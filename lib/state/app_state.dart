import 'package:flutter/cupertino.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/scheduler.dart';
import 'package:hive/hive.dart';

import '../models/board.dart';
import '../models/column.dart' as deck;
import '../models/card_item.dart';
import '../models/label.dart';
import '../models/user_ref.dart';
import '../services/nextcloud_deck_api.dart';
import '../services/notification_service.dart';
import '../services/deep_link_service.dart';
import '../services/widget_service.dart';
import '../sync/sync_service.dart';
import '../sync/sync_service_impl.dart';

class AppState extends ChangeNotifier {
  final storage = const FlutterSecureStorage();
  final CupertinoTabController tabController =
      CupertinoTabController(initialIndex: 1);
  final Box cache = Hive.box('nextdeck_cache');

  bool _initialized = false;
  bool _isDarkMode = false;
  String _themeMode = 'light'; // light | dark | system
  int _themeIndex = 0;
  bool _smartColors = true;
  bool _cardColorsFromLabels = true;
  bool _showDescriptionText = true;
  bool _overviewShowBoardInfo = true; // show board stats in overview
  String _boardBandMode = 'nextcloud'; // nextcloud | hidden
  String? _localeCode; // 'de' | 'en' | 'es' | null for system
  bool _isSyncing = false;
  String? _baseUrl;
  String? _username;
  String? _password;
  Timer? _syncTimer;
  bool _localMode = false;
  static const int localBoardId = -1;
  bool _isWarming = false;
  static const List<String> _defaultBoardColors = [
    '1E88E5',
    '43A047',
    'F4511E',
    '8E24AA',
    '00ACC1',
    '3949AB',
    'D81B60',
    '5E35B1',
    '00897B',
    'EF6C00',
  ];
  int _startupTabIndex = 1; // 0=Upcoming,1=Board,2=Overview
  bool _upcomingSingleColumn =
      false; // user setting: show Upcoming as single list
  bool _upcomingAssignedOnly = false; // user setting: show only my assigned cards
  bool _boardArchivedOnly = false; // user setting: show only archived cards on board
  bool _dueNotificationsEnabled = false; // user setting: due reminders
  bool _dueOverdueEnabled = true; // user setting: overdue reminders
  List<int> _dueReminderMinutes = const [60, 1440];
  int? _defaultBoardId; // user-selected default board for startup
  String _startupBoardMode = 'default'; // 'default' | 'last'

  List<Board> _boards = const [];
  Board? _activeBoard;
  Map<int, List<deck.Column>> _columnsByBoard = {};
  String? _lastError;
  final Set<int> _hiddenBoards = {};
  final Map<int, int> _boardMemberCount = {};
  final Map<int, Map<int, List<CardItem>>> _archivedCardsByBoard = {};
  final Set<int> _archivedCardsLoading = {};
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
  String get themeMode => _themeMode;
  int get themeIndex => _themeIndex;
  bool get smartColors => _smartColors;
  bool get cardColorsFromLabels => _cardColorsFromLabels;
  bool get showDescriptionText => _showDescriptionText;
  bool get overviewShowBoardInfo => _overviewShowBoardInfo;
  String get boardBandMode => _boardBandMode;
  String? get localeCode => _localeCode;
  bool get isSyncing => _isSyncing;
  bool get isWarming => _isWarming;
  int get startupTabIndex => _startupTabIndex;
  bool get upcomingSingleColumn => _upcomingSingleColumn;
  bool get upcomingAssignedOnly => _upcomingAssignedOnly;
  bool get boardArchivedOnly => _boardArchivedOnly;
  bool get dueNotificationsEnabled => _dueNotificationsEnabled;
  bool get dueOverdueEnabled => _dueOverdueEnabled;
  bool get dueReminder1hEnabled => _dueReminderMinutes.contains(60);
  bool get dueReminder1dEnabled => _dueReminderMinutes.contains(1440);
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
  Map<int, List<CardItem>> archivedCardsForBoard(int boardId) =>
      _archivedCardsByBoard[boardId] ?? <int, List<CardItem>>{};
  bool isArchivedCardsLoading(int boardId) =>
      _archivedCardsLoading.contains(boardId);
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
  final NotificationService _notifications = NotificationService();
  final WidgetService _widgetService = WidgetService();
  SyncService? _sync;
  StreamSubscription<Uri>? _deepLinkSub;
  int? _pendingOpenBoardId;
  int? _pendingQuickAddBoardId;
  PendingCardOpen? _pendingOpenCard;
  bool _bootSyncing = false;
  String? _bootMessage;
  bool get bootSyncing => _bootSyncing;
  String? get bootMessage => _bootMessage;

