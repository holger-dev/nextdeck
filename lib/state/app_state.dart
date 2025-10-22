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
import '../sync/sync_service.dart';
import '../sync/sync_service_impl.dart';

class AppState extends ChangeNotifier {
  final storage = const FlutterSecureStorage();
  final CupertinoTabController tabController =
      CupertinoTabController(initialIndex: 1);
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
  int _startupTabIndex = 1; // 0=Upcoming,1=Board,2=Overview
  bool _upcomingSingleColumn =
      false; // user setting: show Upcoming as single list
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
  bool _initialWarmDone = false;

  bool get isDarkMode => _isDarkMode;
  int get themeIndex => _themeIndex;
  bool get smartColors => _smartColors;
  bool get showDescriptionText => _showDescriptionText;
  bool get overviewShowBoardInfo => _overviewShowBoardInfo;
  String? get localeCode => _localeCode;
  bool get isSyncing => _isSyncing;
  bool get isWarming => _isWarming;
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
  List<deck.Column> columnsForBoard(int boardId) =>
      _columnsByBoard[boardId] ?? [];
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
  SyncService? _sync;
  bool _bootSyncing = false;
  String? _bootMessage;
  bool get bootSyncing => _bootSyncing;
  String? get bootMessage => _bootMessage;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _isDarkMode = (await storage.read(key: 'dark')) == '1';
    _themeIndex =
        int.tryParse(await storage.read(key: 'themeIndex') ?? '') ?? 0;
    _smartColors = (await storage.read(key: 'smartColors')) != '0';
    _showDescriptionText =
        (await storage.read(key: 'showDescriptionText')) != '0';
    _upcomingSingleColumn = (await storage.read(key: 'up_single')) == '1';
    _overviewShowBoardInfo =
        (await storage.read(key: 'overview_board_info')) != '0';
    _localMode = (await storage.read(key: 'local_mode')) == '1';
    _localeCode = await storage.read(key: 'locale');
    _baseUrl = await storage.read(key: 'baseUrl');
    _defaultBoardId =
        int.tryParse(await storage.read(key: 'defaultBoardId') ?? '');
    final sbm = await storage.read(key: 'startup_board_mode');
    if (sbm == 'default' || sbm == 'last') {
      _startupBoardMode = sbm!;
    }
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
    _startupTabIndex =
        int.tryParse(await storage.read(key: 'startup_tab') ?? '')
                ?.clamp(0, 2) ??
            1;
    final activeBoardIdStr = await storage.read(key: 'activeBoardId');
    if (_localMode) {
      _setupLocalBoard();
      notifyListeners();
      return;
    }
    if (_baseUrl != null && _username != null && _password != null) {
      _hydrateFromCache();
      try {
        _sync = SyncServiceImpl(
            baseUrl: _baseUrl!, username: _username!, password: _password!, cache: cache);
        // Hintergrund: sofort starten, UI nicht blockieren
        // ignore: unawaited_futures
        (() async {
          try {
            _bootSyncing = true;
            _bootMessage = 'Verbinde und lade Boards…';
            notifyListeners();
            await _sync!.initSyncOnAppStart();
            _bootMessage = 'Bereite Ansicht vor…';
            notifyListeners();
            // Hydrate from cache after sync instead of refreshBoards which may override
            _hydrateFromCache();
          } finally {
            _bootSyncing = false;
            _bootMessage = null;
            notifyListeners();
          }
        })();
      } catch (_) {
        // Ignorieren beim Start; Nutzer kann in den Einstellungen erneut testen
      }
      // Autosync starten (Board-Delta alle 60s, Gatekeeper+Upcoming selektiv)
      _startAutoSync();
      // Kein großer Autosync beim Start – Nutzer kann manuell in „Anstehend“ aktualisieren.
      // Startup board selection based on user preference
      if (_startupBoardMode == 'default') {
        if (_defaultBoardId != null &&
            _boards.any((b) => b.id == _defaultBoardId)) {
          _activeBoard = _boards.firstWhere((b) => b.id == _defaultBoardId);
        } else if (activeBoardIdStr != null) {
          final id = int.tryParse(activeBoardIdStr);
          _activeBoard = _boards.firstWhere(
            (b) => b.id == id,
            orElse: () => _boards.isEmpty ? Board.empty() : _boards.first,
          );
        }
      } else {
        // 'last'
        if (activeBoardIdStr != null) {
          final id = int.tryParse(activeBoardIdStr);
          _activeBoard = _boards.firstWhere(
            (b) => b.id == id,
            orElse: () {
              if (_defaultBoardId != null &&
                  _boards.any((b) => b.id == _defaultBoardId)) {
                return _boards.firstWhere((b) => b.id == _defaultBoardId);
              }
              return _boards.isNotEmpty ? _boards.first : Board.empty();
            },
          );
        } else if (_defaultBoardId != null &&
            _boards.any((b) => b.id == _defaultBoardId)) {
          _activeBoard = _boards.firstWhere((b) => b.id == _defaultBoardId);
        }
      }

      if (_activeBoard != null) {
        await storage.write(
            key: 'activeBoardId', value: _activeBoard!.id.toString());
        cache.put('activeBoardId', _activeBoard!.id);
        final cachedCols = cache.get('columns_${_activeBoard!.id}');
        if (cachedCols is List) {
          _columnsByBoard[_activeBoard!.id] = _parseCachedColumns(cachedCols);
        }
      } else if (_activeBoard == null && _boards.isNotEmpty) {
        // Kein aktives Board gesetzt, aber Boards vorhanden: erstes wählen
        _activeBoard = _boards.first;
        await storage.write(
            key: 'activeBoardId', value: _activeBoard!.id.toString());
        cache.put('activeBoardId', _activeBoard!.id);
        final cachedCols = cache.get('columns_${_activeBoard!.id}');
        if (cachedCols is List) {
          _columnsByBoard[_activeBoard!.id] = _parseCachedColumns(cachedCols);
        }
      }
    }
    // Wenn keine Zugangsdaten gesetzt sind (und nicht im lokalen Modus), zur Einstellungs-Registerkarte springen
    if (!_localMode &&
        (_baseUrl == null || _username == null || _password == null)) {
      tabController.index = 3; // Settings tab
    }
    // Apply preferred startup tab if credentials vorhanden oder im lokalen Modus
    if (_localMode ||
        (_baseUrl != null && _username != null && _password != null)) {
      tabController.index = _startupTabIndex;
    }
    notifyListeners();
  }

  /// Background warm-up of columns && cards for all non-archived boards.
  /// Best-effort: respects existing caches && lazy flags; avoids duplicate fetches.
  Future<void> warmAllBoards(
      {bool force = false,
      void Function(int done, int total)? onProgress}) async {
    if (_localMode) return;
    if (_baseUrl == null || _username == null || _password == null) return;
    if (_isWarming) return;
    if (_initialWarmDone && !force) {
      onProgress?.call(_boards.where((b) => !b.archived).length,
          _boards.where((b) => !b.archived).length);
      return;
    }
    _isWarming = true;
    notifyListeners();
    try {
      final active = _boards.where((b) => !b.archived).toList();
      final total = active.length;
      if (total == 0) {
        onProgress?.call(0, 0);
        return;
      }
      onProgress?.call(0, total);
      for (int i = 0; i < active.length; i++) {
        final b = active[i];
        try {
          await refreshColumnsFor(b,
              bypassCooldown: true,
              full: force,
              forceNetwork: force);
        } catch (_) {}
        onProgress?.call(i + 1, total);
      }
    } finally {
      _isWarming = false;
      _initialWarmDone = true;
      notifyListeners();
      _rebuildUpcomingCacheFromMemory();
    }
  }

  Future<void> configureSyncForCurrentAccount() async {
    if (_localMode) return;
    if (_baseUrl == null || _username == null || _password == null) return;
    try {
      _bootSyncing = true;
      _bootMessage = 'Verbinde mit Server...';
      notifyListeners();
      
      _stopAutoSync();
      _sync = SyncServiceImpl(
          baseUrl: _baseUrl!, username: _username!, password: _password!, cache: cache);
      
      _bootMessage = 'Lade Boards und Daten...';
      notifyListeners();
      
      await _sync!.initSyncOnAppStart();
      
      _bootMessage = 'Bereite Ansicht vor...';
      notifyListeners();
      
      // Hydrate from cache after sync
      _hydrateFromCache();
    } catch (_) {
    } finally {
      _bootSyncing = false;
      _bootMessage = null;
      notifyListeners();
    }
    _startAutoSync();
  }

  /// Refresh a single board using the new sync system
  Future<void> refreshSingleBoard(int boardId) async {
    if (_localMode || _sync == null) return;
    try {
      await _sync!.ensureBoardFresh(boardId);
      _hydrateFromCache();
      // Rebuild Upcoming view after manual board refresh
      _rebuildUpcomingCacheFromMemory();
      notifyListeners();
    } catch (_) {}
  }

  void _rebuildUpcomingCacheFromMemory() {
    try {
      final now = DateTime.now();
      final startToday = DateTime(now.year, now.month, now.day);
      final endToday = startToday
          .add(const Duration(days: 1))
          .subtract(const Duration(milliseconds: 1));
      final startTomorrow = startToday.add(const Duration(days: 1));
      final endTomorrow = startToday
          .add(const Duration(days: 2))
          .subtract(const Duration(milliseconds: 1));
      final end7 = startToday
          .add(const Duration(days: 8))
          .subtract(const Duration(milliseconds: 1));
      final o = <Map<String, int>>[];
      final t = <Map<String, int>>[];
      final tm = <Map<String, int>>[];
      final n7 = <Map<String, int>>[];
      final l = <Map<String, int>>[];
      for (final b in _boards.where((b) => !b.archived)) {
        var cols = _columnsByBoard[b.id];
        if (cols == null) {
          // Board not loaded in memory, try to load from cache for Upcoming view
          final cachedCols = cache.get('columns_${b.id}');
          if (cachedCols is List) {
            _columnsByBoard[b.id] = _parseCachedColumns(cachedCols);
            cols = _columnsByBoard[b.id]!;
          } else {
            cols = const <deck.Column>[];
          }
        }
        for (final c in cols) {
          final ct = c.title.toLowerCase();
          if (ct.contains('done') || ct.contains('erledigt'))
            continue; // exclude done columns
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
            } else if (!due.isBefore(startTomorrow) &&
                !due.isAfter(endTomorrow)) {
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
  /// Only processes boards that actually require work (changed since last board list, || missing local data).
  /// Counter reflects already up-to-date boards immediately.
  Future<void> scanUpcoming({bool force = false}) async {
    await refreshUpcomingDelta(forceFull: force);
  }

  /// Full, sequential sync of all boards (stacks + cards) regardless of lastModified.
  /// Intended for manual refresh from Upcoming: minimizes surprises by avoiding throttles && running serially.
  Future<void> syncAllBoardsNow() async {
    if (_localMode) return;
    if (_baseUrl == null || _username == null || _password == null) return;
    // Initialize progress as in Upcoming
    final boards = _boards
        .where((b) => !b.archived && !_hiddenBoards.contains(b.id))
        .toList();
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
          await refreshColumnsFor(
            b,
            bypassCooldown: true,
            full: true,
            forceNetwork: true,
          );
        } catch (_) {}
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
  /// Fetches stacks WITH cards for each board (by cooldowns), updates cache &&   /// rebuilds Upcoming incrementally. Optimized for large board counts (e.g., 150).
  Future<void> syncAllBoardsFast({int concurrency = 6}) async {
    if (_localMode) return;
    if (_baseUrl == null || _username == null || _password == null) return;
    final boards = _boards
        .where((b) => !b.archived && !_hiddenBoards.contains(b.id))
        .toList();
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
          // Indicate current board
          _upScanBoardTitle = b.title;
          notifyListeners();
          try {
            await refreshColumnsFor(
              b,
              bypassCooldown: true,
              full: true,
              forceNetwork: true,
            );
          } catch (_) {}
          // Rebuild Upcoming cache incrementally && yield a tiny gap to keep UI responsive
          _rebuildUpcomingCacheFromMemory();
          await Future.delayed(const Duration(milliseconds: 10));
        }));
        // Increment done counter after the entire chunk is completed (thread-safe)
        _upScanDone = (_upScanDone + chunk.length).clamp(0, _upScanTotal);
        notifyListeners();
      }
    } finally {
      _upScanActive = false;
      _upScanBoardTitle = null;
      _upScanDone = _upScanTotal; // Ensure completion is always recorded
      notifyListeners();
    }
  }

  Map<String, List<Map<String, int>>>? upcomingCacheRefs() {
    final m = cache.get('upcoming_cache');
    if (m is Map) {
      try {
        return {
          'overdue': (m['overdue'] as List)
              .cast<Map>()
              .map((e) => (e as Map).cast<String, int>())
              .toList(),
          'today': (m['today'] as List)
              .cast<Map>()
              .map((e) => (e as Map).cast<String, int>())
              .toList(),
          'tomorrow': (m['tomorrow'] as List)
              .cast<Map>()
              .map((e) => (e as Map).cast<String, int>())
              .toList(),
          'next7': (m['next7'] as List)
              .cast<Map>()
              .map((e) => (e as Map).cast<String, int>())
              .toList(),
          'later': (m['later'] as List)
              .cast<Map>()
              .map((e) => (e as Map).cast<String, int>())
              .toList(),
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
    // code must be one of 'de','en','es' || null for system
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
  }

  Future<void> setLocalMode(bool enabled) async {
    _localMode = enabled;
    await storage.write(key: 'local_mode', value: enabled ? '1' : '0');
    if (enabled) {
      // Clear credentials to avoid accidental network
      _baseUrl = null;
      _username = null;
      _password = null;
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
      cache.put(
          'columns_$localBoardId',
          initCols
              .map((c) => {'id': c.id, 'title': c.title, 'cards': const []})
              .toList());
    }
    _boards = [
      Board(id: localBoardId, title: 'Lokales Board', archived: false)
    ];
    _activeBoard = _boards.first;
    storage.write(key: 'activeBoardId', value: localBoardId.toString());
    cache.put('activeBoardId', localBoardId);
    cache.put(
        'boards',
        _boards
            .map((b) => {'id': b.id, 'title': b.title, 'archived': b.archived})
            .toList());
  }

  void setCredentials(
      {required String baseUrl,
      required String username,
      required String password}) {
    _localMode = false;
    storage.write(key: 'local_mode', value: '0');
    _stopAutoSync();
    _sync = null;
    final prevBase = _baseUrl;
    final prevUser = _username;
    final nextBase = _normalizeHttps(baseUrl);
    final nextUser = username.trim();
    final changedServer = prevBase != null &&
        prevUser != null &&
        (prevBase != nextBase || prevUser != nextUser);
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
      _stopAutoSync();
      // Clear persisted keys
      final keys = cache.keys.toList();
      for (final k in keys) {
        if (k is String) {
          if (k == 'boards' ||
              k == 'activeBoardId' ||
              k == 'hiddenBoards' ||
              k == 'upcoming_cache' ||
              k == 'etag_boards_details' ||
              k == 'etag_boards_list') {
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
      _stacksLoadingBoards.clear();
      _stacksLastFetchMsMem.clear();
      _orderSyncingStacks.clear();
      _protectStacksUntilMs.clear();
      _initialWarmDone = false;
      _upScanActive = false;
      _upScanDone = 0;
      _upScanTotal = 0;
      _upScanBoardTitle = null;
      // Reset default board selection for new server
      _defaultBoardId = null;
      storage.delete(key: 'defaultBoardId');
      storage.delete(key: 'activeBoardId');
      storage.delete(key: 'hiddenBoards');
    } catch (_) {}
  }

  // Ensure we always talk HTTPS regardless of user input, except when using server-relative base ('/' || '/path')
  String _normalizeHttps(String input) {
    var v = input.trim();
    if (v.isEmpty) return v;
    if (v.startsWith('/')) {
      // Normalize multiple leading slashes && trailing slash (except root)
      v = '/' + v.replaceFirst(RegExp(r'^/+'), '');
      if (v.length > 1 && v.endsWith('/')) v = v.substring(0, v.length - 1);
      return v; // keep server-relative base for Web deployments
    }
    if (v.startsWith('http://')) v = 'https://' + v.substring(7);
    if (!v.startsWith('https://'))
      v = 'https://' + v.replaceFirst(RegExp(r'^/+'), '');
    // Remove trailing slash to avoid double slashes when building paths
    if (v.endsWith('/')) v = v.substring(0, v.length - 1);
    return v;
  }

  Future<bool> testLogin() async {
    if (_baseUrl == null || _username == null || _password == null)
      return false;
    return api.testLogin(_baseUrl!, _username!, _password!);
  }

  Future<void> refreshBoards() async {
    if (_localMode) return;
    if (_baseUrl == null || _username == null || _password == null) return;

    final detailsEtagKey = 'etag_boards_details';

    FetchBoardsDetailsResult res;
    try {
      final prevDetailsEtag = cache.get(detailsEtagKey) as String?;
      res = await api.fetchBoardsWithDetailsEtag(
          _baseUrl!, _username!, _password!,
          ifNoneMatch: prevDetailsEtag);
      if (res.notModified && (_boards.isEmpty || _columnsByBoard.isEmpty)) {
        res = await api.fetchBoardsWithDetailsEtag(
            _baseUrl!, _username!, _password!,
            ifNoneMatch: null);
      }
    } catch (_) {
      await _ensureActiveBoardValid();
      _rebuildUpcomingCacheFromMemory();
      notifyListeners();
      return;
    }

    if (res.notModified) {
      await _ensureActiveBoardValid();
      _rebuildUpcomingCacheFromMemory();
      notifyListeners();
      return;
    }

    final updatedBoards = <Board>[];
    final updatedColumns = <int, List<deck.Column>>{};

    int? _parseLastModified(dynamic value) {
      if (value == null) return null;
      if (value is num) {
        final v = value.toInt();
        return v < 1000000000000 ? v * 1000 : v;
      }
      if (value is String) {
        final trimmed = value.trim();
        final asNum = int.tryParse(trimmed);
        if (asNum != null) {
          return asNum < 1000000000000 ? asNum * 1000 : asNum;
        }
        try {
          return DateTime.parse(trimmed).toUtc().millisecondsSinceEpoch;
        } catch (_) {
          return null;
        }
      }
      return null;
    }

    List<deck.Column> _buildColumns(
        Map<String, dynamic> board, List<deck.Column> previous) {
      final stacks = board['stacks'] ?? board['columns'] ?? board['lists'];
      if (stacks is! List) return previous;
      final Map<int, List<CardItem>> cardsByStack = () {
        final list = board['cards'];
        if (list is! List) return <int, List<CardItem>>{};
        final out = <int, List<CardItem>>{};
        for (final e in list.whereType<Map>()) {
          final em = e.cast<String, dynamic>();
          int? sid;
          final vsid = em['stackId'];
          if (vsid is num) sid = vsid.toInt();
          if (sid == null && em['stack'] is Map && (em['stack']['id'] is num)) {
            sid = (em['stack']['id'] as num).toInt();
          }
          if (sid == null) continue;
          (out[sid] ??= <CardItem>[]).add(CardItem.fromJson(em));
        }
        return out;
      }();
      final cols = <deck.Column>[];
      for (final entry in stacks.whereType<Map>()) {
        final stack = entry.cast<String, dynamic>();
        final stackId = (stack['id'] as num?)?.toInt();
        if (stackId == null) continue;
        final title = (stack['title'] ?? stack['name'] ?? '').toString();
        final cardsRaw = (stack['cards'] is List)
            ? (stack['cards'] as List)
                .whereType<Map>()
                .map((e) => e.cast<String, dynamic>())
                .toList()
            : const <Map<String, dynamic>>[];
        final parsedCards = cardsRaw.map(CardItem.fromJson).toList();
        if (parsedCards.isNotEmpty) {
          cols.add(deck.Column(id: stackId, title: title, cards: parsedCards));
          continue;
        }
        final fallback = cardsByStack[stackId];
        if (fallback != null && fallback.isNotEmpty) {
          cols.add(deck.Column(id: stackId, title: title, cards: fallback));
          continue;
        }
        final prev = previous.firstWhere(
          (element) => element.id == stackId,
          orElse: () => deck.Column(id: stackId, title: title, cards: const []),
        );
        cols.add(deck.Column(id: stackId, title: title, cards: prev.cards));
      }
      return cols;
    }

    for (final raw in res.boards.whereType<Map>()) {
      final map = raw.cast<String, dynamic>();
      final id = (map['id'] as num?)?.toInt();
      if (id == null) continue;
      updatedBoards.add(Board.fromJson(map));
      final lastMod = _parseLastModified(
        map['lastModified'] ??
            map['lastmodified'] ??
            map['lastActivity'] ??
            map['updatedAt'] ??
            map['mtime'] ??
            map['modified'],
      );
      if (lastMod != null) {
        cache.put('board_lastmod_$id', lastMod);
      }
      final previous = _columnsByBoard[id] ?? const <deck.Column>[];
      final columns = _buildColumns(map, previous);
      updatedColumns[id] = columns;
      cache.put(
          'columns_$id',
          columns
              .map((c) => {
                    'id': c.id,
                    'title': c.title,
                    'cards': c.cards
                        .map((k) => {
                              'id': k.id,
                              'title': k.title,
                              'description': k.description,
                              'duedate': k.due?.toUtc().millisecondsSinceEpoch,
                              'order': k.order, // Save order to cache
                              'labels': k.labels
                                  .map((l) => {
                                        'id': l.id,
                                        'title': l.title,
                                        'color': l.color
                                      })
                                  .toList(),
                            })
                        .toList(),
                  })
              .toList());
    }

    final previousBoardIds = _boards.map((b) => b.id).toSet();
    _boards = updatedBoards;
    _columnsByBoard
      ..clear()
      ..addAll(updatedColumns);
    cache.put(
        'boards',
        _boards
            .map((b) => {
                  'id': b.id,
                  'title': b.title,
                  if (b.color != null) 'color': b.color,
                  'archived': b.archived,
                })
            .toList());

    final currentIds = _boards.map((b) => b.id).toSet();
    _boardMemberCount.removeWhere((key, _) => !currentIds.contains(key));
    for (final rid in previousBoardIds.difference(currentIds)) {
      cache.delete('columns_$rid');
      cache.delete('board_members_$rid');
      cache.delete('board_lastmod_$rid');
    }

    if (res.etag != null) {
      cache.put(detailsEtagKey, res.etag);
    }

    _hiddenBoards.removeWhere((id) => !_boards.any((b) => b.id == id));
    cache.put('hiddenBoards', _hiddenBoards.toList());

    if (_defaultBoardId != null &&
        !_boards.any((b) => b.id == _defaultBoardId)) {
      _defaultBoardId = null;
      await storage.delete(key: 'defaultBoardId');
    }

    await _ensureActiveBoardValid();

    _rebuildUpcomingCacheFromMemory();
    notifyListeners();
  }

  Future<void> _ensureActiveBoardValid() async {
    if (_boards.isEmpty) {
      if (_activeBoard != null) {
        _activeBoard = null;
        await storage.write(key: 'activeBoardId', value: '');
        cache.delete('activeBoardId');
      }
      _columnsByBoard.clear();
      return;
    }
    if (_activeBoard != null && !_boards.any((b) => b.id == _activeBoard!.id)) {
      final removedId = _activeBoard!.id;
      _activeBoard = _boards.first;
      await storage.write(
          key: 'activeBoardId', value: _activeBoard!.id.toString());
      cache.put('activeBoardId', _activeBoard!.id);
      _columnsByBoard.remove(removedId);
      cache.delete('columns_$removedId');
      cache.delete('board_members_$removedId');
    } else if (_activeBoard == null) {
      _activeBoard = _boards.first;
      await storage.write(
          key: 'activeBoardId', value: _activeBoard!.id.toString());
      cache.put('activeBoardId', _activeBoard!.id);
    }
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
      final uids = await api.fetchBoardMemberUids(
          _baseUrl!, _username!, _password!, boardId);
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
    // Keine Netz-Requests hier: Spalten/Karten kommen aus Global-Fetch
    notifyListeners();
    _startAutoSync();
    // DISABLED: Old refresh system disabled - new sync system handles this
    // if (!_localMode) {
    //   unawaited(() async {
    //     try {
    //       await refreshColumnsFor(board,
    //           bypassCooldown: true, full: true, forceNetwork: true);
    //     } catch (_) {}
    //   }());
    // }
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

  Future<bool> refreshColumnsFor(Board board,
      {bool bypassCooldown = false,
      bool full = false,
      bool forceNetwork = false}) async {
    if (_localMode) {
      if (_columnsByBoard[board.id] == null) _setupLocalBoard();
      return false;
    }
    if (_baseUrl == null || _username == null || _password == null) {
      return false;
    }

    final base = _baseUrl!;
    final user = _username!;
    final pass = _password!;
    final bool isActive = (_activeBoard?.id == board.id);
    final etagKey = 'etag_board_details_${board.id}';
    final prevEtag = cache.get(etagKey) as String?;
    final ifNoneMatch = forceNetwork ? null : prevEtag;

    FetchStacksResult res;
    try {
      res = await api.fetchBoardDetailsWithEtag(
        base,
        user,
        pass,
        board.id,
        ifNoneMatch: ifNoneMatch,
        priority: isActive,
      );
    } catch (e) {
      _lastError = e.toString();
      return false;
    }

    if (res.notModified) return false;

    final merged = List<deck.Column>.from(res.columns);
    _columnsByBoard[board.id] = merged;
    for (final c in merged) {
      _stackLoaded.add(c.id);
    }
    cache.put(
        'columns_${board.id}',
        merged
            .map((c) => {
                  'id': c.id,
                  'title': c.title,
                  'cards': c.cards
                      .map((k) => {
                            'id': k.id,
                            'title': k.title,
                            'description': k.description,
                            'duedate': k.due?.toUtc().millisecondsSinceEpoch,
                            'order': k.order, // Save order to cache
                            'labels': k.labels
                                .map((l) => {
                                      'id': l.id,
                                      'title': l.title,
                                      'color': l.color
                                    })
                                .toList(),
                          })
                      .toList(),
                })
            .toList());
    if (res.etag != null) cache.put(etagKey, res.etag);
    for (final c in merged) {
      _stackLoaded.add(c.id);
    }
    _lastError = null;
    notifyListeners();
    return true;
  }
  Future<bool> createStack(
      {required int boardId, required String title}) async {
    if (_localMode) {
      final cols = _columnsByBoard[boardId] ?? const <deck.Column>[];
      final nextId = ((cache.get('local_next_stack_id') as int?) ?? 1000) + 1;
      final updated = [
        ...cols,
        deck.Column(id: nextId, title: title, cards: const [])
      ];
      _columnsByBoard[boardId] = updated;
      cache.put('local_next_stack_id', nextId);
      cache.put(
          'columns_$boardId',
          updated
              .map((c) => {'id': c.id, 'title': c.title, 'cards': const []})
              .toList());
      notifyListeners();
      return true;
    }
    if (_baseUrl == null || _username == null || _password == null)
      return false;
    try {
      // Provide a best-effort order: append at end
      final existing = _columnsByBoard[boardId] ?? const <deck.Column>[];
      final order = existing.isEmpty ? 0 : existing.length;
      final created = await api.createStack(
          _baseUrl!, _username!, _password!, boardId,
          title: title, order: order);
      if (created != null) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<Board?> createBoard(
      {required String title, String? color, bool activate = true}) async {
    if (_localMode) {
      // Create a local board stub is out of scope for now
      return null;
    }
    if (_baseUrl == null || _username == null || _password == null) return null;
    try {
      final created = await api.createBoard(_baseUrl!, _username!, _password!,
          title: title, color: color);
      await refreshBoards();
      if (created != null && activate) {
        final found = _boards.firstWhere((b) => b.id == created.id,
            orElse: () => created);
        await setActiveBoard(found);
      }
      return created;
    } catch (_) {
      return null;
    }
  }

  void _startAutoSync() {
    _syncTimer?.cancel();
    if (_localMode ||
        _baseUrl == null ||
        _username == null ||
        _password == null) return;
    _syncTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      try {
        // DISABLED: Auto-sync disabled to prevent overriding freshly loaded cards
        // await _sync?.periodicDeltaSync();
        // DISABLED: Board auto-sync disabled to prevent card overriding
        // if (tabController.index == 1) {
        //   final b = _activeBoard;
        //   if (b != null) {
        //     try {
        //       await refreshColumnsFor(b, bypassCooldown: false, full: false);
        //     } catch (_) {}
        //     try {
        //       await _ensureSomeCardsForBoard(b.id, limit: 2);
        //     } catch (_) {}
        //   }
        // }
        // DISABLED: Upcoming delta sync disabled to prevent card overriding
        // unawaited(refreshUpcomingDelta());
      } catch (_) {}
    });
  }

  void _stopAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
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
  final Set<String> _orderSyncingStacks = {};
  void _protectStack(int boardId, int stackId, {int ms = 10000}) {
    _protectStacksUntilMs['$boardId:$stackId'] =
        DateTime.now().millisecondsSinceEpoch + ms;
  }

  void _clearStackProtection(int boardId, int stackId) {
    _protectStacksUntilMs.remove('$boardId:$stackId');
  }

  bool _isStackProtected(int boardId, int stackId) {
    final v = _protectStacksUntilMs['$boardId:$stackId'];
    if (v == null) return false;
    if (DateTime.now().millisecondsSinceEpoch > v) {
      _protectStacksUntilMs.remove('$boardId:$stackId');
      return false;
    }
    return true;
  }

  Future<void> syncStackOrder(
      {required int boardId, required int stackId}) async {
    if (_localMode) return;
    if (_baseUrl == null || _username == null) return;
    if (_password == null) {
      _password = await storage.read(key: 'password');
      if (_password == null) return;
    }
    final key = '$boardId:$stackId';
    if (_orderSyncingStacks.contains(key)) return;
    final cols = _columnsByBoard[boardId];
    if (cols == null) return;
    final stack = cols.firstWhere((c) => c.id == stackId,
        orElse: () => deck.Column(id: stackId, title: '', cards: const []));
    if (stack.cards.isEmpty) return;
    _orderSyncingStacks.add(key);
    _protectStack(boardId, stackId, ms: 15000);
    String? error;
    try {
      for (int i = 0; i < stack.cards.length; i++) {
        final card = stack.cards[i];
        final payload = <String, dynamic>{
          'order': i + 1,
          'position': i,
          'stackId': stackId,
          'title': card.title,
        };
        if ((card.description ?? '').isNotEmpty)
          payload['description'] = card.description;
        if (card.due != null)
          payload['duedate'] = card.due!.toUtc().toIso8601String();
        if (card.labels.isNotEmpty)
          payload['labels'] = card.labels.map((l) => l.id).toList();
        if (card.assignees.isNotEmpty)
          payload['assignedUsers'] = card.assignees
              .map((u) => u.id)
              .where((id) => id.isNotEmpty)
              .toList();
        try {
          await api.updateCard(_baseUrl!, _username!, _password!, boardId,
              stackId, card.id, payload);
        } catch (e) {
          error = e.toString();
        }
      }
      _lastError = error;
    } finally {
      _orderSyncingStacks.remove(key);
      notifyListeners();
    }
  }

  Future<void> clearLocalData() async {
    if (_localMode) return;
    _stopAutoSync();
    _clearAllServerCaches();
    _orderSyncingStacks.clear();
    _stacksLoadingBoards.clear();
    _stacksLastFetchMsMem.clear();
    _protectStacksUntilMs.clear();
    _lastError = null;
    notifyListeners();
    if (_baseUrl != null && _username != null) {
      if (_password == null) {
        _password = await storage.read(key: 'password');
      }
      if (_password != null) {
        try {
          _sync = SyncServiceImpl(
              baseUrl: _baseUrl!, username: _username!, password: _password!, cache: cache);
          await _sync!.initSyncOnAppStart();
          _hydrateFromCache();
          Board? board = _activeBoard;
          board ??= _boards.isNotEmpty ? _boards.first : null;
          if (board != null) {
            if (_activeBoard == null || _activeBoard!.id != board.id) {
              await setActiveBoard(board);
            }
          }
        } catch (_) {}
      }
    }
    _startAutoSync();
  }

  // Merge utility: replace only stacks present in 'next'; keep others, add new ones.
  // If a stack is protected for this board, keep its previous cards to avoid flicker after local changes.
  List<CardItem> _normalizeCardsOrder(List<CardItem> cards) {
    if (cards.isEmpty) return cards;
    if (!cards.any((c) => c.order != null)) return cards;
    final sorted = [...cards];
    sorted.sort((a, b) {
      final ao = a.order;
      final bo = b.order;
      if (ao == null && bo == null) return 0;
      if (ao == null) return 1;
      if (bo == null) return -1;
      final cmp = ao.compareTo(bo);
      if (cmp != 0) return cmp;
      return a.id.compareTo(b.id);
    });
    return sorted;
  }

  bool isStackLoading(int stackId) => _stackLoading.contains(stackId);
  Future<void> ensureCardsFor(int boardId, int stackId,
      {bool force = false, bool revalidate = false}) async {
    if (_localMode) return;
    if (_baseUrl == null || _username == null || _password == null) return;
    if (_stackLoading.contains(stackId)) return;
    final cols = _columnsByBoard[boardId];
    if (cols == null) return;
    final idx = cols.indexWhere((c) => c.id == stackId);
    if (idx < 0) return;
    if (!force && !revalidate && cols[idx].cards.isNotEmpty) {
      _stackLoaded.add(stackId);
      return;
    }
    _stackLoading.add(stackId);
    try {
      final board = _boards.firstWhere((b) => b.id == boardId,
          orElse: () => Board(id: boardId, title: '', color: null, archived: false));
      await refreshColumnsFor(
        board,
        bypassCooldown: true,
        full: true,
        forceNetwork: force || revalidate,
      );
      _stackLoaded.add(stackId);
      notifyListeners();
    } catch (_) {
      _stackLoaded.add(stackId);
    } finally {
      _stackLoading.remove(stackId);
    }
  }


  // Fetch cards for a limited number of stacks on a board, prioritizing stacks without cards && excluding "done" columns.
  Future<void> _ensureSomeCardsForBoard(int boardId, {int limit = 2}) async {
    final cols = _columnsByBoard[boardId];
    if (cols == null) return;
    for (final c in cols) {
      _stackLoaded.add(c.id);
    }
  }

  Future<void> refreshActiveBoardMeta() async {
    /* disabled to avoid per-card bursts */
  }

  Future<void> syncActiveBoard(
      {bool forceMeta = false,
      bool full = false,
      bool bypassCooldown = false}) async {
    if (_localMode) return;
    final b = _activeBoard;
    if (b == null) return;
    if (_baseUrl == null || _username == null || _password == null) return;
    _isSyncing = true;
    notifyListeners();
    try {
      await refreshColumnsFor(b, bypassCooldown: bypassCooldown, full: true);
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  // Lazy load counts for comments && attachments per card
  // Upcoming delta: Gatekeeper + refresh only changed boards' stacks; then load cards only for stacks with due hits.
  Future<void> refreshUpcomingDelta({bool forceFull = false}) async {
    if (_localMode) return;
    if (_baseUrl == null || _username == null || _password == null) return;
    _upScanActive = true;
    notifyListeners();
    try {
      await refreshBoards();
      final changedBoards = <int, bool>{};
      final boardsToProcess =
          forceFull ? _boards.where((x) => !x.archived).toList() : <Board>[];
      if (forceFull) {
        for (final b in boardsToProcess) {
          changedBoards[b.id] = true;
        }
      } else {
        for (final b in _boards.where((x) => !x.archived)) {
          final curr = cache.get('board_lastmod_${b.id}');
          final prev = cache.get('board_lastmod_prev_${b.id}');
          final int? currMs =
              curr is int ? curr : (curr is num ? curr.toInt() : null);
          final int? prevMs =
              prev is int ? prev : (prev is num ? prev.toInt() : null);
          final changed = (currMs != null && prevMs != null)
              ? (currMs > prevMs)
              : (prevMs == null);
          if (changed) {
            boardsToProcess.add(b);
            changedBoards[b.id] = true;
          }
        }
      }
      for (final b in boardsToProcess) {
        final shouldForce = forceFull || (changedBoards[b.id] ?? false);
        bool boardUpdated = false;
        try {
          boardUpdated = await refreshColumnsFor(
            b,
            bypassCooldown: true,
            full: shouldForce,
            forceNetwork: false,
          );
        } catch (_) {}
        if (boardUpdated) {
          final cols = _columnsByBoard[b.id] ?? const <deck.Column>[];
          for (final c in cols) {
            _stackLoaded.add(c.id);
          }
        }
        final curr = cache.get('board_lastmod_${b.id}');
        final int? currMs =
            curr is int ? curr : (curr is num ? curr.toInt() : null);
        if (currMs != null) cache.put('board_lastmod_prev_${b.id}', currMs);
      }
      _rebuildUpcomingCacheFromMemory();
      notifyListeners();
    } catch (_) {
    } finally {
      _upScanActive = false;
      notifyListeners();
    }
  }

  Future<void> ensureCardMetaCounts(
      {required int boardId,
      required int stackId,
      required int cardId,
      bool force = false}) async {
    if (_localMode) return; // no meta in local mode
    if (_baseUrl == null || _username == null || _password == null) return;
    final needsComments = force || !_cardCommentsCount.containsKey(cardId);
    final needsAttachments =
        force || !_cardAttachmentsCount.containsKey(cardId);
    if (!needsComments && !needsAttachments) return;
    try {
      final base = _baseUrl!, user = _username!, pass = _password!;
      // Fetch in parallel best-effort
      final futures = <Future<void>>[];
      if (needsComments) {
        futures.add(() async {
          try {
            final raw = await api.fetchCommentsRaw(base, user, pass, cardId,
                limit: 200, offset: 0);
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
            final list = await api.fetchCardAttachments(base, user, pass,
                boardId: boardId, stackId: stackId, cardId: cardId);
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

  // Server update helper: apply update on server only, NO automatic sync
  Future<void> updateCardAndRefresh({
    required int boardId,
    required int stackId,
    required int cardId,
    required Map<String, dynamic> patch,
  }) async {
    if (_localMode) return; // local-only mode: callers already did optimistic update
    if (_baseUrl == null || _username == null || _password == null) return;
    try {
      await api.updateCard(
          _baseUrl!, _username!, _password!, boardId, stackId, cardId, patch);
      // Apply successful server response locally to ensure consistency
      updateLocalCard(
        boardId: boardId,
        stackId: stackId,
        cardId: cardId,
        title: patch['title'] as String?,
        description: patch['description'] as String?,
        due: patch['duedate'] != null ? DateTime.parse(patch['duedate'] as String) : null,
      );
    } catch (e) {
      // API call failed, but keep local optimistic update
    }
    // Rebuild Upcoming view from local data after card changes
    _rebuildUpcomingCacheFromMemory();
    // NO automatic board sync - user must manually refresh if needed
  }

  void _hydrateFromCache() {
    final rawBoards = cache.get('boards');
    if (rawBoards is List) {
      _boards = rawBoards.whereType<Map>().map((e) {
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
      }).toList();
    }
    final hidden = cache.get('hiddenBoards');
    if (hidden is List) {
      _hiddenBoards
        ..clear()
        ..addAll(hidden.whereType().map((e) => (e as num).toInt()));
    }
    final activeId = cache.get('activeBoardId');
    if (activeId is int) {
      _activeBoard = _boards.firstWhere((b) => b.id == activeId,
          orElse: () => _boards.isEmpty ? Board.empty() : _boards.first);
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

  void toggleBoardHidden(int boardId) =>
      setBoardHidden(boardId, !isBoardHidden(boardId));

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
            due =
                DateTime.fromMillisecondsSinceEpoch(dd, isUtc: true).toLocal();
          }
          cards.add(CardItem(
            id: (k['id'] as num).toInt(),
            title: (k['title'] ?? '').toString(),
            description: (k['description'] as String?),
            due: due,
            labels: ((k['labels'] as List?) ?? const [])
                .whereType<Map>()
                .map((l) => Label(
                    id: (l['id'] as num).toInt(),
                    title: (l['title'] ?? '').toString(),
                    color: (l['color'] ?? '').toString()))
                .toList(),
            order: (k['order'] as num?)?.toInt(), // Load order from cache
          ));
        }
      }
      // Normalize card order when loading from cache
      final normalizedCards = _normalizeCardsOrder(cards);
      parsed.add(deck.Column(
          id: (c['id'] as num).toInt(),
          title: (c['title'] ?? '').toString(),
          cards: normalizedCards));
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
      final newCard = CardItem(
          id: nextId,
          title: title,
          description: description,
          labels: const [],
          assignees: const [],
          due: null);
      final updated = [
        for (final c in cols)
          if (c.id == columnId)
            deck.Column(id: c.id, title: c.title, cards: [...c.cards, newCard])
          else
            c
      ];
      _columnsByBoard[boardId] = updated;
      cache.put('local_next_card_id', nextId + 1);
      cache.put(
          'columns_$boardId',
          updated
              .map((c) => {
                    'id': c.id,
                    'title': c.title,
                    'cards': c.cards
                        .map((k) => {
                              'id': k.id,
                              'title': k.title,
                              'description': k.description,
                              'duedate': k.due?.toUtc().millisecondsSinceEpoch,
                              'order': k.order, // Save order to cache
                              'labels': k.labels
                                  .map((l) => {
                                        'id': l.id,
                                        'title': l.title,
                                        'color': l.color
                                      })
                                  .toList(),
                            })
                        .toList(),
                  })
              .toList());
      notifyListeners();
      return;
    }
    if (_baseUrl == null || _username == null || _password == null) return;
    // Server-first: create on server, then insert returned card immediately, then perform a focused board sync
    _protectStack(boardId, columnId);
    final created = await api.createCard(
        _baseUrl!, _username!, _password!, boardId, columnId, title,
        description: description);
    if (created != null) {
      final cols = _columnsByBoard[boardId] ?? const <deck.Column>[];
      final idx = cols.indexWhere((c) => c.id == columnId);
      final newCard = CardItem.fromJson(created);
      if (idx >= 0) {
        final updated = [
          for (final c in cols)
            if (c.id == columnId)
              deck.Column(
                  id: c.id, title: c.title, cards: [...c.cards, newCard])
            else
              c
        ];
        _columnsByBoard[boardId] = updated;
        cache.put(
            'columns_$boardId',
            updated
                .map((c) => {
                      'id': c.id,
                      'title': c.title,
                      'cards': c.cards
                          .map((k) => {
                                'id': k.id,
                                'title': k.title,
                                'description': k.description,
                                'duedate':
                                    k.due?.toUtc().millisecondsSinceEpoch,
                                'order': k.order, // Save order to cache
                                'labels': k.labels
                                    .map((l) => {
                                          'id': l.id,
                                          'title': l.title,
                                          'color': l.color
                                        })
                                    .toList(),
                              })
                          .toList(),
                    })
                .toList());
        // Rebuild Upcoming view after creating card
        _rebuildUpcomingCacheFromMemory();
        notifyListeners();
      }
    }
    // Done
  }

  // Delete a card (optimistic local update, best-effort server call)
  Future<void> deleteCard(
      {required int boardId, required int stackId, required int cardId}) async {
    // Local removal
    final cols = _columnsByBoard[boardId];
    if (cols != null) {
      _columnsByBoard[boardId] = [
        for (final c in cols)
          if (c.id == stackId)
            deck.Column(
                id: c.id,
                title: c.title,
                cards: c.cards.where((k) => k.id != cardId).toList())
          else
            c
      ];
      // persist simplified columns cache
      final updated = _columnsByBoard[boardId]!;
      cache.put(
          'columns_$boardId',
          updated
              .map((c) => {
                    'id': c.id,
                    'title': c.title,
                    'cards': c.cards
                        .map((k) => {
                              'id': k.id,
                              'title': k.title,
                              'description': k.description,
                              'duedate': k.due?.toUtc().millisecondsSinceEpoch,
                              'order': k.order, // Save order to cache
                              'labels': k.labels
                                  .map((l) => {
                                        'id': l.id,
                                        'title': l.title,
                                        'color': l.color
                                      })
                                  .toList(),
                            })
                        .toList(),
                  })
              .toList());
      // Rebuild Upcoming view after deleting card
      _rebuildUpcomingCacheFromMemory();
      notifyListeners();
    }
    if (_localMode) return;
    if (_baseUrl == null || _username == null || _password == null) return;
    try {
      await api.deleteCard(_baseUrl!, _username!, _password!,
          boardId: boardId, stackId: stackId, cardId: cardId);
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
    // Protect the affected stack(s) from being overwritten by background fetches while update is in-flight
    _protectStack(boardId, stackId);
    var cols = _columnsByBoard[boardId];
    if (cols == null) {
      // Board is not loaded in memory, try to load from cache
      final cachedCols = cache.get('columns_$boardId');
      if (cachedCols is List) {
        _columnsByBoard[boardId] = _parseCachedColumns(cachedCols);
        cols = _columnsByBoard[boardId]!;
      } else {
        // No data available, cannot update card
        return;
      }
    }
    int fromIndex = cols!.indexWhere((c) => c.id == stackId);
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
      order: current.order, // Preserve card order
    );
    // Apply in place || move to another stack
    if (moveToStackId != null && moveToStackId != stackId) {
      _protectStack(boardId, moveToStackId);
      // remove from current
      final newFromCards = _normalizeCardsOrder([...from.cards]..removeAt(cardIdx));
      _columnsByBoard[boardId] = [
        for (final c in cols)
          if (c.id == from.id)
            deck.Column(id: c.id, title: c.title, cards: newFromCards)
          else if (c.id == moveToStackId)
            deck.Column(
              id: c.id,
              title: c.title,
              cards: _normalizeCardsOrder(() {
                final list = [...c.cards];
                if (insertIndex == null) {
                  list.add(updated);
                } else {
                  final ni = insertIndex!.clamp(0, list.length);
                  list.insert(ni, updated);
                }
                return list;
              }()),
            )
          else
            c
      ];
    } else {
      final newCards = [...from.cards];
      newCards[cardIdx] = updated;
      // Normalize card order to prevent shuffling
      final normalizedCards = _normalizeCardsOrder(newCards);
      _columnsByBoard[boardId] = [
        for (final c in cols)
          if (c.id == from.id)
            deck.Column(id: c.id, title: c.title, cards: normalizedCards)
          else
            c
      ];
    }
    
    // Save updated columns to cache to persist local changes
    final updatedColumns = _columnsByBoard[boardId]!;
    cache.put(
        'columns_$boardId',
        updatedColumns
            .map((c) => {
                  'id': c.id,
                  'title': c.title,
                  'cards': c.cards
                      .map((k) => {
                            'id': k.id,
                            'title': k.title,
                            'description': k.description,
                            'duedate': k.due?.toUtc().millisecondsSinceEpoch,
                            'order': k.order, // Save order to cache
                            'labels': k.labels
                                .map((l) => {
                                      'id': l.id,
                                      'title': l.title,
                                      'color': l.color
                                    })
                                .toList(),
                          })
                      .toList(),
                })
            .toList());
            
    // Rebuild Upcoming view after local card changes
    _rebuildUpcomingCacheFromMemory();
    notifyListeners();
  }

  // Reorder card within the same stack (optimistic)
  void reorderCardLocal({
    required int boardId,
    required int stackId,
    required int cardId,
    required int newIndex,
  }) {
    _protectStack(boardId, stackId);
    var cols = _columnsByBoard[boardId];
    if (cols == null) {
      // Board is not loaded in memory, try to load from cache
      final cachedCols = cache.get('columns_$boardId');
      if (cachedCols is List) {
        _columnsByBoard[boardId] = _parseCachedColumns(cachedCols);
        cols = _columnsByBoard[boardId]!;
      } else {
        // No data available, cannot reorder card
        return;
      }
    }
    final sIdx = cols.indexWhere((c) => c.id == stackId);
    if (sIdx < 0) return;
    final stack = cols[sIdx];
    final list = List<CardItem>.from(stack.cards);
    final cIdx = list.indexWhere((k) => k.id == cardId);
    if (cIdx < 0) return;
    final item = list.removeAt(cIdx);
    final ni = newIndex.clamp(0, list.length);
    list.insert(ni, item);
    // Normalize card order after reordering
    final normalizedCards = _normalizeCardsOrder(list);
    _columnsByBoard[boardId] = [
      for (int i = 0; i < cols.length; i++)
        if (i == sIdx)
          deck.Column(id: stack.id, title: stack.title, cards: normalizedCards)
        else
          cols[i]
    ];
    
    // Save updated columns to cache to persist reordering
    final updatedColumns = _columnsByBoard[boardId]!;
    cache.put(
        'columns_$boardId',
        updatedColumns
            .map((c) => {
                  'id': c.id,
                  'title': c.title,
                  'cards': c.cards
                      .map((k) => {
                            'id': k.id,
                            'title': k.title,
                            'description': k.description,
                            'duedate': k.due?.toUtc().millisecondsSinceEpoch,
                            'order': k.order, // Save order to cache
                            'labels': k.labels
                                .map((l) => {
                                      'id': l.id,
                                      'title': l.title,
                                      'color': l.color
                                    })
                                .toList(),
                          })
                      .toList(),
                })
            .toList());
    
    // Rebuild Upcoming view after card reordering
    _rebuildUpcomingCacheFromMemory();
    notifyListeners();
  }

  // Helper: toggle global syncing spinner for short manual actions
  Future<T> runWithSyncing<T>(Future<T> Function() fn) async {
    _isSyncing = true;
    notifyListeners();
    try {
      return await fn();
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }
}
