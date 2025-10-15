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

  bool get isDarkMode => _isDarkMode;
  int get themeIndex => _themeIndex;
  bool get smartColors => _smartColors;
  bool get showDescriptionText => _showDescriptionText;
  String? get localeCode => _localeCode;
  bool get isSyncing => _isSyncing;
  bool get isWarming => _isWarming;
  bool get backgroundPreload => _backgroundPreload;
  bool get cacheBoardsLocal => _cacheBoardsLocal;
  int get startupTabIndex => _startupTabIndex;
  String? get baseUrl => _baseUrl;
  String? get username => _username;
  bool get localMode => _localMode;
  Board? get activeBoard => _activeBoard;
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
    _localMode = (await storage.read(key: 'local_mode')) == '1';
    _localeCode = await storage.read(key: 'locale');
    _baseUrl = await storage.read(key: 'baseUrl');
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
      // Kein globales Karten-Warmup mehr. Optional: Stacks im Hintergrund, wenn aktiviert.
      if (_backgroundPreload) {
        unawaited(warmAllBoards());
      }
      // Upcoming-Hintergrundscan direkt beim Start anstoßen (schont UI, limitiert parallele Last)
      unawaited(scanUpcoming());
      if (activeBoardIdStr != null) {
        final id = int.tryParse(activeBoardIdStr);
        _activeBoard = _boards.firstWhere(
          (b) => b.id == id,
          orElse: () => _boards.isEmpty ? Board.empty() : _boards.first,
        );
        // Falls wir Spalten im Cache haben, direkt zeigen
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
      // Process boards in small batches; nur Spalten (Stacks) laden, Karten lazy
      for (int bi = 0; bi < active.length; bi += boardConcurrency) {
        final slice = active.skip(bi).take(boardConcurrency).toList();
        await Future.wait(slice.map((b) async {
          try {
            // Spalten schlank laden (lazyCards=true) und cachen
            final fetched = await api.fetchColumns(_baseUrl!, _username!, _password!, b.id, lazyCards: true);
            _columnsByBoard[b.id] = fetched;
            cache.put('columns_${b.id}', fetched.map((c) => {
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
  /// Loads cards in small batches per board. Safe to call multiple times; ignores if already running unless forced.
  Future<void> scanUpcoming({bool force = false, int listConcurrency = 1}) async {
    if (_localMode) return;
    if (_baseUrl == null || _username == null || _password == null) return;
    if (_upScanActive && !force) return;
    _upScanActive = true;
    _upScanDone = 0;
    final boards = _boards.where((b) => !b.archived && !_hiddenBoards.contains(b.id)).toList();
    _upScanTotal = boards.length;
    _upScanBoardTitle = null;
    notifyListeners();
    try {
      final activeId = _activeBoard?.id;
      for (final b in boards) {
        _upScanBoardTitle = b.title;
        notifyListeners();
        if (b.id != activeId) {
          if (_cacheBoardsLocal) {
            final etagKey = 'etag_stacks_${b.id}';
            final prevEtag = cache.get(etagKey) as String?;
            FetchStacksResult? res;
            try {
              res = await api.fetchStacksWithEtag(_baseUrl!, _username!, _password!, b.id, ifNoneMatch: prevEtag, priority: false);
            } catch (_) {}
            if (res != null && !res.notModified) {
              _columnsByBoard[b.id] = res.columns;
              cache.put('columns_${b.id}', res.columns.map((c) => {
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
              final cols = _columnsByBoard[b.id] ?? const <deck.Column>[];
              for (int i = 0; i < cols.length; i += listConcurrency) {
                final slice = cols.skip(i).take(listConcurrency).toList();
                await Future.wait(slice.map((c) => ensureCardsFor(b.id, c.id)));
              }
            }
            // If notModified: keep old columns/cards from cache
          } else {
            if ((_columnsByBoard[b.id] ?? const <deck.Column>[]).isEmpty) {
              try { await refreshColumnsFor(b); } catch (_) {}
            }
            final cols = _columnsByBoard[b.id] ?? const <deck.Column>[];
            for (int i = 0; i < cols.length; i += listConcurrency) {
              final slice = cols.skip(i).take(listConcurrency).toList();
              await Future.wait(slice.map((c) => ensureCardsFor(b.id, c.id)));
            }
          }
        }
        _upScanDone += 1;
        // Refresh upcoming cache incrementally
        _rebuildUpcomingCacheFromMemory();
        notifyListeners();
        // brief pause to yield network/CPU to interactive actions
        await Future.delayed(const Duration(milliseconds: 250));
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
    _baseUrl = _normalizeHttps(baseUrl);
    _username = username.trim();
    _password = password;
    storage.write(key: 'baseUrl', value: _baseUrl);
    storage.write(key: 'username', value: _username);
    storage.write(key: 'password', value: _password);
    notifyListeners();
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
    _boards = await api.fetchBoards(_baseUrl!, _username!, _password!);
    // Cache Boards schlank ablegen (inkl. Farbe/archived, falls vorhanden)
    cache.put('boards', _boards.map((b) => {
      'id': b.id,
      'title': b.title,
      if (b.color != null) 'color': b.color,
      'archived': b.archived,
    }).toList());
    // Prune hidden list to existing boards
    _hiddenBoards.removeWhere((id) => !_boards.any((b) => b.id == id));
    cache.put('hiddenBoards', _hiddenBoards.toList());
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

  Future<void> refreshColumnsFor(Board board) async {
    if (_localMode) {
      // Already in memory; ensure cached structure exists
      if (_columnsByBoard[board.id] == null) _setupLocalBoard();
      return;
    }
    if (_baseUrl == null || _username == null || _password == null) return;
    try {
      _stackLoaded.clear();
      _stackLoading.clear();
      final isActive = (_activeBoard?.id == board.id);
      final cols = await api.fetchColumns(_baseUrl!, _username!, _password!, board.id, lazyCards: true, priority: isActive);
      _columnsByBoard[board.id] = cols;
      // Cache Columns + Cards pro Board
      cache.put('columns_${board.id}', cols.map((c) => {
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
        if (tabController.index != 1) {
          await syncActiveBoard(forceMeta: true);
        }
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

  final Set<int> _stackLoading = {};
  final Set<int> _stackLoaded = {};
  bool isStackLoading(int stackId) => _stackLoading.contains(stackId);
  Future<void> ensureCardsFor(int boardId, int stackId) async {
    if (_localMode) return;
    if (_baseUrl == null || _username == null || _password == null) return;
    if (_stackLoading.contains(stackId) || _stackLoaded.contains(stackId)) return;
    final cols = _columnsByBoard[boardId];
    if (cols == null) return;
    final idx = cols.indexWhere((c) => c.id == stackId);
    if (idx < 0) return;
    if (cols[idx].cards.isNotEmpty) { _stackLoaded.add(stackId); return; }
    _stackLoading.add(stackId);
    try {
      final isActive = (_activeBoard?.id == boardId);
      final cards = await api.fetchCards(_baseUrl!, _username!, _password!, boardId, stackId, priority: isActive);
      final updated = [
        for (final c in cols)
          if (c.id == stackId) deck.Column(id: c.id, title: c.title, cards: cards) else c
      ];
      _columnsByBoard[boardId] = updated;
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
    if (_activeBoard != null) {
      final cols = cache.get('columns_${_activeBoard!.id}');
      if (cols is List) {
        _columnsByBoard[_activeBoard!.id] = _parseCachedColumns(cols);
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
      // persist simplified columns cache
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
    await api.createCard(_baseUrl!, _username!, _password!, boardId, columnId, title, description: description);
    final board = _boards.firstWhere((b) => b.id == boardId);
    await refreshColumnsFor(board);
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
