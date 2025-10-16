import 'package:flutter/cupertino.dart';
import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

import '../models/board.dart';
import '../models/column.dart' as deck;
import '../models/card_item.dart';
import '../models/label.dart';
import '../models/user_ref.dart';
import '../services/nextcloud_deck_api.dart';

class AppState extends ChangeNotifier {
  final storage = const FlutterSecureStorage();
  final CupertinoTabController tabController = CupertinoTabController(initialIndex: 1);
  final Box cache = Hive.box('nextdeck_cache');

  bool _initialized = false;
  bool _isDarkMode = false;
  int _themeIndex = 0;
  bool _smartColors = true;
  bool _showDescriptionText = true;
  bool _overviewShowBoardInfo = true; // show board stats in overview
  String? _localeCode; // 'de' | 'en' | 'es' | null for system
  bool _isSyncing = false;
  String? _baseUrl;
  String? _username;
  String? _password;
  Timer? _syncTimer;
  bool _localMode = false;
  static const int localBoardId = -1;
  bool _isWarming = false;
  bool _backgroundPreload = false; // user setting: warm stacks in background
  bool _cacheBoardsLocal = true; // user setting: store boards locally + conditional sync
  int _startupTabIndex = 1; // 0=Upcoming,1=Board,2=Overview
  bool _upcomingSingleColumn = false; // user setting: show Upcoming as single list
  int? _defaultBoardId; // user-selected default board for startup
  String _startupBoardMode = 'default'; // 'default' | 'last'

  List<Board> _boards = const [];
  Board? _activeBoard;
  Map<int, List<deck.Column>> _columnsByBoard = {};
  String? _lastError;
  final Set<int> _hiddenBoards = {};
  final Map<int, int> _boardMemberCount = {};
  // Meta Counters per card
  final Map<int, int> _cardCommentsCount = {};
  final Map<int, int> _cardAttachmentsCount = {};
  // Upcoming background scan progress
  bool _upScanActive = false;
  int _upScanTotal = 0;
  int _upScanDone = 0;
  String? _upScanBoardTitle;
  int _upScanSeq = 0;

  bool get isDarkMode => _isDarkMode;
  int get themeIndex => _themeIndex;
  bool get smartColors => _smartColors;
  bool get showDescriptionText => _showDescriptionText;
  bool get overviewShowBoardInfo => _overviewShowBoardInfo;
  String? get localeCode => _localeCode;
  bool get isSyncing => _isSyncing;
  bool get isWarming => _isWarming;
  bool get backgroundPreload => _backgroundPreload;
  bool get cacheBoardsLocal => _cacheBoardsLocal;
  int get startupTabIndex => _startupTabIndex;
  bool get upcomingSingleColumn => _upcomingSingleColumn;
  String? get baseUrl => _baseUrl;
  String? get username => _username;
  bool get localMode => _localMode;
  Board? get activeBoard => _activeBoard;
  int? get defaultBoardId => _defaultBoardId;
  String get startupBoardMode => _startupBoardMode;
  bool get startupUsesDefault => _startupBoardMode != 'last';
  List<Board> get boards => _boards;
  List<deck.Column> columnsForActiveBoard() =>
      _activeBoard == null ? [] : (_columnsByBoard[_activeBoard!.id] ?? []);
  List<deck.Column> columnsForBoard(int boardId) => _columnsByBoard[boardId] ?? [];
  String? get lastError => _lastError;
  bool isBoardHidden(int id) => _hiddenBoards.contains(id);
  int? boardMemberCount(int boardId) => _boardMemberCount[boardId];
  int? commentsCountFor(int cardId) => _cardCommentsCount[cardId];
  int? attachmentsCountFor(int cardId) => _cardAttachmentsCount[cardId];
  bool get upcomingScanActive => _upScanActive;
  int get upcomingScanTotal => _upScanTotal;
  int get upcomingScanDone => _upScanDone;
  String? get upcomingScanBoardTitle => _upScanBoardTitle;
  void setCardCommentsCount(int cardId, int count) {
    _cardCommentsCount[cardId] = count < 0 ? 0 : count;
    notifyListeners();
  }
  void setCardAttachmentsCount(int cardId, int count) {
    _cardAttachmentsCount[cardId] = count < 0 ? 0 : count;
    notifyListeners();
  }