  @override
  void dispose() {
    _deepLinkSub?.cancel();
    super.dispose();
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    if (Platform.isIOS) {
      await DeepLinkService.instance.init();
      _deepLinkSub ??=
          DeepLinkService.instance.links.listen((uri) => unawaited(_handleDeepLink(uri)));
    }
    final String? storedThemeMode = await storage.read(key: 'themeMode');
    if (storedThemeMode == 'light' ||
        storedThemeMode == 'dark' ||
        storedThemeMode == 'system') {
      _themeMode = storedThemeMode!;
    } else {
      _themeMode = (await storage.read(key: 'dark')) == '1' ? 'dark' : 'light';
    }
    _isDarkMode =
        _resolveDarkMode(SchedulerBinding.instance.platformDispatcher.platformBrightness);
    _themeIndex =
        int.tryParse(await storage.read(key: 'themeIndex') ?? '') ?? 0;
    _smartColors = (await storage.read(key: 'smartColors')) != '0';
    _cardColorsFromLabels =
        (await storage.read(key: 'card_colors_from_labels')) != '0';
    _showDescriptionText =
        (await storage.read(key: 'showDescriptionText')) != '0';
    _upcomingSingleColumn = (await storage.read(key: 'up_single')) == '1';
    _upcomingAssignedOnly =
        (await storage.read(key: 'up_assigned_only')) == '1';
    _boardArchivedOnly =
        (await storage.read(key: 'board_archived_only')) == '1';
    _overviewShowBoardInfo =
        (await storage.read(key: 'overview_board_info')) != '0';
    final bandMode = await storage.read(key: 'board_band_mode');
    if (bandMode == 'nextcloud' || bandMode == 'hidden') {
      _boardBandMode = bandMode!;
    }
    _dueNotificationsEnabled =
        (await storage.read(key: 'due_notif_enabled')) == '1';
    _dueOverdueEnabled =
        (await storage.read(key: 'due_notif_overdue')) != '0';
    _dueReminderMinutes =
        _parseReminderMinutes(await storage.read(key: 'due_notif_offsets')) ??
            const [60, 1440];
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
    if (_dueNotificationsEnabled && Platform.isIOS) {
      try {
        await _notifications.init(requestPermissions: false);
      } catch (_) {}
    }
    final activeBoardIdStr = await storage.read(key: 'activeBoardId');
    if (_localMode) {
      _setupLocalBoard();
      unawaited(_updateWidgetData());
      notifyListeners();
      return;
    }
    if (_baseUrl != null && _username != null && _password != null) {
      // One-time cache migration: clear old caches without order data
      final migrationDone = cache.get('cache_migration_v2');
      if (migrationDone != true) {
        print('[STATE init] Running cache migration - clearing old column caches...');
        final boards = cache.get('boards');
        if (boards is List) {
          for (final b in boards) {
            if (b is Map) {
              final id = b['id'];
              if (id is num) {
                cache.delete('columns_${id.toInt()}');
              }
            }
          }
        }
        cache.put('cache_migration_v2', true);
        print('[STATE init] Cache migration complete');
      }
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
            // Fetch boards once to drop deleted boards from cache/UI
            try {
              await refreshBoards(forceNetwork: true);
            } catch (_) {}
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
      // Fetch boards once to drop deleted boards from cache/UI
      try {
        await refreshBoards(forceNetwork: true);
      } catch (_) {}
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
            if (k.done != null) continue;
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
    setThemeMode(value ? 'dark' : 'light');
  }

  void setThemeMode(String mode, {Brightness? platformBrightness}) {
    if (mode != 'light' && mode != 'dark' && mode != 'system') return;
    _themeMode = mode;
    storage.write(key: 'themeMode', value: mode);
    // keep legacy flag in sync for older installs
    storage.write(key: 'dark', value: mode == 'dark' ? '1' : '0');
    final b = platformBrightness ??
        SchedulerBinding.instance.platformDispatcher.platformBrightness;
    final next = _resolveDarkMode(b);
    if (next != _isDarkMode) {
      _isDarkMode = next;
      notifyListeners();
    } else {
      notifyListeners();
    }
  }

  void setThemeIndex(int index) {
    _themeIndex = index.clamp(0, 4);
    storage.write(key: 'themeIndex', value: _themeIndex.toString());
    notifyListeners();
  }

  void updatePlatformBrightness(Brightness brightness) {
    if (_themeMode != 'system') return;
    final next = _resolveDarkMode(brightness);
    if (next != _isDarkMode) {
      _isDarkMode = next;
      notifyListeners();
    }
  }

  bool _resolveDarkMode(Brightness brightness) {
    if (_themeMode == 'dark') return true;
    if (_themeMode == 'light') return false;
    return brightness == Brightness.dark;
  }

  void setSmartColors(bool value) {
    _smartColors = value;
    storage.write(key: 'smartColors', value: value ? '1' : '0');
    notifyListeners();
  }

  void setCardColorsFromLabels(bool value) {
    _cardColorsFromLabels = value;
    storage.write(
        key: 'card_colors_from_labels', value: value ? '1' : '0');
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

  void setBoardBandMode(String mode) {
    if (mode != 'nextcloud' && mode != 'hidden') return;
    _boardBandMode = mode;
    storage.write(key: 'board_band_mode', value: mode);
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

  bool hasPendingQuickAddFor(int boardId) =>
      _pendingQuickAddBoardId == boardId;

  void clearPendingQuickAdd() {
    _pendingQuickAddBoardId = null;
  }

  bool hasPendingOpenCardFor(int boardId) =>
      _pendingOpenCard?.boardId == boardId;

  PendingCardOpen? consumePendingOpenCard(int boardId) {
    final pending = _pendingOpenCard;
    if (pending == null || pending.boardId != boardId) return null;
    _pendingOpenCard = null;
    return pending;
  }

  PendingCardOpen? get pendingOpenCard => _pendingOpenCard;

  PendingCardOpen? consumePendingOpenCardAny() {
    final pending = _pendingOpenCard;
    _pendingOpenCard = null;
    return pending;
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
      cache.put('columns_$localBoardId', _serializeColumnsForCache(initCols));
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

  Future<void> refreshBoards({bool forceNetwork = false}) async {
    if (_localMode) return;
    if (_baseUrl == null || _username == null || _password == null) return;

    final detailsEtagKey = 'etag_boards_details';

    FetchBoardsDetailsResult res;
    try {
      final prevDetailsEtag =
          forceNetwork ? null : cache.get(detailsEtagKey) as String?;
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
      unawaited(_updateWidgetData());
      notifyListeners();
      return;
    }

    if (res.notModified) {
      await _ensureActiveBoardValid();
      _rebuildUpcomingCacheFromMemory();
      unawaited(_updateWidgetData());
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

      // Build order map from stacks
      final Map<int, int> orderMap = {};
      for (final entry in stacks.whereType<Map>()) {
        final sid = entry['id'];
        if (sid is num) {
          final id = sid.toInt();
          final ord = entry['order'];
          orderMap[id] = ord is num ? ord.toInt() : 999999;
        }
      }

      final boardId = (board['id'] as num?)?.toInt();
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
        final order = orderMap[stackId];

        // Check if this stack is protected (has recent local changes)
        final isProtected = boardId != null && _isStackProtected(boardId, stackId);

        if (isProtected) {
          // Use cards from previous/local state for protected stacks
          final prev = previous.firstWhere(
            (element) => element.id == stackId,
            orElse: () => deck.Column(id: stackId, title: title, cards: const [], order: order),
          );
          cols.add(deck.Column(id: stackId, title: title, cards: prev.cards, order: order));
          continue;
        }

        final cardsRaw = (stack['cards'] is List)
            ? (stack['cards'] as List)
                .whereType<Map>()
                .map((e) => e.cast<String, dynamic>())
                .toList()
            : const <Map<String, dynamic>>[];
        final parsedCards = cardsRaw.map(CardItem.fromJson).toList();

        // Try to get cards from previous state if available
        final prev = previous.firstWhere(
          (element) => element.id == stackId,
          orElse: () => deck.Column(id: stackId, title: title, cards: const [], order: order),
        );

        // Use parsed cards if available, otherwise try fallbacks
        if (parsedCards.isNotEmpty) {
          cols.add(deck.Column(id: stackId, title: title, cards: parsedCards, order: order));
          continue;
        }

        final fallback = cardsByStack[stackId];
        if (fallback != null && fallback.isNotEmpty) {
          cols.add(deck.Column(id: stackId, title: title, cards: fallback, order: order));
          continue;
        }

        // If server returned empty but we have local cards, keep them
        // This handles the case where the API doesn't include cards in the response
        if (prev.cards.isNotEmpty) {
          cols.add(deck.Column(id: stackId, title: title, cards: prev.cards, order: order));
          continue;
        }

        // Last resort: empty stack
        cols.add(deck.Column(id: stackId, title: title, cards: const [], order: order));
      }

      // Sort columns by order field (ascending)
      cols.sort((a, b) {
        final oa = a.order ?? 999999;
        final ob = b.order ?? 999999;
        return oa.compareTo(ob);
      });

      return cols;
    }

    for (final raw in res.boards.whereType<Map>()) {
      final map = raw.cast<String, dynamic>();
      final id = (map['id'] as num?)?.toInt();
      if (id == null) continue;
      // Skip boards marked as deleted by server (Nextcloud sets deletedAt timestamp)
      final deletedAt = map['deletedAt'] ?? map['deleted_at'] ?? map['deleted_at_utc'];
      if (deletedAt is num && deletedAt.toInt() != 0) {
        // Purge caches for this board
        cache.delete('columns_$id');
        cache.delete('board_members_$id');
        cache.delete('board_lastmod_$id');
        cache.delete('board_lastmod_prev_$id');
        cache.delete('stacks_$id');
        continue;
      }
      // Debug: log possible deletion/archive flags from server payload
      final dbg = <String, dynamic>{};
      for (final entry in map.entries) {
        final k = entry.key.toLowerCase();
        if (k == 'id' || k == 'title' || k == 'archived') {
          dbg[entry.key] = entry.value;
        }
        if (k.contains('delete') || k.contains('archive') || k.contains('trash')) {
          dbg[entry.key] = entry.value;
        }
      }
      if (dbg.length > 3) {
        print('[refreshBoards] board raw flags: $dbg');
      }
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
      cache.put('columns_$id', _serializeColumnsForCache(columns));
    }

    // Log server boards for manual diagnostics
    final boardLog = updatedBoards.map((b) => '${b.id}:${b.title}').join(', ');
    print('[refreshBoards] server returned boards (${updatedBoards.length}): $boardLog');

    final previousBoardIds = _boards.map((b) => b.id).toSet();
    _boards = updatedBoards;
    // Update only the boards that were returned from the server, keep others
    for (final entry in updatedColumns.entries) {
      _columnsByBoard[entry.key] = entry.value;
    }
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
    // Remove deleted boards from memory and cache
    for (final rid in previousBoardIds.difference(currentIds)) {
      _columnsByBoard.remove(rid);
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
    if (_dueNotificationsEnabled && Platform.isIOS) {
      unawaited(_rescheduleDueNotificationsFromMemory());
    }
    unawaited(_updateWidgetData());
    unawaited(_applyPendingDeepLinkIfReady());
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

  Future<void> _handleDeepLink(Uri uri) async {
    final action = uri.host.isNotEmpty
        ? uri.host
        : (uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '');
    final boardId = int.tryParse(uri.queryParameters['board'] ?? '');
    final cardId = int.tryParse(uri.queryParameters['card'] ?? '');
    final stackId = int.tryParse(uri.queryParameters['stack'] ?? '');
    final edit = uri.queryParameters['edit'] == '1';
    if (action == 'quick-add') {
      await _queueDeepLinkAction(boardId, quickAdd: true);
      return;
    }
    if (action == 'card') {
      if (boardId == null || cardId == null) return;
      await _queueCardDeepLink(
          boardId: boardId, cardId: cardId, stackId: stackId, edit: edit);
      return;
    }
    if (action == 'open' || action == 'board') {
      await _queueDeepLinkAction(boardId, quickAdd: false);
    }
  }

  Future<void> _queueDeepLinkAction(int? boardId,
      {required bool quickAdd}) async {
    final resolved = boardId ?? _defaultBoardId ?? _activeBoard?.id;
    if (resolved == null) return;
    _pendingOpenBoardId = resolved;
    if (quickAdd) _pendingQuickAddBoardId = resolved;
    await _applyPendingDeepLinkIfReady();
  }

  Future<void> _queueCardDeepLink(
      {required int boardId,
      required int cardId,
      int? stackId,
      required bool edit}) async {
    _pendingOpenCard = PendingCardOpen(
        cardId: cardId, boardId: boardId, stackId: stackId, edit: edit);
    _pendingOpenBoardId = boardId;
    notifyListeners();
    await _applyPendingDeepLinkIfReady();
  }

  Future<void> _applyPendingDeepLinkIfReady() async {
    if (_pendingOpenBoardId == null) return;
    final target = _boards.firstWhere(
      (b) => b.id == _pendingOpenBoardId,
      orElse: () => Board.empty(),
    );
    if (target.id < 0) return;
    final quickAdd = _pendingQuickAddBoardId == target.id;
    _pendingOpenBoardId = null;
    await _openBoardFromDeepLink(target, quickAdd: quickAdd);
  }

  Future<void> _openBoardFromDeepLink(Board board,
      {required bool quickAdd}) async {
    await setActiveBoard(board);
    if (columnsForBoard(board.id).isEmpty) {
      await refreshColumnsFor(board, forceNetwork: true);
    }
    selectTab(1);
    if (quickAdd) _pendingQuickAddBoardId = board.id;
  }

  Map<String, dynamic> _buildWidgetPayload() {
    final visibleBoards = _boards
        .where((b) => !b.archived && !_hiddenBoards.contains(b.id))
        .toList();
    final cards = <Map<String, dynamic>>[];
    const maxCards = 300;
    for (final b in visibleBoards) {
      final cols = _columnsByBoard[b.id] ?? const <deck.Column>[];
      for (final col in cols) {
        for (final card in col.cards) {
          if (cards.length >= maxCards) break;
          if (card.archived) continue;
          if (card.done != null) continue;
          cards.add({
            'id': card.id,
            'title': card.title,
            'boardId': b.id,
            'columnId': col.id,
            if (card.due != null)
              'due': card.due!.toUtc().millisecondsSinceEpoch,
            'assignedToMe': _isAssignedToMe(card),
          });
        }
        if (cards.length >= maxCards) break;
      }
      if (cards.length >= maxCards) break;
    }
    return {
      'updatedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
      'defaultBoardId': _defaultBoardId ?? _activeBoard?.id,
      'boards': visibleBoards
          .map((b) => {
                'id': b.id,
                'title': b.title,
                if (b.color != null) 'color': b.color,
              })
          .toList(),
      'cards': cards,
    };
  }

  Future<void> _updateWidgetData() async {
    if (!Platform.isIOS) return;
    try {
      await _widgetService.updateWidgetData(_buildWidgetPayload());
    } catch (_) {
      // ignore widget update errors
    }
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

    if (res.notModified) {
      _lastError = null; // Clear any previous errors when 304 (data is still valid)
      return false;
    }

    final merged = List<deck.Column>.from(res.columns);

    // Preserve cards from protected stacks OR when server returns empty cards
    final existingCols = _columnsByBoard[board.id];
    if (existingCols != null) {
      for (int i = 0; i < merged.length; i++) {
        final newStack = merged[i];
        final existingStack = existingCols.firstWhere(
          (c) => c.id == newStack.id,
          orElse: () => newStack,
        );

        // Keep local cards if:
        // 1. Stack is protected (recent local changes)
        // 2. Server returned empty cards but we have cards locally
        if (existingStack.id == newStack.id) {
          final shouldKeepLocal = _isStackProtected(board.id, newStack.id) ||
              (newStack.cards.isEmpty && existingStack.cards.isNotEmpty);

          if (shouldKeepLocal) {
            merged[i] = deck.Column(
              id: newStack.id,
              title: newStack.title,
              cards: existingStack.cards, // Keep local cards
              order: newStack.order,
            );
          }
        }
      }
    }

    _columnsByBoard[board.id] = merged;
    for (final c in merged) {
      _stackLoaded.add(c.id);
    }
    final serialized = _serializeColumnsForCache(merged);
    cache.put('columns_${board.id}', serialized);
    if (res.etag != null) cache.put(etagKey, res.etag);
    for (final c in merged) {
      _stackLoaded.add(c.id);
    }
    _lastError = null;
    unawaited(_updateWidgetData());
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
        deck.Column(
            id: nextId,
            title: title,
            cards: const [],
            order: cols.length)
      ];
      _columnsByBoard[boardId] = updated;
      cache.put('local_next_stack_id', nextId);
      cache.put('columns_$boardId', _serializeColumnsForCache(updated));
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
        final existing = _columnsByBoard[boardId] ?? const <deck.Column>[];
        final nextOrder = existing.length;
        final updated = [
          ...existing,
          deck.Column(
              id: created.id,
              title: created.title,
              cards: const [],
              order: created.order ?? nextOrder)
        ];
        _columnsByBoard[boardId] = updated;
        cache.put('columns_$boardId', _serializeColumnsForCache(updated));
        notifyListeners();
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> deleteStack(
      {required int boardId, required int stackId}) async {
    if (_localMode) {
      final cols = _columnsByBoard[boardId] ?? const <deck.Column>[];
      final updated = cols.where((c) => c.id != stackId).toList();
      _columnsByBoard[boardId] = updated;
      cache.put('columns_$boardId', _serializeColumnsForCache(updated));
      notifyListeners();
      return true;
    }
    if (_baseUrl == null || _username == null || _password == null)
      return false;
    try {
      final ok = await api.deleteStack(
          _baseUrl!, _username!, _password!, boardId, stackId);
      if (ok) {
        final cols = _columnsByBoard[boardId] ?? const <deck.Column>[];
        final updated = cols.where((c) => c.id != stackId).toList();
        _columnsByBoard[boardId] = updated;
        cache.put('columns_$boardId', _serializeColumnsForCache(updated));
        notifyListeners();
      }
      return ok;
    } catch (_) {}
    return false;
  }

  int _normalizeReorderIndex(int oldIndex, int newIndex, int length) {
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    if (target < 0) target = 0;
    if (target >= length) target = length - 1;
    return target;
  }

  void reorderStackLocal(
      {required int boardId, required int oldIndex, required int newIndex}) {
    final cols = _columnsByBoard[boardId];
    if (cols == null || cols.isEmpty) return;
    if (oldIndex < 0 || oldIndex >= cols.length) return;
    final target = _normalizeReorderIndex(oldIndex, newIndex, cols.length);
    final list = List<deck.Column>.from(cols);
    final moved = list.removeAt(oldIndex);
    list.insert(target, moved);
    final updated = <deck.Column>[];
    for (int i = 0; i < list.length; i++) {
      final c = list[i];
      updated.add(deck.Column(
          id: c.id, title: c.title, cards: c.cards, order: i));
    }
    _columnsByBoard[boardId] = updated;
    cache.put('columns_$boardId', _serializeColumnsForCache(updated));
    notifyListeners();
  }

  Future<void> reorderStack(
      {required int boardId, required int oldIndex, required int newIndex}) async {
    final cols = _columnsByBoard[boardId];
    if (cols == null || cols.isEmpty) return;
    if (oldIndex < 0 || oldIndex >= cols.length) return;
    final target = _normalizeReorderIndex(oldIndex, newIndex, cols.length);
    final moved = cols[oldIndex];
    if (target == oldIndex) return;
    reorderStackLocal(boardId: boardId, oldIndex: oldIndex, newIndex: newIndex);
    if (_localMode) return;
    if (_baseUrl == null || _username == null || _password == null) return;
    try {
      final updated = _columnsByBoard[boardId] ?? const <deck.Column>[];
      final start = math.min(oldIndex, target);
      final end = math.max(oldIndex, target);
      for (int i = start; i <= end && i < updated.length; i++) {
        final c = updated[i];
        await api.updateStack(_baseUrl!, _username!, _password!, boardId, c.id,
            title: c.title, order: i);
      }
    } catch (_) {}
  }

  Future<Board?> createBoard(
      {required String title, String? color, bool activate = true}) async {
    if (_localMode) {
      // Create a local board stub is out of scope for now
      return null;
    }
    if (_baseUrl == null || _username == null || _password == null) return null;
    try {
      final normalizedColor = _normalizeBoardColor(
          (color == null || color.trim().isEmpty)
              ? _defaultBoardColors[_boards.length % _defaultBoardColors.length]
              : color);
      final created = await api.createBoard(_baseUrl!, _username!, _password!,
          title: title, color: normalizedColor);
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

  Future<bool> updateBoardColor(
      {required int boardId, required String color}) async {
    final idx = _boards.indexWhere((b) => b.id == boardId);
    if (idx < 0) return false;
    final board = _boards[idx];
    final normalizedColor = _normalizeBoardColor(color);
    if (_localMode) {
      final updated = Board(
          id: board.id,
          title: board.title,
          color: normalizedColor,
          archived: board.archived);
      _boards = [
        ..._boards.sublist(0, idx),
        updated,
        ..._boards.sublist(idx + 1),
      ];
      if (_activeBoard?.id == boardId) _activeBoard = updated;
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
      notifyListeners();
      return true;
    }
    if (_baseUrl == null || _username == null || _password == null)
      return false;
    try {
      final ok = await api.updateBoard(_baseUrl!, _username!, _password!,
          boardId,
          title: board.title, color: normalizedColor, archived: board.archived);
      if (!ok) return false;
      final updated = Board(
          id: board.id,
          title: board.title,
          color: normalizedColor,
          archived: board.archived);
      _boards = [
        ..._boards.sublist(0, idx),
        updated,
        ..._boards.sublist(idx + 1),
      ];
      if (_activeBoard?.id == boardId) _activeBoard = updated;
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
      notifyListeners();
      return true;
    } catch (_) {}
    return false;
  }

  String _normalizeBoardColor(String value) {
    var s = value.trim();
    if (s.startsWith('#')) s = s.substring(1);
    if (s.length == 3) {
      s = s.split('').map((c) => '$c$c').join();
    } else if (s.length == 8 && s.startsWith('FF')) {
      s = s.substring(2);
    }
    if (s.length > 6) s = s.substring(0, 6);
    return s;
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

  void setUpcomingAssignedOnly(bool value) {
    _upcomingAssignedOnly = value;
    storage.write(key: 'up_assigned_only', value: value ? '1' : '0');
    _rebuildUpcomingCacheFromMemory();
    notifyListeners();
  }

  void setBoardArchivedOnly(bool value) {
    _boardArchivedOnly = value;
    storage.write(key: 'board_archived_only', value: value ? '1' : '0');
    notifyListeners();
  }

  Future<void> refreshArchivedCardsForBoard(int boardId) async {
    if (_localMode) return;
    if (_baseUrl == null || _username == null || _password == null) return;
    if (_archivedCardsLoading.contains(boardId)) return;
    _archivedCardsLoading.add(boardId);
    notifyListeners();
    try {
      final stacks =
          await api.fetchArchivedStacks(_baseUrl!, _username!, _password!, boardId);
      final map = <int, List<CardItem>>{};
      for (final c in stacks) {
        map[c.id] = c.cards;
      }
      _archivedCardsByBoard[boardId] = map;
      notifyListeners();
    } catch (_) {
    } finally {
      _archivedCardsLoading.remove(boardId);
      notifyListeners();
    }
  }

  Future<void> setDueNotificationsEnabled(bool value) async {
    _dueNotificationsEnabled = value;
    await storage.write(key: 'due_notif_enabled', value: value ? '1' : '0');
    notifyListeners();
    if (!Platform.isIOS) return;
    if (value) {
      await _notifications.init(requestPermissions: true);
      unawaited(_rescheduleDueNotificationsFromMemory());
    } else {
      await _notifications.cancelAll();
    }
  }

  void setDueReminderOffsetEnabled(int minutes, bool enabled) {
    final next = [..._dueReminderMinutes];
    if (enabled) {
      if (!next.contains(minutes)) next.add(minutes);
    } else {
      next.remove(minutes);
    }
    next.sort();
    _dueReminderMinutes = next;
    storage.write(key: 'due_notif_offsets', value: _dueReminderMinutes.join(','));
    notifyListeners();
    if (_dueNotificationsEnabled && Platform.isIOS) {
      unawaited(_rescheduleDueNotificationsFromMemory());
    }
  }

  void setDueOverdueEnabled(bool value) {
    _dueOverdueEnabled = value;
    storage.write(key: 'due_notif_overdue', value: value ? '1' : '0');
    notifyListeners();
    if (_dueNotificationsEnabled && Platform.isIOS) {
      unawaited(_rescheduleDueNotificationsFromMemory());
    }
  }

  bool shouldIncludeAssignedCard(CardItem card) {
    if (!_upcomingAssignedOnly) return true;
    if (card.assignees.isEmpty) return false;
    return _isAssignedToMe(card);
  }

  bool _isAssignedToMe(CardItem card) {
    final me = _username?.toLowerCase();
    if (me == null || me.isEmpty) return false;
    for (final u in card.assignees) {
      final id = u.id.toLowerCase();
      if (id == me) return true;
      final alt = u.altId;
      if (alt != null && alt.toLowerCase() == me) return true;
    }
    return false;
  }

  List<int>? _parseReminderMinutes(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final parts = raw.split(',').map((e) => int.tryParse(e.trim()));
    final out = <int>[];
    for (final p in parts) {
      if (p != null && p > 0) out.add(p);
    }
    return out.isEmpty ? null : out;
  }

  List<Duration> _dueReminderOffsets() {
    return _dueReminderMinutes.map((m) => Duration(minutes: m)).toList();
  }

  List<CardItem> _collectDueCards() {
    final out = <CardItem>[];
    final seen = <int>{};
    for (final cols in _columnsByBoard.values) {
      for (final col in cols) {
        for (final card in col.cards) {
          if (card.due == null || card.done != null) continue;
          if (seen.add(card.id)) out.add(card);
        }
      }
    }
    return out;
  }

  Future<void> _rescheduleDueNotificationsFromMemory() async {
    if (!_dueNotificationsEnabled || !Platform.isIOS) return;
    final cards = _collectDueCards();
    await _notifications.rescheduleAll(
      cards,
      offsets: _dueReminderOffsets(),
      includeOverdue: _dueOverdueEnabled,
      localeCode: _localeCode,
    );
  }

  CardItem? _findCardInBoard(int boardId, int cardId) {
    final cols = _columnsByBoard[boardId];
    if (cols == null) return null;
    for (final c in cols) {
      for (final card in c.cards) {
        if (card.id == cardId) return card;
      }
    }
    return null;
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
        if (card.done != null)
          payload['done'] = card.done!.toUtc().toIso8601String();
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
          // Force network request if board was detected as changed to get fresh data
          boardUpdated = await refreshColumnsFor(
            b,
            bypassCooldown: true,
            full: shouldForce,
            forceNetwork: shouldForce, // Use network if board changed
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

  Future<void> refreshUpcomingAssigneesIfNeeded() async {
    if (_localMode) return;
    if (_baseUrl == null || _username == null || _password == null) return;
    final refs = upcomingCacheRefs();
    if (refs == null) return;
    final boardsToRefresh = <int>{};
    for (final bucket in refs.values) {
      for (final e in bucket) {
        final bId = e['b'];
        final sId = e['s'];
        final cId = e['c'];
        if (bId == null || sId == null || cId == null) continue;
        if (boardsToRefresh.contains(bId)) continue;
        if (!_cachedCardHasAssignees(bId, sId, cId)) {
          boardsToRefresh.add(bId);
        }
      }
    }
    if (boardsToRefresh.isEmpty) return;
    _upScanActive = true;
    _upScanTotal = boardsToRefresh.length;
    _upScanDone = 0;
    _upScanBoardTitle = null;
    notifyListeners();
    try {
      for (final bId in boardsToRefresh) {
        final board = _boards.firstWhere(
          (b) => b.id == bId,
          orElse: () => Board(id: bId, title: '', color: null, archived: false),
        );
        _upScanBoardTitle = board.title;
        notifyListeners();
        try {
          await refreshColumnsFor(
            board,
            bypassCooldown: true,
            full: true,
            forceNetwork: true,
          );
        } catch (_) {}
        _upScanDone = (_upScanDone + 1).clamp(0, _upScanTotal);
        notifyListeners();
      }
    } finally {
      _upScanActive = false;
      _upScanBoardTitle = null;
      notifyListeners();
    }
    _rebuildUpcomingCacheFromMemory();
    notifyListeners();
  }

  bool _cachedCardHasAssignees(int boardId, int stackId, int cardId) {
    final cols = cache.get('columns_$boardId');
    if (cols is! List) return false;
    for (final c in cols) {
      if (c is! Map) continue;
      final cid = c['id'];
      if (cid is num && cid.toInt() != stackId) continue;
      if (cid is int && cid != stackId) continue;
      final cards = c['cards'];
      if (cards is! List) return false;
      for (final k in cards) {
        if (k is! Map) continue;
        final kid = k['id'];
        final idMatch = (kid is num && kid.toInt() == cardId) ||
            (kid is int && kid == cardId);
        if (!idMatch) continue;
        return k.containsKey('assignedUsers');
      }
    }
    return false;
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
    final effectivePatch = Map<String, dynamic>.from(patch);
    if (!effectivePatch.containsKey('done')) {
      final local = _findCardInBoard(boardId, cardId);
      if (local?.done != null) {
        effectivePatch['done'] = local!.done!.toUtc().toIso8601String();
      }
    }
    try {
      await api.updateCard(
          _baseUrl!, _username!, _password!, boardId, stackId, cardId, effectivePatch);
      // Apply successful server response locally to ensure consistency
    final doneValue = () {
        if (!effectivePatch.containsKey('done')) return null;
        final v = effectivePatch['done'];
        if (v == null || v == false) return null;
        if (v is DateTime) return v.toLocal();
        if (v is int) {
          final ts = v > 100000000000 ? v ~/ 1000 : v;
          return DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true)
              .toLocal();
        }
        if (v is String) return DateTime.tryParse(v)?.toLocal();
      return null;
    }();
    final clearDone = effectivePatch.containsKey('done') && doneValue == null;
    final archivedValue = () {
      if (!effectivePatch.containsKey('archived')) return null;
      final v = effectivePatch['archived'];
      if (v is bool) return v;
      if (v is num) return v != 0;
      return null;
    }();
    updateLocalCard(
      boardId: boardId,
      stackId: stackId,
      cardId: cardId,
      title: patch['title'] as String?,
      description: patch['description'] as String?,
      due: patch['duedate'] != null ? DateTime.parse(patch['duedate'] as String) : null,
      clearDue: patch.containsKey('duedate') && patch['duedate'] == null,
      done: doneValue,
      clearDone: clearDone,
      archived: archivedValue,
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
        final cachedColumns = _parseCachedColumns(cols);

        // Preserve cards from protected stacks (stacks with recent local changes)
        final existingColumns = _columnsByBoard[b.id];
        if (existingColumns != null) {
          for (int i = 0; i < cachedColumns.length; i++) {
            final cachedStack = cachedColumns[i];
            if (_isStackProtected(b.id, cachedStack.id)) {
              // Stack is protected - keep local cards instead of overwriting with cached data
              final existingStack = existingColumns.firstWhere(
                (c) => c.id == cachedStack.id,
                orElse: () => cachedStack,
              );
              if (existingStack.id == cachedStack.id) {
                cachedColumns[i] = deck.Column(
                  id: cachedStack.id,
                  title: cachedStack.title,
                  cards: existingStack.cards, // Keep local cards
                  order: cachedStack.order,
                );
              }
            }
          }
        }

        _columnsByBoard[b.id] = cachedColumns;
      }
    }
    // Members cache (best-effort)
    for (final b in _boards) {
      final m = cache.get('board_members_${b.id}');
      if (m is int) {
        _boardMemberCount[b.id] = m;
      }
    }
    if (_dueNotificationsEnabled && Platform.isIOS) {
      unawaited(_rescheduleDueNotificationsFromMemory());
    }
  }

  void setBoardHidden(int boardId, bool hidden) {
    if (hidden) {
      _hiddenBoards.add(boardId);
    } else {
      _hiddenBoards.remove(boardId);
    }
    cache.put('hiddenBoards', _hiddenBoards.toList());
    unawaited(_updateWidgetData());
    notifyListeners();
  }

  void toggleBoardHidden(int boardId) =>
      setBoardHidden(boardId, !isBoardHidden(boardId));

  // Helper to serialize columns to cache with proper order
  List<Map<String, dynamic>> _serializeColumnsForCache(List<deck.Column> columns) {
    return columns
        .map((col) => {
              'id': col.id,
              'title': col.title,
              'order': col.order, // Save real order value from server
              'cards': col.cards
                  .map((k) => {
                        'id': k.id,
                        'title': k.title,
                        'description': k.description,
                        'duedate': k.due?.toUtc().millisecondsSinceEpoch,
                        'done': k.done?.toUtc().millisecondsSinceEpoch,
                        'archived': k.archived,
                        'order': k.order, // Save card order to cache
                        'assignedUsers': k.assignees
                            .map((u) => {
                                  'id': u.id,
                                  'displayName': u.displayName,
                                  'unique': u.altId,
                                  'shareType': u.shareType,
                                })
                            .toList(),
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
        .toList();
  }

  List<deck.Column> _parseCachedColumns(List colsRaw) {
    final parsed = <deck.Column>[];

    for (int idx = 0; idx < colsRaw.length; idx++) {
      final c = colsRaw[idx];
      if (c is! Map) continue;
      final colId = (c['id'] as num).toInt();
      final colOrder = c['order'];
      int? order;
      if (colOrder is num) {
        order = colOrder.toInt();
      } else {
        // Legacy cache without order - use index as fallback
        order = idx;
      }

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
          DateTime? done;
          final dn = k['done'];
          if (dn is int) {
            done =
                DateTime.fromMillisecondsSinceEpoch(dn, isUtc: true).toLocal();
          }
          final archivedRaw = k['archived'];
          final archived = archivedRaw is bool
              ? archivedRaw
              : (archivedRaw is num ? archivedRaw != 0 : false);
          final assignees = <UserRef>[];
          final rawAssignees = k['assignedUsers'];
          if (rawAssignees is List) {
            for (final item in rawAssignees) {
              if (item is Map) {
                assignees.add(
                    UserRef.fromJson(item.cast<String, dynamic>()));
              } else if (item is String) {
                assignees.add(UserRef(id: item, displayName: item));
              }
            }
          }
          cards.add(CardItem(
            id: (k['id'] as num).toInt(),
            title: (k['title'] ?? '').toString(),
            description: (k['description'] as String?),
            due: due,
            done: done,
            archived: archived,
            assignees: assignees,
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
          id: colId,
          title: (c['title'] ?? '').toString(),
          cards: normalizedCards,
          order: order));
    }

    // Sort columns by cached order
    parsed.sort((a, b) {
      final oa = a.order ?? 999999;
      final ob = b.order ?? 999999;
      return oa.compareTo(ob);
    });

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
          due: null,
          done: null);
      final updated = [
        for (final c in cols)
          if (c.id == columnId)
            deck.Column(id: c.id, title: c.title, cards: [...c.cards, newCard])
          else
            c
      ];
      _columnsByBoard[boardId] = updated;
      cache.put('local_next_card_id', nextId + 1);
      cache.put('columns_$boardId', _serializeColumnsForCache(updated));
      unawaited(_updateWidgetData());
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
        cache.put('columns_$boardId', _serializeColumnsForCache(updated));
        // Rebuild Upcoming view after creating card
        _rebuildUpcomingCacheFromMemory();
        unawaited(_updateWidgetData());
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
      cache.put('columns_$boardId', _serializeColumnsForCache(updated));
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
    bool clearDue = false,
    DateTime? done,
    bool clearDone = false,
    bool? archived,
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
      due: clearDue ? null : (due ?? current.due),
      done: clearDone ? null : (done ?? current.done),
      archived: archived ?? current.archived,
      labels: setLabels ?? current.labels,
      assignees: setAssignees ?? current.assignees,
      order: current.order, // Preserve card order
    );
    // Apply in place || move to another stack
    if (moveToStackId != null && moveToStackId != stackId) {
      _protectStack(boardId, moveToStackId);
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
      // Keep cards in their current position, don't re-sort
      _columnsByBoard[boardId] = [
        for (final c in cols)
          if (c.id == from.id)
            deck.Column(id: c.id, title: c.title, cards: newCards)
          else
            c
      ];
    }

    // Save updated columns to cache to persist local changes
    final updatedColumns = _columnsByBoard[boardId]!;
    cache.put('columns_$boardId', _serializeColumnsForCache(updatedColumns));

    // Rebuild Upcoming view after local card changes
    _rebuildUpcomingCacheFromMemory();
    notifyListeners();
    if (_dueNotificationsEnabled && Platform.isIOS) {
      unawaited(_notifications.rescheduleForCard(
        updated,
        offsets: _dueReminderOffsets(),
        includeOverdue: _dueOverdueEnabled,
        localeCode: _localeCode,
      ));
    }
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
    // Update order properties to reflect new positions
    final reorderedCards = <CardItem>[];
    for (int i = 0; i < list.length; i++) {
      final card = list[i];
      reorderedCards.add(CardItem(
        id: card.id,
        title: card.title,
        description: card.description,
        due: card.due,
        done: card.done,
        archived: card.archived,
        labels: card.labels,
        assignees: card.assignees,
        order: i + 1, // Update order to match new position
      ));
    }
    _columnsByBoard[boardId] = [
      for (int i = 0; i < cols.length; i++)
        if (i == sIdx)
          deck.Column(id: stack.id, title: stack.title, cards: reorderedCards)
        else
          cols[i]
    ];

    // Save updated columns to cache to persist reordering
    final updatedColumns = _columnsByBoard[boardId]!;
    cache.put('columns_$boardId', _serializeColumnsForCache(updatedColumns));

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

class PendingCardOpen {
  final int cardId;
  final int boardId;
  final int? stackId;
  final bool edit;

  const PendingCardOpen({
    required this.cardId,
    required this.boardId,
    this.stackId,
    required this.edit,
  });
}