  final api = NextcloudDeckApi();

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _isDarkMode = (await storage.read(key: 'dark')) == '1';
    _themeIndex = int.tryParse(await storage.read(key: 'themeIndex') ?? '') ?? 0;
    _smartColors = (await storage.read(key: 'smartColors')) != '0';
    _showDescriptionText = (await storage.read(key: 'showDescriptionText')) != '0';
    _backgroundPreload = (await storage.read(key: 'bg_preload')) == '1';
    _cacheBoardsLocal = (await storage.read(key: 'cache_boards_local')) != '0';
    _upcomingSingleColumn = (await storage.read(key: 'up_single')) == '1';
    _overviewShowBoardInfo = (await storage.read(key: 'overview_board_info')) != '0';
    _localMode = (await storage.read(key: 'local_mode')) == '1';
    _localeCode = await storage.read(key: 'locale');
    _baseUrl = await storage.read(key: 'baseUrl');
    _defaultBoardId = int.tryParse(await storage.read(key: 'defaultBoardId') ?? '');
    final sbm = await storage.read(key: 'startup_board_mode');
    if (sbm == 'default' || sbm == 'last') { _startupBoardMode = sbm!; }
    // Enforce HTTPS: normalize any stored base URL to https
    if (_baseUrl != null) {
      final normalized = _normalizeHttps(_baseUrl!);
      if (normalized != _baseUrl) {
        _baseUrl = normalized;
        await storage.write(key: 'baseUrl', value: _baseUrl);
      }
    }
    _username = await storage.read(key: 'username');
    _password = await storage.read(key: 'password');
    _startupTabIndex = int.tryParse(await storage.read(key: 'startup_tab') ?? '')?.clamp(0, 2) ?? 1;
    final activeBoardIdStr = await storage.read(key: 'activeBoardId');
    if (_localMode) {
      _setupLocalBoard();
      notifyListeners();
      return;
    }
    if (_baseUrl != null && _username != null && _password != null) {
      _hydrateFromCache();
      try {
        await refreshBoards();
      } catch (_) {
        // Ignorieren beim Start; Nutzer kann in den Einstellungen erneut testen
      }
      // Kein großer Autosync beim Start – Nutzer kann manuell in „Anstehend“ aktualisieren.
      // Startup board selection based on user preference
      if (_startupBoardMode == 'default') {
        if (_defaultBoardId != null && _boards.any((b) => b.id == _defaultBoardId)) {
          _activeBoard = _boards.firstWhere((b) => b.id == _defaultBoardId);
        } else if (activeBoardIdStr != null) {
          final id = int.tryParse(activeBoardIdStr);
          _activeBoard = _boards.firstWhere(
            (b) => b.id == id,
            orElse: () => _boards.isEmpty ? Board.empty() : _boards.first,
          );
        }
      } else { // 'last'
        if (activeBoardIdStr != null) {
          final id = int.tryParse(activeBoardIdStr);
          _activeBoard = _boards.firstWhere(
            (b) => b.id == id,
            orElse: () {
              if (_defaultBoardId != null && _boards.any((b) => b.id == _defaultBoardId)) {
                return _boards.firstWhere((b) => b.id == _defaultBoardId);
              }
              return _boards.isNotEmpty ? _boards.first : Board.empty();
            },
          );
        } else if (_defaultBoardId != null && _boards.any((b) => b.id == _defaultBoardId)) {
          _activeBoard = _boards.firstWhere((b) => b.id == _defaultBoardId);
        }
      }

      if (_activeBoard != null) {
        await storage.write(key: 'activeBoardId', value: _activeBoard!.id.toString());
        cache.put('activeBoardId', _activeBoard!.id);
        final cachedCols = cache.get('columns_${_activeBoard!.id}');
        if (cachedCols is List) {
          _columnsByBoard[_activeBoard!.id] = _parseCachedColumns(cachedCols);
        }
      } else if (_activeBoard == null && _boards.isNotEmpty) {
        // Kein aktives Board gesetzt, aber Boards vorhanden: erstes wählen
        _activeBoard = _boards.first;
        await storage.write(key: 'activeBoardId', value: _activeBoard!.id.toString());
        cache.put('activeBoardId', _activeBoard!.id);
        final cachedCols = cache.get('columns_${_activeBoard!.id}');
        if (cachedCols is List) {
          _columnsByBoard[_activeBoard!.id] = _parseCachedColumns(cachedCols);
        }
      }
    }
    // Wenn keine Zugangsdaten gesetzt sind (und nicht im lokalen Modus), zur Einstellungs-Registerkarte springen
    if (!_localMode && (_baseUrl == null || _username == null || _password == null)) {
      tabController.index = 3; // Settings tab
    }
    // Apply preferred startup tab if credentials vorhanden oder im lokalen Modus
    if (_localMode || (_baseUrl != null && _username != null && _password != null)) {
      tabController.index = _startupTabIndex;
    }
    notifyListeners();
    _startAutoSync();
  }

  /// Background warm-up of columns and cards for all non-archived boards.
  /// Best-effort: respects existing caches and lazy flags; avoids duplicate fetches.
  Future<void> warmAllBoards({int boardConcurrency = 3, int listConcurrency = 3}) async {
    if (_localMode) return;
    if (_baseUrl == null || _username == null || _password == null) return;
    if (_isWarming) return;
    _isWarming = true;
    notifyListeners();
    try {
      final active = List<Board>.from(_boards.where((b) => !b.archived));
      // Prioritize active board first in warm-up order
      final aid = _activeBoard?.id;
      if (aid != null) {
        active.sort((a, b) => (a.id == aid ? -1 : (b.id == aid ? 1 : 0)));
      }
      // Process boards in small batches; nur Spalten (Stacks) laden, Karten lazy
      for (int bi = 0; bi < active.length; bi += boardConcurrency) {
        final slice = active.skip(bi).take(boardConcurrency).toList();
        await Future.wait(slice.map((b) async {
          try {
            // Spalten schlank laden (lazyCards=true) und cachen; send If-Modified-Since, merge partial updates
            final fetched = await api.fetchColumns(_baseUrl!, _username!, _password!, b.id, lazyCards: true);
            final prev = _columnsByBoard[b.id] ?? const <deck.Column>[];
            final merged = [
              for (final p in prev)
                () {
                  final idx = fetched.indexWhere((x) => x.id == p.id);
                  if (idx >= 0) {
                    final nc = fetched[idx];
                    final cards = nc.cards.isNotEmpty ? nc.cards : p.cards;
                    return deck.Column(id: nc.id, title: nc.title, cards: cards);
                  } else {
                    return p;
                  }
                }(),
              for (final nc in fetched)
                if (!prev.any((p) => p.id == nc.id)) deck.Column(id: nc.id, title: nc.title, cards: nc.cards),
            ];
            _columnsByBoard[b.id] = merged;
            cache.put('columns_${b.id}', merged.map((c) => {
              'id': c.id,
              'title': c.title,
              'cards': c.cards
                  .map((k) => {
                        'id': k.id,
                        'title': k.title,
                        'description': k.description,
                        'duedate': k.due?.toUtc().millisecondsSinceEpoch,
                        'labels': k.labels
                            .map((l) => {'id': l.id, 'title': l.title, 'color': l.color})
                            .toList(),
                      })
                  .toList(),
            }).toList());
          } catch (_) {}
        }));
      }
    } finally {
      _isWarming = false;
      notifyListeners();
      _rebuildUpcomingCacheFromMemory();
    }
  }

  void _rebuildUpcomingCacheFromMemory() {
    try {
      final now = DateTime.now();
      final startToday = DateTime(now.year, now.month, now.day);
      final endToday = startToday.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
      final startTomorrow = startToday.add(const Duration(days: 1));
      final endTomorrow = startToday.add(const Duration(days: 2)).subtract(const Duration(milliseconds: 1));
      final end7 = startToday.add(const Duration(days: 8)).subtract(const Duration(milliseconds: 1));
      final o = <Map<String, int>>[];
      final t = <Map<String, int>>[];
      final tm = <Map<String, int>>[];
      final n7 = <Map<String, int>>[];
      final l = <Map<String, int>>[];
      for (final b in _boards.where((b) => !b.archived)) {
        final cols = _columnsByBoard[b.id] ?? const <deck.Column>[];
        for (final c in cols) {
          final ct = c.title.toLowerCase();
          if (ct.contains('done') || ct.contains('erledigt')) continue; // exclude done columns
          for (final k in c.cards) {
            final due = k.due;
            if (due == null) continue;
            final entry = {
              'b': b.id,
              's': c.id,
              'c': k.id,
              'd': due.toUtc().millisecondsSinceEpoch,
            };
            if (due.isBefore(now)) {
              o.add(entry);
            } else if (!due.isBefore(startToday) && !due.isAfter(endToday)) {
              t.add(entry);
            } else if (!due.isBefore(startTomorrow) && !due.isAfter(endTomorrow)) {
              tm.add(entry);
            } else if (due.isAfter(endTomorrow) && !due.isAfter(end7)) {
              n7.add(entry);
            } else if (due.isAfter(end7)) {
              l.add(entry);
            }
          }
        }
      }
      cache.put('upcoming_cache', {
        'ts': DateTime.now().millisecondsSinceEpoch,
        'overdue': o,
        'today': t,
        'tomorrow': tm,
        'next7': n7,
        'later': l,
      });
    } catch (_) {}
  }

  /// Background scan to build a complete Upcoming view across all (non-archived, non-hidden) boards.
  /// Only processes boards that actually require work (changed since last board list, or missing local data).
  /// Counter reflects already up-to-date boards immediately.
  Future<void> scanUpcoming({bool force = false, int listConcurrency = 1}) async {
    if (_localMode) return;
    if (_baseUrl == null || _username == null || _password == null) return;
    // Global throttle: do not start a new scan more often than every 10s unless forced
    final lastRun = cache.get('up_scan_last');
    final int? lastRunMs = lastRun is int ? lastRun : (lastRun is num ? lastRun.toInt() : null);
    final nowMs0 = DateTime.now().millisecondsSinceEpoch;
    if (!force && lastRunMs != null && (nowMs0 - lastRunMs) < 10000) {
      return;
    }
    cache.put('up_scan_last', nowMs0);
    if (_upScanActive && !force) return;
    _upScanActive = true;
    final mySeq = ++_upScanSeq;
    final boards = _boards.where((b) => !b.archived && !_hiddenBoards.contains(b.id)).toList();
    // Prioritize active board first
    final aid = _activeBoard?.id;
    if (aid != null) {
      boards.sort((a, b) => (a.id == aid ? -1 : (b.id == aid ? 1 : 0)));
    }
    _upScanTotal = boards.length;
    // Decide which boards actually need processing
    final toProcess = <Board>[];
    final changedList = <Board>[];
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (_cacheBoardsLocal && !force) {
      // Periodic rescan disabled to avoid unnecessary syncs if lastModified is unchanged
      for (final b in boards) {
        final cols = _columnsByBoard[b.id] ?? const <deck.Column>[];
        final hasAnyCards = cols.any((c) => c.cards.isNotEmpty);
        final colsEmpty = cols.isEmpty;
        // Compare lastModified markers (curr vs prev) set in refreshBoards()
        final curr = cache.get('board_lastmod_${b.id}');
        final prev = cache.get('board_lastmod_prev_${b.id}');
        int? currMs = curr is int ? curr : (curr is num ? curr.toInt() : null);
        int? prevMs = prev is int ? prev : (prev is num ? prev.toInt() : null);
        final bool changed = (currMs != null && prevMs != null) ? (currMs > prevMs) : false;
        final lastScan = cache.get('board_scan_ts_${b.id}');
        final int? lastScanMs = lastScan is int ? lastScan : (lastScan is num ? lastScan.toInt() : null);
        final bool needsInitial = colsEmpty || (!hasAnyCards && lastScanMs == null);
        // Treat boards with missing prev marker as needing initial processing (to align markers)
        final bool prevMissing = (prevMs == null && currMs != null && lastScanMs == null);
        // Cooldown for changed boards to avoid hammering servers that bump lastModified frequently
        final bool changedDue = changed && (lastScanMs == null || (nowMs - lastScanMs) > 120000); // >= 2 min
        if (changedDue || needsInitial || prevMissing) {
          toProcess.add(b);
        }
        if (changedDue) changedList.add(b);
      }
      // Middle ground: also refresh a tiny rotating subset of "unchanged" boards to catch due-date-only changes.
      final staleCandidates = boards.where((b) => !toProcess.any((x) => x.id == b.id)).where((b) {
        final lastScan = cache.get('board_scan_ts_${b.id}');
        final int? lastScanMs = lastScan is int ? lastScan : (lastScan is num ? lastScan.toInt() : null);
        // Consider stale if not scanned within the past 15 minutes
        return lastScanMs == null || (nowMs - lastScanMs) > 15 * 60 * 1000;
      }).toList();
      // Keine Stale-Rotation im Hintergrund, wenn nichts geändert wurde
    } else {
      // Without local caching, keep current behavior: process all
      toProcess.addAll(boards);
    }
    // If forced, process all boards. Else, process only changed; otherwise do nothing.
    final List<Board> processNow = force
        ? List<Board>.from(boards)
        : (changedList.isNotEmpty ? List<Board>.from(changedList) : const <Board>[]);
    // Counter zeigt immer die Gesamtzahl der sichtbaren Boards
    _upScanTotal = boards.length;
    // Bereits "up-to-date" Boards zählen wir sofort als erledigt,
    // damit der Zähler nicht bei 0/x startet, wenn nur wenige Boards zu verarbeiten sind.
    final baselineDone = (_upScanTotal - processNow.length).clamp(0, _upScanTotal);
    _upScanDone = baselineDone;
    _upScanBoardTitle = null;
    notifyListeners();
    try {
      final activeId = _activeBoard?.id;
      final int pool = force ? 1 : 2;
      for (int i = 0; i < processNow.length; i += pool) {
        if (mySeq != _upScanSeq) break;
        final chunk = processNow.skip(i).take(pool).toList();
        for (final b in chunk) {
          _upScanBoardTitle = b.title;
          _upScanDone = (_upScanDone + 1).clamp(0, _upScanTotal);
        }
        notifyListeners();
        await Future.wait(chunk.map((b) async {
          if (mySeq != _upScanSeq) return;
          if (b.id != activeId) {
            final hadAnyPre = (_columnsByBoard[b.id] ?? const <deck.Column>[]).any((c) => c.cards.isNotEmpty);
          final lastFetch = cache.get('stacks_fetch_ts_${b.id}');
          final int? lastFetchMs = lastFetch is int ? lastFetch : (lastFetch is num ? lastFetch.toInt() : null);
            final nowMs2 = DateTime.now().millisecondsSinceEpoch;
            final bool recentStacks = lastFetchMs != null && (nowMs2 - lastFetchMs) < 5 * 60 * 1000;
            if (force || (!_stacksLoadingBoards.contains(b.id) && !recentStacks)) {
              _stacksLoadingBoards.add(b.id);
              try {
                if (_cacheBoardsLocal) {
                  final etagKey = 'etag_stacks_${b.id}';
                  final prevEtag = cache.get(etagKey) as String?;
                  FetchStacksResult? res;
                  try {
                    res = await api.fetchStacksWithEtag(_baseUrl!, _username!, _password!, b.id, ifNoneMatch: prevEtag, priority: false);
                  } catch (_) {}
                  if (res != null && !res.notModified) {
                    final prev = _columnsByBoard[b.id] ?? const <deck.Column>[];
                    final merged = [
                      // update or keep previous stacks
                      for (final p in prev)
                        () {
                          final idx = res!.columns.indexWhere((x) => x.id == p.id);
                          if (idx >= 0) {
                            final nc = res!.columns[idx];
                            final cards = nc.cards.isNotEmpty ? nc.cards : p.cards;
                            return deck.Column(id: nc.id, title: nc.title, cards: cards);
                          } else {
                            return p;
                          }
                        }(),
                      // add any new stacks not previously present
                      for (final nc in res.columns)
                        if (!prev.any((p) => p.id == nc.id)) deck.Column(id: nc.id, title: nc.title, cards: nc.cards),
                    ];
                    _columnsByBoard[b.id] = merged;
                    cache.put('columns_${b.id}', merged.map((c) => {
                      'id': c.id,
                      'title': c.title,
                      'cards': c.cards.map((k) => {
                        'id': k.id,
                        'title': k.title,
                        'description': k.description,
                        'duedate': k.due?.toUtc().millisecondsSinceEpoch,
                        'labels': k.labels.map((l) => {'id': l.id, 'title': l.title, 'color': l.color}).toList(),
                      }).toList(),
                    }).toList());
                    if (res.etag != null) cache.put(etagKey, res.etag);
                  } else {
                    // Not modified (or failed) but we might not have columns yet: fetch baseline stacks without ETag
                    if ((_columnsByBoard[b.id] ?? const <deck.Column>[]).isEmpty) {
                      try {
                        final fetched = await api.fetchColumns(_baseUrl!, _username!, _password!, b.id, lazyCards: true);
                        final prev = _columnsByBoard[b.id] ?? const <deck.Column>[];
                        final merged = [
                          for (final p in prev)
                            () {
                              final idx = fetched.indexWhere((x) => x.id == p.id);
                              if (idx >= 0) {
                                final nc = fetched[idx];
                                final cards = nc.cards.isNotEmpty ? nc.cards : p.cards;
                                return deck.Column(id: nc.id, title: nc.title, cards: cards);
                              } else {
                                return p;
                              }
                            }(),
                          for (final nc in fetched)
                            if (!prev.any((p) => p.id == nc.id)) deck.Column(id: nc.id, title: nc.title, cards: nc.cards),
                        ];
                        _columnsByBoard[b.id] = merged;
                        cache.put('columns_${b.id}', merged.map((c) => {
                          'id': c.id,
                          'title': c.title,
                          'cards': c.cards.map((k) => {
                            'id': k.id,
                            'title': k.title,
                            'description': k.description,
                            'duedate': k.due?.toUtc().millisecondsSinceEpoch,
                            'labels': k.labels.map((l) => {'id': l.id, 'title': l.title, 'color': l.color}).toList(),
                          }).toList(),
                        }).toList());
                      } catch (_) {}
                    }
                  }
                } else {
                  if ((_columnsByBoard[b.id] ?? const <deck.Column>[]).isEmpty) {
                    try { await refreshColumnsFor(b); } catch (_) {}
                  }
                }
                // Light background when not forced
                if (!force) {
                  try { await _ensureSomeCardsForBoard(b.id, limit: 2); } catch (_) {}
                }
                // If this scan is user-forced, aggressively refresh cards for all non-done stacks to update Upcoming immediately
                if (force) {
                  try {
                    // For forced scans, prefer a single board-wide columns fetch with inline cards
                    // to avoid N-per-stack requests on servers without card list endpoints.
                    final fetched = await api.fetchColumns(_baseUrl!, _username!, _password!, b.id, lazyCards: false, priority: false, bypassCooldown: true);
                    final prev = _columnsByBoard[b.id] ?? const <deck.Column>[];
                    final merged = _mergeColumnsReplaceChangedForBoard(b.id, prev, fetched);
                    _columnsByBoard[b.id] = merged;
                    cache.put('columns_${b.id}', merged.map((c) => {
                      'id': c.id,
                      'title': c.title,
                      'cards': c.cards.map((k) => {
                        'id': k.id,
                        'title': k.title,
                        'description': k.description,
                        'duedate': k.due?.toUtc().millisecondsSinceEpoch,
                        'labels': k.labels.map((l) => {'id': l.id, 'title': l.title, 'color': l.color}).toList(),
                      }).toList(),
                    }).toList());
                  } catch (_) {}
                }
              } finally {
                cache.put('stacks_fetch_ts_${b.id}', DateTime.now().millisecondsSinceEpoch);
                _stacksLoadingBoards.remove(b.id);
              }
            }
            // Karten nicht im Hintergrund scanUpcoming() nachladen – hält Netzlast niedrig.
          }
          cache.put('board_scan_ts_${b.id}', DateTime.now().millisecondsSinceEpoch);
          // Nach erfolgreicher Verarbeitung gilt der aktuelle lastModified-Stand als abgearbeitet.
          final curr = cache.get('board_lastmod_${b.id}');
          final int? currMs = curr is int ? curr : (curr is num ? curr.toInt() : null);
          if (currMs != null) {
            cache.put('board_lastmod_prev_${b.id}', currMs);
          }
          _rebuildUpcomingCacheFromMemory();
          notifyListeners();
        }));
        await Future.delayed(const Duration(milliseconds: 40));
      }
    } finally {
      if (mySeq == _upScanSeq) {
        _upScanActive = false;
        _upScanBoardTitle = null;
        notifyListeners();
      }
    }
  }

  /// Full, sequential sync of all boards (stacks + cards) regardless of lastModified.
  /// Intended for manual refresh from Upcoming: minimizes surprises by avoiding throttles and running serially.
  Future<void> syncAllBoardsNow() async {
    if (_localMode) return;
    if (_baseUrl == null || _username == null || _password == null) return;
    // Initialize progress as in Upcoming
    final boards = _boards.where((b) => !b.archived && !_hiddenBoards.contains(b.id)).toList();
    _upScanActive = true;
    _upScanTotal = boards.length;
    _upScanDone = 0;
    _upScanBoardTitle = null;
    notifyListeners();
    try {
      for (final b in boards) {
        // Indicate current board while syncing; count as done after completion
        _upScanBoardTitle = b.title;
        notifyListeners();
        try {
          // Single call per board to fetch stacks WITH cards; bypass cooldowns to ensure freshness.
          final fetched = await api.fetchColumns(_baseUrl!, _username!, _password!, b.id, lazyCards: false, priority: false, bypassCooldown: true);
          final prev = _columnsByBoard[b.id] ?? const <deck.Column>[];
          final merged0 = _mergeColumnsReplaceChangedForBoard(b.id, prev, fetched);
          _columnsByBoard[b.id] = merged0;
          cache.put('columns_${b.id}', merged0.map((c) => {
            'id': c.id,
            'title': c.title,
            'cards': c.cards.map((k) => {
              'id': k.id,
              'title': k.title,
              'description': k.description,
              'duedate': k.due?.toUtc().millisecondsSinceEpoch,
              'labels': k.labels.map((l) => {'id': l.id, 'title': l.title, 'color': l.color}).toList(),
            }).toList(),
          }).toList());
        } catch (_) {
          // Fallback: best-effort stacks (lazy) then ensure a few cards
          try { await refreshColumnsFor(b); } catch (_) {}
          try { await _ensureSomeCardsForBoard(b.id, limit: 3); } catch (_) {}
        }
        // Rebuild Upcoming cache incrementally to reflect progress
        _rebuildUpcomingCacheFromMemory();
        _upScanDone = (_upScanDone + 1).clamp(0, _upScanTotal);
        notifyListeners();
      }
    } finally {
      _upScanActive = false;
      _upScanBoardTitle = null;
      notifyListeners();
    }
  }

  /// Parallel full sync for many boards with bounded concurrency.
  /// Fetches stacks WITH cards for each board (bypass cooldowns), updates cache and
  /// rebuilds Upcoming incrementally. Optimized for large board counts (e.g., 150).
  Future<void> syncAllBoardsFast({int concurrency = 6}) async {
    if (_localMode) return;
    if (_baseUrl == null || _username == null || _password == null) return;
    final boards = _boards.where((b) => !b.archived && !_hiddenBoards.contains(b.id)).toList();
    if (boards.isEmpty) return;
    // Bounded parallelism for speed; keep within safe range
    final pool = concurrency.clamp(2, 8);
    _upScanActive = true;
    _upScanTotal = boards.length;
    _upScanDone = 0;
    _upScanBoardTitle = null;
    notifyListeners();
    try {
      for (int i = 0; i < boards.length; i += pool) {
        final chunk = boards.skip(i).take(pool).toList();
        await Future.wait(chunk.map((b) async {
          // Indicate current board; increment 'done' after completion to reflect real progress
          _upScanBoardTitle = b.title;
          notifyListeners();
          try {
            final isActive = (_activeBoard?.id == b.id);
            final fetched = await api.fetchColumns(
              _baseUrl!, _username!, _password!, b.id,
              lazyCards: false, priority: isActive, bypassCooldown: true,
            );
            final prev = _columnsByBoard[b.id] ?? const <deck.Column>[];
            final merged = _mergeColumnsReplaceChangedForBoard(b.id, prev, fetched);
            _columnsByBoard[b.id] = merged;
            cache.put('columns_${b.id}', merged.map((c) => {
              'id': c.id,
              'title': c.title,
              'cards': c.cards.map((k) => {
                'id': k.id,
                'title': k.title,
                'description': k.description,
                'duedate': k.due?.toUtc().millisecondsSinceEpoch,
                'labels': k.labels.map((l) => {'id': l.id, 'title': l.title, 'color': l.color}).toList(),
              }).toList(),
            }).toList());
          } catch (_) {
            // Fallback for problematic boards: fetch stacks lazily and ensure a few cards
            try { await refreshColumnsFor(b); } catch (_) {}
            try { await _ensureSomeCardsForBoard(b.id, limit: 3); } catch (_) {}
          }
          // Rebuild Upcoming cache incrementally and yield a tiny gap to keep UI responsive
          _rebuildUpcomingCacheFromMemory();
          _upScanDone = (_upScanDone + 1).clamp(0, _upScanTotal);
          notifyListeners();
          await Future.delayed(const Duration(milliseconds: 10));
        }));
      }
    } finally {
      _upScanActive = false;
      _upScanBoardTitle = null;
      notifyListeners();
    }
  }

  Map<String, List<Map<String, int>>>? upcomingCacheRefs() {
    final m = cache.get('upcoming_cache');
    if (m is Map) {
      try {
        return {
          'overdue': (m['overdue'] as List).cast<Map>().map((e) => (e as Map).cast<String, int>()).toList(),
          'today': (m['today'] as List).cast<Map>().map((e) => (e as Map).cast<String, int>()).toList(),
          'tomorrow': (m['tomorrow'] as List).cast<Map>().map((e) => (e as Map).cast<String, int>()).toList(),
          'next7': (m['next7'] as List).cast<Map>().map((e) => (e as Map).cast<String, int>()).toList(),
          'later': (m['later'] as List).cast<Map>().map((e) => (e as Map).cast<String, int>()).toList(),
        };
      } catch (_) {}
    }
    return null;
  }

  void setDarkMode(bool value) {
    _isDarkMode = value;
    storage.write(key: 'dark', value: value ? '1' : '0');
    notifyListeners();
  }

  void setThemeIndex(int index) {
    _themeIndex = index.clamp(0, 4);
    storage.write(key: 'themeIndex', value: _themeIndex.toString());
    notifyListeners();
  }

  void setSmartColors(bool value) {
    _smartColors = value;
    storage.write(key: 'smartColors', value: value ? '1' : '0');
    notifyListeners();
  }

  void setShowDescriptionText(bool value) {
    _showDescriptionText = value;
    storage.write(key: 'showDescriptionText', value: value ? '1' : '0');
    notifyListeners();
  }

  void setOverviewShowBoardInfo(bool value) {
    _overviewShowBoardInfo = value;
    storage.write(key: 'overview_board_info', value: value ? '1' : '0');
    notifyListeners();
  }

  void setLocale(String? code) {
    // code must be one of 'de','en','es' or null for system
    if (code != null && code != 'de' && code != 'en' && code != 'es') return;
    _localeCode = code;
    if (code == null) {
      storage.delete(key: 'locale');
    } else {
      storage.write(key: 'locale', value: code);
    }
    notifyListeners();
  }

  void selectTab(int index) {
    tabController.index = index;
    // On Board tab (index 1 in current layout), refresh meta counters in background
    if (index == 1) {
      final b = _activeBoard;
      if (b != null && _baseUrl != null && _username != null && _password != null) {
        // Lightweight: refresh stacks first (priority), then meta in background
        unawaited(() async {
          try { await refreshColumnsFor(b); } catch (_) {}
          await refreshActiveBoardMeta();
        }());
      }
    }
  }

  Future<void> setLocalMode(bool enabled) async {
    _localMode = enabled;
    await storage.write(key: 'local_mode', value: enabled ? '1' : '0');
    if (enabled) {
      // Clear credentials to avoid accidental network
      _baseUrl = null; _username = null; _password = null;
      await storage.delete(key: 'baseUrl');
      await storage.delete(key: 'username');
      await storage.delete(key: 'password');
      _stopAutoSync();
      _setupLocalBoard();
    } else {
      // Leave it to user to re-enter credentials; clear boards
      _boards = const [];
      _activeBoard = null;
      _columnsByBoard.clear();
    }
    notifyListeners();
  }

  void _setupLocalBoard() {
    // Build a simple default local board with three columns if missing
    final existing = _columnsByBoard[localBoardId];
    if (existing == null || existing.isEmpty) {
      final initCols = [
        deck.Column(id: -101, title: 'To Do', cards: const []),
        deck.Column(id: -102, title: 'In Arbeit', cards: const []),
        deck.Column(id: -103, title: 'Erledigt', cards: const []),
      ];
      _columnsByBoard[localBoardId] = initCols;
      cache.put('columns_$localBoardId', initCols.map((c) => {'id': c.id, 'title': c.title, 'cards': const []}).toList());
    }
    _boards = [Board(id: localBoardId, title: 'Lokales Board', archived: false)];
    _activeBoard = _boards.first;
    storage.write(key: 'activeBoardId', value: localBoardId.toString());
    cache.put('activeBoardId', localBoardId);
    cache.put('boards', _boards.map((b) => {'id': b.id, 'title': b.title, 'archived': b.archived}).toList());
  }

  void setCredentials({required String baseUrl, required String username, required String password}) {
    _localMode = false;
    storage.write(key: 'local_mode', value: '0');
    final prevBase = _baseUrl;
    final prevUser = _username;
    final nextBase = _normalizeHttps(baseUrl);
    final nextUser = username.trim();
    final changedServer = prevBase != null && prevUser != null && (prevBase != nextBase || prevUser != nextUser);
    _baseUrl = nextBase;
    _username = nextUser;
    _password = password;
    storage.write(key: 'baseUrl', value: _baseUrl);
    storage.write(key: 'username', value: _username);
    storage.write(key: 'password', value: _password);
    if (changedServer) {
      _clearAllServerCaches();
    }
    notifyListeners();
  }

  void _clearAllServerCaches() {
    try {
      // Clear persisted keys
      final keys = cache.keys.toList();
      for (final k in keys) {
        if (k is String) {
          if (k == 'boards' || k == 'activeBoardId' || k == 'hiddenBoards' || k == 'upcoming_cache') {
            cache.delete(k);
          }
          if (k.startsWith('columns_') ||
              k.startsWith('etag_stacks_') ||
              k.startsWith('board_members_') ||
              k.startsWith('board_lastmod_') ||
              k.startsWith('board_lastmod_prev_')) {
            cache.delete(k);
          }
        }
      }
      // Clear in-memory state
      _boards = const [];
      _activeBoard = null;
      _columnsByBoard.clear();
      _hiddenBoards.clear();
      _boardMemberCount.clear();
      _cardCommentsCount.clear();
      _cardAttachmentsCount.clear();
      _stackLoaded.clear();
      _stackLoading.clear();
      _upScanActive = false; _upScanDone = 0; _upScanTotal = 0; _upScanBoardTitle = null;
      // Reset default board selection for new server
      _defaultBoardId = null;
      storage.delete(key: 'defaultBoardId');
    } catch (_) {}
  }

  // Ensure we always talk HTTPS regardless of user input
  String _normalizeHttps(String input) {
    var v = input.trim();
    if (v.isEmpty) return v;
    if (v.startsWith('http://')) v = 'https://' + v.substring(7);
    if (!v.startsWith('https://')) v = 'https://' + v.replaceFirst(RegExp(r'^/+'), '');
    // Remove trailing slash to avoid double slashes when building paths
    if (v.endsWith('/')) v = v.substring(0, v.length - 1);
    return v;
  }

  Future<bool> testLogin() async {
    if (_baseUrl == null || _username == null || _password == null) return false;
    return api.testLogin(_baseUrl!, _username!, _password!);
  }

  Future<void> refreshBoards() async {
    if (_localMode) return;
    if (_baseUrl == null || _username == null || _password == null) return;
    // Load raw to access lastModified and build both: boards list and lastmod map
    final raw = await api.fetchBoardsRaw(_baseUrl!, _username!, _password!);
    _boards = raw.map((m) => Board.fromJson(m)).toList();
    // Cache Boards schlank ablegen (inkl. Farbe/archived, falls vorhanden)
    cache.put('boards', _boards.map((b) => {
          'id': b.id,
          'title': b.title,
          if (b.color != null) 'color': b.color,
          'archived': b.archived,
        }).toList());
    // Extract and persist lastModified per board, compute changed boards list
    final nowMarks = <int, int>{};
    for (final m in raw) {
      final id = (m['id'] as num?)?.toInt();
      if (id == null) continue;
      final lmRaw = m['lastModified'] ?? m['lastmodified'] ?? m['lastActivity'] ?? m['updatedAt'] ?? m['mtime'] ?? m['modified'];
      int? lm;
      if (lmRaw is num) {
        final v = lmRaw.toInt();
        // Heuristic: treat values < 10^12 as seconds
        lm = v < 1000000000000 ? v * 1000 : v;
      } else if (lmRaw is String) {
        final s = lmRaw.trim();
        final asNum = int.tryParse(s);
        if (asNum != null) {
          lm = asNum < 1000000000000 ? asNum * 1000 : asNum;
        } else {
          try { lm = DateTime.parse(s).toUtc().millisecondsSinceEpoch; } catch (_) {}
        }
      }
      if (lm != null) {
        nowMarks[id] = lm;
        cache.put('board_lastmod_$id', lm);
      }
    }
    // Do NOT update the "prev" markers here. We only set
    // board_lastmod_prev_* after a board was processed in scanUpcoming().
    // This allows scanUpcoming() to detect changed boards reliably.
    // Prune hidden list to existing boards
    _hiddenBoards.removeWhere((id) => !_boards.any((b) => b.id == id));
    cache.put('hiddenBoards', _hiddenBoards.toList());
    // If default board no longer exists, clear default
    if (_defaultBoardId != null && !_boards.any((b) => b.id == _defaultBoardId)) {
      _defaultBoardId = null;
      await storage.delete(key: 'defaultBoardId');
    }
    // Wenn das aktive Board nicht mehr existiert (z. B. serverseitig gelöscht), umschalten
    if (_activeBoard != null && !_boards.any((b) => b.id == _activeBoard!.id)) {
      final removedId = _activeBoard!.id;
      _activeBoard = _boards.isNotEmpty ? _boards.first : null;
      if (_activeBoard != null) {
        storage.write(key: 'activeBoardId', value: _activeBoard!.id.toString());
        cache.put('activeBoardId', _activeBoard!.id);
        // Vorherige Spalten/Caches des entfernten Boards wegräumen
        _columnsByBoard.remove(removedId);
        cache.delete('columns_$removedId');
        cache.delete('board_members_$removedId');
        // Spalten des neuen aktiven Boards nachladen (lazy Cards)
        unawaited(refreshColumnsFor(_activeBoard!));
      } else {
        // Keine Boards mehr vorhanden
        storage.write(key: 'activeBoardId', value: '');
        cache.delete('activeBoardId');
        _columnsByBoard.clear();
      }
    }
    notifyListeners();

    // Hintergrund-Refresh ausgelagert: scanUpcoming() verarbeitet geänderte Boards gezielt.
  }

  Future<void> ensureBoardMemberCount(int boardId) async {
    if (_baseUrl == null || _username == null || _password == null) return;
    if (_boardMemberCount.containsKey(boardId)) return;
    try {
      // Try cache first
      final cached = cache.get('board_members_$boardId');
      if (cached is int) {
        _boardMemberCount[boardId] = cached;
        notifyListeners();
        return;
      }
      final uids = await api.fetchBoardMemberUids(_baseUrl!, _username!, _password!, boardId);
      _boardMemberCount[boardId] = uids.length;
      cache.put('board_members_$boardId', uids.length);
      notifyListeners();
    } catch (_) {
      // ignore silently; can retry later
    }
  }

  Future<void> setActiveBoard(Board board) async {
    _activeBoard = board;
    _stackLoaded.clear();
    _stackLoading.clear();
    await storage.write(key: 'activeBoardId', value: board.id.toString());
    cache.put('activeBoardId', board.id);
    await refreshColumnsFor(board);
    notifyListeners();
    _startAutoSync();
  }

  Future<void> setDefaultBoard(Board board) async {
    _defaultBoardId = board.id;
    await storage.write(key: 'defaultBoardId', value: board.id.toString());
    // Do not change the currently active board; applies on next app start based on startup mode
    notifyListeners();
  }

  void setStartupBoardMode(String mode) {
    if (mode != 'default' && mode != 'last') return;
    _startupBoardMode = mode;
    storage.write(key: 'startup_board_mode', value: mode);
    notifyListeners();
  }

  Future<void> refreshColumnsFor(Board board) async {
    if (_localMode) {
      // Already in memory; ensure cached structure exists
      if (_columnsByBoard[board.id] == null) _setupLocalBoard();
      return;
    }
    if (_baseUrl == null || _username == null || _password == null) return;
    // Global throttle: avoid hammering the same board's stacks endpoint
    final throttleKey = 'stacks_fetch_ts_${board.id}';
    final last = cache.get(throttleKey);
    final int? lastMs = last is int ? last : (last is num ? last.toInt() : null);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    // Skip network if we fetched stacks for this board very recently (< 30s)
    if (lastMs != null && (nowMs - lastMs) < 30000) {
      return;
    }
    // Additional in-memory guard (covers cases where cache timestamp is missing/cleared)
    final int? lastMem = _stacksLastFetchMsMem[board.id];
    if (lastMem != null && (nowMs - lastMem) < 30000) {
      return;
    }
    // Coalesce concurrent callers for the same board
    if (_stacksLoadingBoards.contains(board.id)) return;
    _stacksLoadingBoards.add(board.id);
    // Mark intent to fetch to coalesce concurrent callers
    cache.put(throttleKey, nowMs);
    _stacksLastFetchMsMem[board.id] = nowMs;
    try {
      _stackLoaded.clear();
      _stackLoading.clear();
      final isActive = (_activeBoard?.id == board.id);
      if (_cacheBoardsLocal) {
        final etagKey = 'etag_stacks_${board.id}';
        final prevEtag = cache.get(etagKey) as String?;
        try {
          final res = await api.fetchStacksWithEtag(_baseUrl!, _username!, _password!, board.id, ifNoneMatch: prevEtag, priority: isActive);
          if (!res.notModified) {
            // Merge: preserve existing cards if stacks response lacks inline cards
            final prev = _columnsByBoard[board.id] ?? const <deck.Column>[];
            final merged = [
              for (final c in res.columns)
                () {
                  final pm = prev.firstWhere((p) => p.id == c.id, orElse: () => deck.Column(id: c.id, title: c.title, cards: const []));
                  final cards = c.cards.isNotEmpty ? c.cards : pm.cards;
                  return deck.Column(id: c.id, title: c.title, cards: cards);
                }()
            ];
            _columnsByBoard[board.id] = merged;
            cache.put('columns_${board.id}', merged.map((c) => {
                  'id': c.id,
                  'title': c.title,
                  'cards': c.cards
                      .map((k) => {
                            'id': k.id,
                            'title': k.title,
                            'description': k.description,
                            'duedate': k.due?.toUtc().millisecondsSinceEpoch,
                            'labels': k.labels
                                .map((l) => {'id': l.id, 'title': l.title, 'color': l.color})
                                .toList(),
                          })
                      .toList(),
                }).toList());
            if (res.etag != null) cache.put(etagKey, res.etag);
          }
          _lastError = null;
          notifyListeners();
          return;
        } catch (_) {
          // fall back to non-ETag path below
        }
      }
      final cols = await api.fetchColumns(_baseUrl!, _username!, _password!, board.id, lazyCards: true, priority: isActive);
      // Merge with existing to preserve card lists if none inline
      final prev = _columnsByBoard[board.id] ?? const <deck.Column>[];
      final merged = [
        for (final c in cols)
          () {
            final pm = prev.firstWhere((p) => p.id == c.id, orElse: () => deck.Column(id: c.id, title: c.title, cards: const []));
            final cards = c.cards.isNotEmpty ? c.cards : pm.cards;
            return deck.Column(id: c.id, title: c.title, cards: cards);
          }()
      ];
      _columnsByBoard[board.id] = merged;
      cache.put('columns_${board.id}', merged.map((c) => {
            'id': c.id,
            'title': c.title,
            'cards': c.cards
                .map((k) => {
                      'id': k.id,
                      'title': k.title,
                      'description': k.description,
                      'duedate': k.due?.toUtc().millisecondsSinceEpoch,
                      'labels': k.labels
                          .map((l) => {'id': l.id, 'title': l.title, 'color': l.color})
                          .toList(),
                    })
                .toList(),
          }).toList());
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
    } finally {
      _stacksLoadingBoards.remove(board.id);
      _stacksLastFetchMsMem[board.id] = DateTime.now().millisecondsSinceEpoch;
    }
    notifyListeners();
  }

  Future<bool> createStack({required int boardId, required String title}) async {
    if (_localMode) {
      final cols = _columnsByBoard[boardId] ?? const <deck.Column>[];
      final nextId = ((cache.get('local_next_stack_id') as int?) ?? 1000) + 1;
      final updated = [...cols, deck.Column(id: nextId, title: title, cards: const [])];
      _columnsByBoard[boardId] = updated;
      cache.put('local_next_stack_id', nextId);
      cache.put('columns_$boardId', updated.map((c) => {'id': c.id, 'title': c.title, 'cards': const []}).toList());
      notifyListeners();
      return true;
    }
    if (_baseUrl == null || _username == null || _password == null) return false;
    try {
      // Provide a best-effort order: append at end
      final existing = _columnsByBoard[boardId] ?? const <deck.Column>[];
      final order = existing.isEmpty ? 0 : existing.length;
      final created = await api.createStack(_baseUrl!, _username!, _password!, boardId, title: title, order: order);
      if (created != null) {
        final b = _boards.firstWhere((x) => x.id == boardId, orElse: () => Board.empty());
        await refreshColumnsFor(b);
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<Board?> createBoard({required String title, String? color, bool activate = true}) async {
    if (_localMode) {
      // Create a local board stub is out of scope for now
      return null;
    }
    if (_baseUrl == null || _username == null || _password == null) return null;
    try {
      final created = await api.createBoard(_baseUrl!, _username!, _password!, title: title, color: color);
      await refreshBoards();
      if (created != null && activate) {
        final found = _boards.firstWhere((b) => b.id == created.id, orElse: () => created);
        await setActiveBoard(found);
      }
      return created;
    } catch (_) {
      return null;
    }
  }

  void _startAutoSync() {
    _syncTimer?.cancel();
    if (_localMode || _baseUrl == null || _username == null || _password == null) return;
    _syncTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      try {
        // Refresh boards list to detect changed boards (lastModified) and update only those
        await refreshBoards();
        // When on Board tab, also refresh the active board's stacks and lightly ensure some cards
        if (tabController.index == 1) {
          final b = _activeBoard;
          if (b != null) {
            try { await refreshColumnsFor(b); } catch (_) {}
            // Light touch: fetch a couple of empty stacks' cards to keep view fresh
            unawaited(_ensureSomeCardsForBoard(b.id, limit: 2));
          }
        }
        // Kick a light Upcoming scan to process changed boards (ohne Karten-/Meta-Fetch)
        unawaited(scanUpcoming());
        // Kein automatisches Meta-/Karten-Refresh mehr im Timer – das bleibt nutzergetrieben.
      } catch (_) {}
    });
  }

  void _stopAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  void setBackgroundPreload(bool enabled) {
    _backgroundPreload = enabled;
    storage.write(key: 'bg_preload', value: enabled ? '1' : '0');
    // Do not immediately kick off heavy work here; user can use refresh
    notifyListeners();
  }

  void setCacheBoardsLocal(bool enabled) {
    _cacheBoardsLocal = enabled;
    storage.write(key: 'cache_boards_local', value: enabled ? '1' : '0');
    notifyListeners();
  }

  void setStartupTabIndex(int index) {
    final clamped = index.clamp(0, 2);
    _startupTabIndex = clamped;
    storage.write(key: 'startup_tab', value: clamped.toString());
    notifyListeners();
  }

  void setUpcomingSingleColumn(bool value) {
    _upcomingSingleColumn = value;
    storage.write(key: 'up_single', value: value ? '1' : '0');
    notifyListeners();
  }

  final Set<int> _stackLoading = {};
  final Set<int> _stackLoaded = {};
  // Prevent concurrent/redundant stacks fetches per board across different code paths
  final Set<int> _stacksLoadingBoards = {};
  // Extra in-memory throttle to complement persisted timestamps
  final Map<int, int> _stacksLastFetchMsMem = {};
  // Protect freshly modified stacks from being overwritten by background fetches for a short window
  final Map<String, int> _protectStacksUntilMs = {};
  void _protectStack(int boardId, int stackId, {int ms = 10000}) {
    _protectStacksUntilMs['$boardId:$stackId'] = DateTime.now().millisecondsSinceEpoch + ms;
  }
  void _clearStackProtection(int boardId, int stackId) {
    _protectStacksUntilMs.remove('$boardId:$stackId');
  }
  bool _isStackProtected(int boardId, int stackId) {
    final v = _protectStacksUntilMs['$boardId:$stackId'];
    if (v == null) return false;
    if (DateTime.now().millisecondsSinceEpoch > v) { _protectStacksUntilMs.remove('$boardId:$stackId'); return false; }
    return true;
  }

  // Merge utility: replace only stacks present in 'next'; keep others, add new ones.
  // If a stack is protected for this board, keep its previous cards to avoid flicker after local changes.
  List<deck.Column> _mergeColumnsReplaceChangedForBoard(int boardId, List<deck.Column> prev, List<deck.Column> next) {
    final out = <deck.Column>[];
    for (final p in prev) {
      final idx = next.indexWhere((n) => n.id == p.id);
      if (idx >= 0) {
        final n = next[idx];
        if (_isStackProtected(boardId, n.id)) {
          out.add(deck.Column(id: n.id, title: n.title, cards: p.cards));
        } else {
          final cards = n.cards.isNotEmpty ? n.cards : p.cards;
          out.add(deck.Column(id: n.id, title: n.title, cards: cards));
        }
      } else {
        out.add(p);
      }
    }
    for (final n in next) {
      if (!prev.any((p) => p.id == n.id)) out.add(n);
    }
    return out;
  }
  bool isStackLoading(int stackId) => _stackLoading.contains(stackId);
  Future<void> ensureCardsFor(int boardId, int stackId, {bool force = false}) async {
    if (_localMode) return;
    if (_baseUrl == null || _username == null || _password == null) return;
    if (_stackLoading.contains(stackId)) return;
    if (!force && _stackLoaded.contains(stackId)) return;
    final cols = _columnsByBoard[boardId];
    if (cols == null) return;
    final idx = cols.indexWhere((c) => c.id == stackId);
    if (idx < 0) return;
    if (!force && cols[idx].cards.isNotEmpty) { _stackLoaded.add(stackId); return; }
    _stackLoading.add(stackId);
    try {
      final isActive = (_activeBoard?.id == boardId);
      final cards = await api.fetchCards(_baseUrl!, _username!, _password!, boardId, stackId, priority: isActive);
      final updated = [
        for (final c in cols)
          if (c.id == stackId) deck.Column(id: c.id, title: c.title, cards: cards) else c
      ];
      _columnsByBoard[boardId] = updated;
      _clearStackProtection(boardId, stackId);
      // Persist updated columns to local cache so partial progress survives app restarts
      cache.put('columns_$boardId', updated.map((c) => {
        'id': c.id,
        'title': c.title,
        'cards': c.cards.map((k) => {
          'id': k.id,
          'title': k.title,
          'description': k.description,
          'duedate': k.due?.toUtc().millisecondsSinceEpoch,
          'labels': k.labels.map((l) => {'id': l.id, 'title': l.title, 'color': l.color}).toList(),
        }).toList(),
      }).toList());
      _stackLoaded.add(stackId);
      notifyListeners();
    } catch (_) {
      _stackLoaded.add(stackId);
    } finally {
      _stackLoading.remove(stackId);
    }
  }

  // Fetch cards for a limited number of stacks on a board, prioritizing stacks without cards and excluding "done" columns.
  Future<void> _ensureSomeCardsForBoard(int boardId, {int limit = 2}) async {
    if (_localMode) return;
    if (_baseUrl == null || _username == null || _password == null) return;
    final cols = _columnsByBoard[boardId] ?? const <deck.Column>[];
    if (cols.isEmpty) return;
    int fetched = 0;
    for (final c in cols) {
      final ct = c.title.toLowerCase();
      if (ct.contains('done') || ct.contains('erledigt')) continue;
      if (c.cards.isEmpty) {
        try { await ensureCardsFor(boardId, c.id); } catch (_) {}
        fetched++;
        if (fetched >= limit) break;
      }
    }
    // Optional light force refresh: at most every 30 minutes per board
    if (fetched == 0) {
      final key = 'board_cards_force_ts_$boardId';
      final last = cache.get(key);
      final int? lastMs = last is int ? last : (last is num ? last.toInt() : null);
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (lastMs == null || (nowMs - lastMs) > 30 * 60 * 1000) {
        final pick = cols.firstWhere(
          (c) => !c.title.toLowerCase().contains('done') && !c.title.toLowerCase().contains('erledigt'),
          orElse: () => cols.first,
        );
        try { await ensureCardsFor(boardId, pick.id, force: true); } catch (_) {}
        cache.put(key, nowMs);
      }
    }
  }

  Future<void> refreshActiveBoardMeta() async {
    if (_localMode) return; // local mode: meta is maintained via UI actions
    final b = _activeBoard;
    if (b == null) return;
    if (_baseUrl == null || _username == null || _password == null) return;
    // Ensure cards are present in small batches (2-3 stacks parallel)
    final cols = columnsForActiveBoard();
    const pool = 3;
    for (int i = 0; i < cols.length; i += pool) {
      final slice = cols.skip(i).take(pool).toList();
      await Future.wait(slice.map((c) => ensureCardsFor(b.id, c.id)));
    }
    // Now kick off meta count fetch for all cards
    final cols2 = columnsForActiveBoard();
    for (final c in cols2) {
      for (final k in c.cards) {
        // force refresh to catch external changes
        unawaited(ensureCardMetaCounts(boardId: b.id, stackId: c.id, cardId: k.id, force: true));
      }
    }
  }

  Future<void> syncActiveBoard({bool forceMeta = false}) async {
    if (_localMode) return;
    final b = _activeBoard;
    if (b == null) return;
    if (_baseUrl == null || _username == null || _password == null) return;
    _isSyncing = true;
    notifyListeners();
    try {
      await refreshColumnsFor(b);
      final cols = columnsForActiveBoard();
      const pool = 3;
      for (int i = 0; i < cols.length; i += pool) {
        final slice = cols.skip(i).take(pool).toList();
        await Future.wait(slice.map((c) => ensureCardsFor(b.id, c.id)));
      }
      final cols2 = columnsForActiveBoard();
      final jobs = <Future<void>>[];
      for (final c in cols2) {
        for (final k in c.cards) {
          jobs.add(ensureCardMetaCounts(boardId: b.id, stackId: c.id, cardId: k.id, force: forceMeta));
        }
      }
      if (jobs.isNotEmpty) await Future.wait(jobs);
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  // Lazy load counts for comments and attachments per card
  Future<void> ensureCardMetaCounts({required int boardId, required int stackId, required int cardId, bool force = false}) async {
    if (_localMode) return; // no meta in local mode
    if (_baseUrl == null || _username == null || _password == null) return;
    final needsComments = force || !_cardCommentsCount.containsKey(cardId);
    final needsAttachments = force || !_cardAttachmentsCount.containsKey(cardId);
    if (!needsComments && !needsAttachments) return;
    try {
      final base = _baseUrl!, user = _username!, pass = _password!;
      // Fetch in parallel best-effort
      final futures = <Future<void>>[];
      if (needsComments) {
        futures.add(() async {
          try {
            final raw = await api.fetchCommentsRaw(base, user, pass, cardId, limit: 200, offset: 0);
            // Some Deck instances return threaded comments: top-level with nested 'replies'
            int total = 0;
            for (final e in raw) {
              if (e is Map) {
                final m = (e as Map).cast<String, dynamic>();
                final replies = m['replies'];
                final rlen = (replies is List) ? replies.length : 0;
                total += 1 + rlen;
              } else {
                total += 1;
              }
            }
            _cardCommentsCount[cardId] = total;
          } catch (_) {}
        }());
      }
      if (needsAttachments) {
        futures.add(() async {
          try {
            final list = await api.fetchCardAttachments(base, user, pass, boardId: boardId, stackId: stackId, cardId: cardId);
            _cardAttachmentsCount[cardId] = list.length;
          } catch (_) {}
        }());
      }
      if (futures.isNotEmpty) {
        await Future.wait(futures);
        notifyListeners();
      }
    } catch (_) {}
  }

  void _hydrateFromCache() {
    final rawBoards = cache.get('boards');
    if (rawBoards is List) {
      _boards = rawBoards
          .whereType<Map>()
          .map((e) {
            final m = e.cast<String, dynamic>();
            final archivedRaw = m['archived'];
            final archived = archivedRaw is bool
                ? archivedRaw
                : (archivedRaw is num ? (archivedRaw != 0) : false);
            return Board(
              id: (m['id'] as num).toInt(),
              title: (m['title'] ?? '').toString(),
              color: (m['color'] as String?),
              archived: archived,
            );
          })
          .toList();
    }
    final hidden = cache.get('hiddenBoards');
    if (hidden is List) {
      _hiddenBoards
        ..clear()
        ..addAll(hidden.whereType().map((e) => (e as num).toInt()));
    }
    final activeId = cache.get('activeBoardId');
    if (activeId is int) {
      _activeBoard = _boards.firstWhere((b) => b.id == activeId, orElse: () => _boards.isEmpty ? Board.empty() : _boards.first);
    }
    for (final b in _boards) {
      final cols = cache.get('columns_${b.id}');
      if (cols is List) {
        _columnsByBoard[b.id] = _parseCachedColumns(cols);
      }
    }
    // Members cache (best-effort)
    for (final b in _boards) {
      final m = cache.get('board_members_${b.id}');
      if (m is int) {
        _boardMemberCount[b.id] = m;
      }
    }
  }

  void setBoardHidden(int boardId, bool hidden) {
    if (hidden) {
      _hiddenBoards.add(boardId);
    } else {
      _hiddenBoards.remove(boardId);
    }
    cache.put('hiddenBoards', _hiddenBoards.toList());
    notifyListeners();
  }

  void toggleBoardHidden(int boardId) => setBoardHidden(boardId, !isBoardHidden(boardId));

  List<deck.Column> _parseCachedColumns(List colsRaw) {
    final parsed = <deck.Column>[];
    for (final c in colsRaw.whereType<Map>()) {
      final cards = <CardItem>[];
      final list = c['cards'];
      if (list is List) {
        for (final k in list.whereType<Map>()) {
          DateTime? due;
          final dd = k['duedate'];
          if (dd is int) {
            due = DateTime.fromMillisecondsSinceEpoch(dd, isUtc: true).toLocal();
          }
          cards.add(CardItem(
            id: (k['id'] as num).toInt(),
            title: (k['title'] ?? '').toString(),
            description: (k['description'] as String?),
            due: due,
            labels: ((k['labels'] as List?) ?? const [])
                .whereType<Map>()
                .map((l) => Label(id: (l['id'] as num).toInt(), title: (l['title'] ?? '').toString(), color: (l['color'] ?? '').toString()))
                .toList(),
          ));
        }
      }
      parsed.add(deck.Column(id: (c['id'] as num).toInt(), title: (c['title'] ?? '').toString(), cards: cards));
    }
    return parsed;
  }

  Future<void> createCard({
    required int boardId,
    required int columnId,
    required String title,
    String? description,
  }) async {
    if (_localMode) {
      final cols = _columnsByBoard[boardId];
      if (cols == null) return;
      final idx = cols.indexWhere((c) => c.id == columnId);
      if (idx < 0) return;
      final nextId = (cache.get('local_next_card_id') as int?) ?? 1;
      final newCard = CardItem(id: nextId, title: title, description: description, labels: const [], assignees: const [], due: null);
      final updated = [
        for (final c in cols)
          if (c.id == columnId) deck.Column(id: c.id, title: c.title, cards: [...c.cards, newCard]) else c
      ];
      _columnsByBoard[boardId] = updated;
      cache.put('local_next_card_id', nextId + 1);
      cache.put('columns_$boardId', updated.map((c) => {
        'id': c.id,
        'title': c.title,
        'cards': c.cards.map((k) => {
          'id': k.id,
          'title': k.title,
          'description': k.description,
          'duedate': k.due?.toUtc().millisecondsSinceEpoch,
          'labels': k.labels.map((l) => {'id': l.id, 'title': l.title, 'color': l.color}).toList(),
        }).toList(),
      }).toList());
      notifyListeners();
      return;
    }
    if (_baseUrl == null || _username == null || _password == null) return;
    // Server-first: create on server, then insert returned card immediately, then kick a prioritized refresh
    _protectStack(boardId, columnId);
    final created = await api.createCard(_baseUrl!, _username!, _password!, boardId, columnId, title, description: description);
    if (created != null) {
      final cols = _columnsByBoard[boardId] ?? const <deck.Column>[];
      final idx = cols.indexWhere((c) => c.id == columnId);
      final newCard = CardItem.fromJson(created);
      if (idx >= 0) {
        final updated = [
          for (final c in cols)
            if (c.id == columnId) deck.Column(id: c.id, title: c.title, cards: [...c.cards, newCard]) else c
        ];
        _columnsByBoard[boardId] = updated;
        cache.put('columns_$boardId', updated.map((c) => {
          'id': c.id,
          'title': c.title,
          'cards': c.cards.map((k) => {
            'id': k.id,
            'title': k.title,
            'description': k.description,
            'duedate': k.due?.toUtc().millisecondsSinceEpoch,
            'labels': k.labels.map((l) => {'id': l.id, 'title': l.title, 'color': l.color}).toList(),
          }).toList(),
        }).toList());
        notifyListeners();
      }
    }
    // Kick a prioritized refresh of the whole board to converge fully (do not block UI)
    unawaited(() async {
      try {
        final fetched = await api.fetchColumns(_baseUrl!, _username!, _password!, boardId, lazyCards: false, priority: true, bypassCooldown: true);
        final prev = _columnsByBoard[boardId] ?? const <deck.Column>[];
        final merged = _mergeColumnsReplaceChangedForBoard(boardId, prev, fetched);
        _columnsByBoard[boardId] = merged;
        cache.put('columns_$boardId', merged.map((c) => {
          'id': c.id,
          'title': c.title,
          'cards': c.cards.map((k) => {
            'id': k.id,
            'title': k.title,
            'description': k.description,
            'duedate': k.due?.toUtc().millisecondsSinceEpoch,
            'labels': k.labels.map((l) => {'id': l.id, 'title': l.title, 'color': l.color}).toList(),
          }).toList(),
        }).toList());
        notifyListeners();
      } catch (_) {}
      _clearStackProtection(boardId, columnId);
    }());
  }

  // Delete a card (optimistic local update, best-effort server call)
  Future<void> deleteCard({required int boardId, required int stackId, required int cardId}) async {
    // Local removal
    final cols = _columnsByBoard[boardId];
    if (cols != null) {
      _columnsByBoard[boardId] = [
        for (final c in cols)
          if (c.id == stackId)
            deck.Column(id: c.id, title: c.title, cards: c.cards.where((k) => k.id != cardId).toList())
          else
            c
      ];
      // persist simplified columns cache
      final updated = _columnsByBoard[boardId]!;
      cache.put('columns_$boardId', updated.map((c) => {
        'id': c.id,
        'title': c.title,
        'cards': c.cards.map((k) => {
          'id': k.id,
          'title': k.title,
          'description': k.description,
          'duedate': k.due?.toUtc().millisecondsSinceEpoch,
          'labels': k.labels.map((l) => {'id': l.id, 'title': l.title, 'color': l.color}).toList(),
        }).toList(),
      }).toList());
      notifyListeners();
    }
    if (_localMode) return;
    if (_baseUrl == null || _username == null || _password == null) return;
    try {
      await api.deleteCard(_baseUrl!, _username!, _password!, boardId: boardId, stackId: stackId, cardId: cardId);
    } catch (_) {}
  }

  // Optimistic local update to reflect changes immediately
  void updateLocalCard({
    required int boardId,
    required int stackId,
    required int cardId,
    String? title,
    String? description,
    DateTime? due,
    int? moveToStackId,
    int? insertIndex,
    List<Label>? setLabels,
    List<UserRef>? setAssignees,
  }) {
    final cols = _columnsByBoard[boardId];
    if (cols == null) return;
    int fromIndex = cols.indexWhere((c) => c.id == stackId);
    if (fromIndex < 0) return;
    final from = cols[fromIndex];
    final cardIdx = from.cards.indexWhere((k) => k.id == cardId);
    if (cardIdx < 0) return;
    final current = from.cards[cardIdx];
    final updated = CardItem(
      id: current.id,
      title: title ?? current.title,
      description: description ?? current.description,
      due: due ?? current.due,
      labels: setLabels ?? current.labels,
      assignees: setAssignees ?? current.assignees,
    );
    // Apply in place or move to another stack
    if (moveToStackId != null && moveToStackId != stackId) {
      // remove from current
      final newFromCards = [...from.cards]..removeAt(cardIdx);
      _columnsByBoard[boardId] = [
        for (final c in cols)
          if (c.id == from.id)
            deck.Column(id: c.id, title: c.title, cards: newFromCards)
          else if (c.id == moveToStackId)
            deck.Column(
              id: c.id,
              title: c.title,
              cards: () {
                final list = [...c.cards];
                if (insertIndex == null) {
                  list.add(updated);
                } else {
                  final ni = insertIndex!.clamp(0, list.length);
                  list.insert(ni, updated);
                }
                return list;
              }(),
            )
          else
            c
      ];
    } else {
      final newCards = [...from.cards];
      newCards[cardIdx] = updated;
      _columnsByBoard[boardId] = [
        for (final c in cols)
          if (c.id == from.id) deck.Column(id: c.id, title: c.title, cards: newCards) else c
      ];
    }
    notifyListeners();
  }

  // Reorder card within the same stack (optimistic)
  void reorderCardLocal({
    required int boardId,
    required int stackId,
    required int cardId,
    required int newIndex,
  }) {
    final cols = _columnsByBoard[boardId];
    if (cols == null) return;
    final sIdx = cols.indexWhere((c) => c.id == stackId);
    if (sIdx < 0) return;
    final stack = cols[sIdx];
    final list = List<CardItem>.from(stack.cards);
    final cIdx = list.indexWhere((k) => k.id == cardId);
    if (cIdx < 0) return;
    final item = list.removeAt(cIdx);
    final ni = newIndex.clamp(0, list.length);
    list.insert(ni, item);
    _columnsByBoard[boardId] = [
      for (int i = 0; i < cols.length; i++)
        if (i == sIdx) deck.Column(id: stack.id, title: stack.title, cards: list) else cols[i]
    ];
    notifyListeners();
  }
}
