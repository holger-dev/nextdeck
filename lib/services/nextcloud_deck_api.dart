import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/board.dart';
import '../models/column.dart' as deck;
import '../models/card_item.dart';
import '../models/user_ref.dart';
import 'log_service.dart';

class NextcloudDeckApi {
  static const _ocsHeader = {
    'OCS-APIRequest': 'true',
    'Accept': 'application/json'
  };
  static const _restHeader = {'Accept': 'application/json'};
  // Concurrency limiter and request timeout to reduce server load
  static int _maxConcurrent = 12;
  static int _maxPrioOvercommit =
      2; // allow a small burst for priority calls even when saturated
  static int _inFlight = 0;
  static int _prioBurst = 0; // how many priority waiters served consecutively
  static final List<Completer<void>> _prioWaiters = [];
  static final List<Completer<void>> _waiters = [];
  static const Duration _defaultTimeout = Duration(seconds: 30);
  // Coalesce identical stacks requests across concurrent callers (per base|user|board)
  final Map<String, Future<List<deck.Column>>> _stacksFetchFutures = {};
  final Map<String, Future<FetchStacksResult>> _stacksWithEtagFutures = {};
  final Map<String, Future<FetchBoardsDetailsResult>> _boardsDetailsFutures =
      {};
  final Map<String, Future<FetchBoardsDetailsResult>> _boardsListFutures = {};
  final Map<String, Future<FetchStacksResult>> _boardDetailsPerIdFutures = {};
  // Variant cache for board-wide cards listing
  final Map<String, String?> _boardCardsVariantCache =
      {}; // baseUrl -> working path template or null if unsupported
  final Map<String, DateTime> _boardCardsVariantExpiry =
      {}; // expiry for negative cache

  Future<void> _acquireSlot({bool priority = false}) async {
    if (_inFlight < _maxConcurrent) {
      _inFlight++;
      return;
    }
    // Allow limited overcommit for priority callers to avoid being starved by background syncs
    if (priority && _inFlight < (_maxConcurrent + _maxPrioOvercommit)) {
      _inFlight++;
      return;
    }
    final c = Completer<void>();
    if (priority) {
      _prioWaiters.add(c);
    } else {
      _waiters.add(c);
    }
    await c.future;
  }

  void _releaseSlot() {
    if (_prioWaiters.isNotEmpty && (_waiters.isEmpty || _prioBurst < 2)) {
      final c = _prioWaiters.removeAt(0);
      _prioBurst += 1;
      c.complete();
    } else if (_waiters.isNotEmpty) {
      final c = _waiters.removeAt(0);
      _prioBurst = 0; // reset burst when serving normal queue
      c.complete();
    } else {
      _inFlight = (_inFlight - 1).clamp(0, 1 << 20);
      _prioBurst = 0;
    }
  }

  // In-memory TTL caches to speed up frequent lookups
  final Map<String, _CacheEntry<UserRef?>> _meCache = {};
  final Map<String, _CacheEntry<Map<String, dynamic>?>> _boardDetailCache = {};
  final Map<String, _CacheEntry<Set<String>>> _boardMemberCache = {};
  final Map<String, _CacheEntry<List<UserRef>>> _shareesCache = {};
  static const _defaultTtlMs = 60 * 1000; // 60s for most endpoints
  static const _meTtlMs = 10 * 60 * 1000; // 10min for current user
  static const _maxCacheEntries = 120;
  // Capability cache for cards list endpoint per base URL
  final Map<String, String?> _cardsVariantCache =
      {}; // baseUrl -> working path template or null if unsupported
  final Map<String, DateTime> _cardsVariantExpiry =
      {}; // expiry for negative cache
  static const Duration _capsTtl = Duration(minutes: 20);
  // Stacks throttling + memo per board to avoid hammering
  final Map<String, DateTime> _stacksCooldown = {}; // key: base|user|boardId
  final Map<String, List<deck.Column>> _stacksMemo =
      {}; // last columns per board
  static const Duration _stacksMinInterval = Duration(seconds: 30);

  T? _getCached<T>(Map<String, _CacheEntry<T>> m, String key) {
    final e = m[key];
    if (e == null) return null;
    if (e.expires.isBefore(DateTime.now())) {
      m.remove(key);
      return null;
    }
    return e.value;
  }

  void _setCached<T>(Map<String, _CacheEntry<T>> m, String key, T value,
      {int ttlMs = _defaultTtlMs}) {
    m[key] = _CacheEntry(
        value: value,
        expires: DateTime.now().add(Duration(milliseconds: ttlMs)));
    if (m.length > _maxCacheEntries) {
      // prune expired, then oldest
      final now = DateTime.now();
      m.removeWhere((_, v) => v.expires.isBefore(now));
      if (m.length > _maxCacheEntries) {
        final oldest = m.entries.toList()
          ..sort((a, b) => a.value.expires.compareTo(b.value.expires));
        for (int i = 0; i < oldest.length - _maxCacheEntries; i++) {
          m.remove(oldest[i].key);
        }
      }
    }
  }

  Future<bool> testLogin(
      String baseUrl, String username, String password) async {
    final res =
        await _get(baseUrl, username, password, '/ocs/v2.php/cloud/user');
    if (res == null) return false;
    try {
      _parseBodyOk(_ensureOk(res, 'Login fehlgeschlagen'));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<UserRef?> fetchCurrentUser(
      String baseUrl, String username, String password) async {
    final cacheKey = 'me|$baseUrl|$username';
    final cached = _getCached(_meCache, cacheKey);
    if (cached != null) return cached;
    final res =
        await _get(baseUrl, username, password, '/ocs/v2.php/cloud/user');
    final ok = _ensureOk(res, 'Benutzerinfo laden fehlgeschlagen');
    final data = _parseBodyOk(ok);
    try {
      if (data is Map) {
        final ocs = (data['ocs'] as Map?)?.cast<String, dynamic>();
        final d = (ocs?['data'] as Map?)?.cast<String, dynamic>();
        final id = (d?['id'] ?? '').toString();
        final dn = (d?['display-name'] ?? d?['displayName'] ?? '').toString();
        if (id.isNotEmpty) {
          final out =
              UserRef(id: id, displayName: dn.isEmpty ? id : dn, shareType: 0);
          _setCached(_meCache, cacheKey, out, ttlMs: _meTtlMs);
          return out;
        }
      }
    } catch (_) {}
    _setCached(_meCache, cacheKey, null, ttlMs: 5 * 1000);
    return null;
  }

  Future<bool> hasDeckEnabled(
      String baseUrl, String username, String password) async {
    final res = await _get(
        baseUrl, username, password, '/ocs/v2.php/cloud/capabilities');
    final okRes = _ensureOk(res, 'Capabilities laden fehlgeschlagen');
    final data = _parseBodyOk(okRes);
    if (data is Map && data['capabilities'] is Map) {
      final caps = (data['capabilities'] as Map).cast<String, dynamic>();
      return caps.containsKey('deck');
    }
    return false;
  }

  Future<List<Board>> fetchBoards(
      String baseUrl, String username, String password) async {
    // Prefer official Deck REST path, fall back to OCS if needed
    final res =
        await _get(baseUrl, username, password, '/apps/deck/api/v1.0/boards');
    final okRes = _ensureOk(res, 'Boards laden fehlgeschlagen');
    final data = _parseBodyOk(okRes);
    if (data is List) {
      return data.map((e) => Board.fromJson((e as Map).cast())).toList();
    }
    if (data is Map && data['boards'] is List) {
      return (data['boards'] as List)
          .map((e) => Board.fromJson((e as Map).cast()))
          .toList();
    }
    return [];
  }

  // Fetch all boards with details (stacks, cards, labels, members) in a single request.
  // Supports ETag via If-None-Match and returns 304 as notModified=true.
  Future<FetchBoardsDetailsResult> fetchBoardsWithDetailsEtag(
      String baseUrl, String user, String pass,
      {String? ifNoneMatch}) async {
    final cacheKey = 'boards|$baseUrl|$user';
    final inFlight = _boardsDetailsFutures[cacheKey];
    if (inFlight != null) return await inFlight;
    final future = () async {
      Map<String, String> headers = {
        ..._restHeader,
        'authorization': _basicAuth(user, pass)
      };
      if (ifNoneMatch != null && ifNoneMatch.isNotEmpty) {
        headers['If-None-Match'] = ifNoneMatch;
      }
      final baseUri = _buildUri(baseUrl, '/apps/deck/api/v1.0/boards', false);
      final uri = baseUri.replace(
          queryParameters: {...baseUri.queryParameters, 'details': 'true'});
      final res = await _send('GET', uri, headers, priority: true);
      if (res.statusCode == 304) {
        return const FetchBoardsDetailsResult(
            boards: [], etag: null, notModified: true);
      }
      final bool httpOk = _isOk(res);
      dynamic data;
      http.Response effective = res;
      if (httpOk) {
        effective = _ensureOk(res, 'Boards laden (details) fehlgeschlagen');
        data = _parseBodyOk(effective);
      } else if (res.statusCode == 404) {
        try {
          data = jsonDecode(res.body);
        } catch (_) {
          data = null;
        }
        if (data == null) {
          _ensureOk(res, 'Boards laden (details) fehlgeschlagen');
        }
      } else {
        final ok = _ensureOk(res, 'Boards laden (details) fehlgeschlagen');
        data = _parseBodyOk(ok);
        effective = ok;
      }
      List<dynamic> list;
      if (data is List) {
        list = data;
      } else if (data is Map && data['boards'] is List) {
        list = (data['boards'] as List);
      } else {
        if (!httpOk) {
          _ensureOk(res, 'Boards laden (details) fehlgeschlagen');
        }
        list = const [];
      }
      final etag = effective.headers['etag'] ??
          effective.headers['ETag'] ??
          effective.headers['Etag'];
      final boards = list
          .whereType<Map>()
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
      return FetchBoardsDetailsResult(
          boards: boards, etag: etag, notModified: false);
    }();
    _boardsDetailsFutures[cacheKey] = future;
    try {
      return await future;
    } finally {
      _boardsDetailsFutures.remove(cacheKey);
    }
  }

  // Fetch a single board with details=true and optional ETag. Parses into columns with cards.
  Future<FetchStacksResult> fetchBoardDetailsWithEtag(
      String baseUrl, String user, String pass, int boardId,
      {String? ifNoneMatch, bool priority = false}) async {
    final key = 'board|$baseUrl|$user|$boardId';
    final inFlight = _boardDetailsPerIdFutures[key];
    if (inFlight != null) return await inFlight;
    final future = () async {
      Map<String, String> headers = {
        ..._restHeader,
        'authorization': _basicAuth(user, pass)
      };
      if (ifNoneMatch != null && ifNoneMatch.isNotEmpty)
        headers['If-None-Match'] = ifNoneMatch;
      http.Response? res;
      dynamic data;
      for (final withIndex in [false, true]) {
        try {
          final base = _buildUri(
              baseUrl, '/apps/deck/api/v1.0/boards/$boardId', withIndex);
          final uri = base.replace(
              queryParameters: {...base.queryParameters, 'details': 'true'});
          final r = await _send('GET', uri, headers, priority: priority);
          if (r.statusCode == 304) {
            return const FetchStacksResult(
                columns: [], etag: null, notModified: true);
          }
          if (_isOk(r)) {
            res = r;
            data = _parseBodyOk(r);
            break;
          }
        } catch (_) {}
      }
      if (res == null) {
        _ensureOk(res, 'Board laden (details) fehlgeschlagen');
        return const FetchStacksResult(
            columns: [], etag: null, notModified: false);
      }
      final etag =
          res!.headers['etag'] ?? res.headers['ETag'] ?? res.headers['Etag'];
      // Normalize possible envelope shapes
      Map<String, dynamic>? m;
      if (data is Map) {
        m = data.cast<String, dynamic>();
        if (m['ocs'] is Map && (m['ocs'] as Map)['data'] is Map) {
          m = ((m['ocs'] as Map)['data'] as Map).cast<String, dynamic>();
        }
        if (m['board'] is Map) {
          m = (m['board'] as Map).cast<String, dynamic>();
        }
      }
      final stacks = (m?['stacks'] is List) ? (m!['stacks'] as List) : const [];
      final columns = <deck.Column>[];
      for (final s in stacks) {
        if (s is! Map) continue;
        final sm = s.cast<String, dynamic>();
        final sid = (sm['id'] as num?)?.toInt();
        if (sid == null) continue;
        final title = (sm['title'] ?? sm['name'] ?? '').toString();
        final cardsRaw = (sm['cards'] is List)
            ? (sm['cards'] as List)
                .whereType<Map>()
                .map((e) => e.cast<String, dynamic>())
                .toList()
            : const <Map<String, dynamic>>[];
        final cards = cardsRaw.map(CardItem.fromJson).toList();
        columns.add(deck.Column(id: sid, title: title, cards: cards));
      }
      return FetchStacksResult(
          columns: columns, etag: etag, notModified: false);
    }();
    _boardDetailsPerIdFutures[key] = future;
    try {
      return await future;
    } finally {
      _boardDetailsPerIdFutures.remove(key);
    }
  }

  Future<Board?> createBoard(String baseUrl, String user, String pass,
      {required String title, String? color}) async {
    final body =
        jsonEncode({'title': title, if (color != null) 'color': color});
    final headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'authorization': _basicAuth(user, pass)
    };
    http.Response? last;
    for (final withIndex in [false, true]) {
      try {
        last = await _send(
            'POST',
            _buildUri(baseUrl, '/apps/deck/api/v1.0/boards', withIndex),
            headers,
            body: body);
        if (_isOk(last)) {
          final data = _parseBodyOk(last!);
          if (data is Map) return Board.fromJson(data.cast<String, dynamic>());
        }
      } catch (_) {}
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> fetchBoardsRaw(
      String baseUrl, String username, String password) async {
    final res =
        await _get(baseUrl, username, password, '/apps/deck/api/v1.0/boards');
    final okRes = _ensureOk(res, 'Boards laden fehlgeschlagen');
    final data = _parseBodyOk(okRes);
    if (data is List) {
      return data.map((e) => (e as Map).cast<String, dynamic>()).toList();
    }
    if (data is Map && data['boards'] is List) {
      return (data['boards'] as List)
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
    }
    return const [];
  }

  Future<FetchBoardsDetailsResult> fetchBoardsListEtag(
      String baseUrl, String user, String pass,
      {String? ifNoneMatch}) async {
    final cacheKey = 'boards_list|$baseUrl|$user';
    final inFlight = _boardsListFutures[cacheKey];
    if (inFlight != null) return await inFlight;
    final future = () async {
      Map<String, String> headers = {
        ..._restHeader,
        'authorization': _basicAuth(user, pass)
      };
      if (ifNoneMatch != null && ifNoneMatch.isNotEmpty) {
        headers['If-None-Match'] = ifNoneMatch;
      }
      final uri = _buildUri(baseUrl, '/apps/deck/api/v1.0/boards', false);
      final res = await _send('GET', uri, headers, priority: true);
      if (res.statusCode == 304) {
        return const FetchBoardsDetailsResult(
            boards: [], etag: null, notModified: true);
      }
      final bool httpOk = _isOk(res);
      dynamic data;
      http.Response effective = res;
      if (httpOk) {
        effective = _ensureOk(res, 'Boards laden fehlgeschlagen');
        data = _parseBodyOk(effective);
      } else if (res.statusCode == 404) {
        try {
          data = jsonDecode(res.body);
        } catch (_) {
          data = null;
        }
        if (data == null) {
          _ensureOk(res, 'Boards laden fehlgeschlagen');
        }
      } else {
        final ok = _ensureOk(res, 'Boards laden fehlgeschlagen');
        data = _parseBodyOk(ok);
        effective = ok;
      }
      List<dynamic> list;
      if (data is List) {
        list = data;
      } else if (data is Map && data['boards'] is List) {
        list = (data['boards'] as List);
      } else {
        if (!httpOk) {
          _ensureOk(res, 'Boards laden fehlgeschlagen');
        }
        list = const [];
      }
      final etag = effective.headers['etag'] ??
          effective.headers['ETag'] ??
          effective.headers['Etag'];
      final boards = list
          .whereType<Map>()
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
      return FetchBoardsDetailsResult(
          boards: boards, etag: etag, notModified: false);
    }();
    _boardsListFutures[cacheKey] = future;
    try {
      return await future;
    } finally {
      _boardsListFutures.remove(cacheKey);
    }
  }

  Future<Map<String, dynamic>?> fetchBoardDetail(
      String baseUrl, String user, String pass, int boardId) async {
    final cacheKey = 'board|$baseUrl|$user|$boardId';
    final cached = _getCached(_boardDetailCache, cacheKey);
    if (cached != null) return cached;
    // Use REST endpoint only; OCS variants are unreliable on many Deck installations
    final headers = {
      'Accept': 'application/json',
      'authorization': _basicAuth(user, pass),
    };
    for (final withIndex in [false, true]) {
      try {
        final res = await _send(
            'GET',
            _buildUri(
                baseUrl, '/apps/deck/api/v1.0/boards/$boardId', withIndex),
            headers);
        if (_isOk(res)) {
          final data = _parseBodyOk(res);
          if (data is Map) {
            final out = data.cast<String, dynamic>();
            _setCached(_boardDetailCache, cacheKey, out);
            return out;
          }
        }
      } catch (_) {
        // try next variant
      }
    }
    return null;
  }

  Future<Set<String>> fetchBoardMemberUids(
      String baseUrl, String user, String pass, int boardId) async {
    final cacheKey = 'members|$baseUrl|$user|$boardId';
    final cached = _getCached(_boardMemberCache, cacheKey);
    if (cached != null) return cached;
    final out = <String>{};
    final detail = await fetchBoardDetail(baseUrl, user, pass, boardId);
    if (detail == null) return out;
    // owner
    final owner = detail['owner'];
    if (owner is Map && owner['uid'] is String) out.add(owner['uid'] as String);
    // users list
    void addFrom(dynamic v) {
      if (v is List) {
        for (final e in v) {
          if (e is Map) {
            if (e['uid'] is String) out.add(e['uid'] as String);
            final p = e['participant'];
            if (p is Map && p['uid'] is String) out.add(p['uid'] as String);
          }
        }
      }
    }

    addFrom(detail['users']);
    addFrom(detail['acl']);
    // activeSessions (may carry participants)
    addFrom(detail['activeSessions']);
    _setCached(_boardMemberCache, cacheKey, out);
    return out;
  }

  Future<List<deck.Column>> fetchColumns(
    String baseUrl,
    String username,
    String password,
    int boardId, {
    bool lazyCards = true,
    bool priority = false,
    bool bypassCooldown = false,
  }) async {
    final cdKey = '$baseUrl|$username|$boardId';
    if (!bypassCooldown) {
      final last = _stacksCooldown[cdKey];
      if (last != null &&
          DateTime.now().difference(last) < _stacksMinInterval) {
        final memo = _stacksMemo[cdKey];
        if (memo != null) return memo;
      }
    }
    // Coalesce in-flight identical fetches
    final inFlight = _stacksFetchFutures[cdKey];
    if (inFlight != null) return await inFlight;
    http.Response? res;
    dynamic data;
    // Try REST stacks first (with/without index, priority), then OCS v2 and v1
    final future = () async {
      for (final withIndex in [false, true]) {
        try {
          final uri = _buildUri(
              baseUrl, '/apps/deck/api/v1.0/boards/$boardId/stacks', withIndex);
          final r = await _send('GET', uri,
              {..._restHeader, 'authorization': _basicAuth(username, password)},
              priority: priority,
              timeout: bypassCooldown ? const Duration(seconds: 12) : null);
          if (_isOk(r)) {
            res = r;
            data = _parseBodyOk(r);
            break;
          }
        } catch (_) {}
      }
      if (res == null || !_isOk(res!)) {
        for (final ocs in ['/ocs/v2.php', '/ocs/v1.php']) {
          for (final withIndex in [false, true]) {
            try {
              final uri = _buildUri(baseUrl,
                  '$ocs/apps/deck/api/v1.0/boards/$boardId/stacks', withIndex);
              final r = await _send(
                  'GET',
                  uri,
                  {
                    ..._ocsHeader,
                    'authorization': _basicAuth(username, password)
                  },
                  priority: priority,
                  timeout: bypassCooldown ? const Duration(seconds: 12) : null);
              if (_isOk(r)) {
                res = r;
                data = _parseBodyOk(r);
                break;
              }
            } catch (_) {}
          }
          if (res != null && _isOk(res!)) break;
        }
      }
      if (res == null || !_isOk(res!)) {
        _ensureOk(res, 'Spalten laden fehlgeschlagen');
        return const <deck.Column>[];
      }
      final List<deck.Column> columns = [];
      final List<dynamic> rawStacks = data is List
          ? data
          : (data is Map && data['stacks'] is List)
              ? (data['stacks'] as List)
              : const <dynamic>[];
      if (rawStacks.isEmpty) return columns;

      // Build deterministic ordering using explicit order field if present, else input order
      final Map<int, int> orderMap = {};
      for (int idx = 0; idx < rawStacks.length; idx++) {
        final s = rawStacks[idx];
        if (s is! Map) continue;
        final sm = s as Map;
        final sid = sm['id'];
        if (sid is! num) continue;
        final id = sid.toInt();
        final ord =
            (sm['order'] ?? sm['position'] ?? sm['sort'] ?? sm['ordinal']);
        orderMap[id] = ord is num ? ord.toInt() : idx;
      }

      // Prefer inline cards if provided by the stacks response.
      final needFetch = <Map<String, dynamic>>[];
      for (final s in rawStacks) {
        if (s is! Map) continue;
        final stack = s.cast<String, dynamic>();
        final stackId = (stack['id'] as num).toInt();
        final title = (stack['title'] ?? stack['name'] ?? '').toString();
        final inline = stack['cards'];
        if (inline is List) {
          final cards = inline
              .whereType<Map>()
              .map((e) => CardItem.fromJson(e.cast<String, dynamic>()))
              .toList();
          columns.add(deck.Column(id: stackId, title: title, cards: cards));
        } else {
          // Lazy mode: leave empty and fetch on demand later
          if (lazyCards) {
            columns
                .add(deck.Column(id: stackId, title: title, cards: const []));
          } else {
            // Skip obvious done columns to reduce requests when only due dates are needed
            final lt = title.toLowerCase();
            final isDone = lt.contains('done') || lt.contains('erledigt');
            columns
                .add(deck.Column(id: stackId, title: title, cards: const []));
            if (!isDone) {
              needFetch.add({'id': stackId, 'title': title});
            }
          }
        }
      }

      if (!lazyCards) {
        // Try fast board-wide cards listing first to avoid N-per-stack requests
        final boardCards =
            await _fetchBoardCardsRaw(baseUrl, username, password, boardId);
        if (boardCards.isNotEmpty) {
          final byStack = <int, List<CardItem>>{};
          for (final e in boardCards) {
            int? sid;
            final vStackId = e['stackId'];
            if (vStackId is num) sid = vStackId.toInt();
            if (sid == null && e['stack'] is Map && (e['stack']['id'] is num))
              sid = (e['stack']['id'] as num).toInt();
            if (sid == null) continue;
            (byStack[sid] ??= <CardItem>[]).add(CardItem.fromJson(e));
          }
          // Merge cards into existing columns in-place
          for (int i = 0; i < columns.length; i++) {
            final c = columns[i];
            final list = byStack[c.id];
            if (list != null) {
              columns[i] = deck.Column(id: c.id, title: c.title, cards: list);
            }
          }
        } else if (needFetch.isNotEmpty) {
          // Fallback: fetch per stack (bounded by global concurrency limiter)
          final results = await Future.wait(
            needFetch.map((m) => fetchCards(
                baseUrl, username, password, boardId, m['id'] as int)),
          );
          // Merge results into existing columns (replace placeholder empties)
          final mapById = {for (final c in columns) c.id: c};
          for (int i = 0; i < needFetch.length; i++) {
            final sid = needFetch[i]['id'] as int;
            final title = needFetch[i]['title'] as String;
            mapById[sid] =
                deck.Column(id: sid, title: title, cards: results[i]);
          }
          // Rebuild columns preserving order
          final ordered = <deck.Column>[];
          for (final s in rawStacks) {
            if (s is Map && s['id'] is num) {
              final id = (s['id'] as num).toInt();
              final c = mapById[id];
              if (c != null) ordered.add(c);
            }
          }
          columns
            ..clear()
            ..addAll(ordered);
        }
      }

      // Sort by provided order/position; if equal, preserve original stacks order
      final indexMap = <int, int>{
        for (int i = 0; i < rawStacks.length; i++)
          if (rawStacks[i] is Map && (rawStacks[i] as Map)['id'] is num)
            ((rawStacks[i] as Map)['id'] as num).toInt(): i
      };
      columns.sort((a, b) {
        final oa = orderMap[a.id] ?? 0;
        final ob = orderMap[b.id] ?? 0;
        if (oa != ob) return oa.compareTo(ob);
        final ia = indexMap[a.id] ?? 0;
        final ib = indexMap[b.id] ?? 0;
        return ia.compareTo(ib);
      });

      // Memoize + cooldown
      _stacksMemo[cdKey] = columns;
      _stacksCooldown[cdKey] = DateTime.now();
      return columns;
    }();
    _stacksFetchFutures[cdKey] = future;
    try {
      return await future;
    } finally {
      _stacksFetchFutures.remove(cdKey);
    }
  }

  Future<FetchStacksResult> fetchStacksWithEtag(
      String baseUrl, String username, String password, int boardId,
      {String? ifNoneMatch, bool priority = false}) async {
    final cdKey = '$baseUrl|$username|$boardId';
    final lastCd = _stacksCooldown[cdKey];
    if (lastCd != null &&
        DateTime.now().difference(lastCd) < _stacksMinInterval) {
      final memo = _stacksMemo[cdKey];
      if (memo != null) {
        return FetchStacksResult(
            columns: memo, etag: ifNoneMatch, notModified: true);
      }
      return const FetchStacksResult(
          columns: [], etag: null, notModified: true);
    }
    // Coalesce in-flight identical fetches (ignore differing ETags for coalescing simplicity)
    final inFlight = _stacksWithEtagFutures[cdKey];
    if (inFlight != null) return await inFlight;
    _stacksCooldown[cdKey] = DateTime.now();
    http.Response? res;
    dynamic data;
    Map<String, String> restHeaders = {
      ..._restHeader,
      'authorization': _basicAuth(username, password)
    };
    Map<String, String> ocsHeaders = {
      ..._ocsHeader,
      'authorization': _basicAuth(username, password)
    };
    if (ifNoneMatch != null && ifNoneMatch.isNotEmpty) {
      restHeaders['If-None-Match'] = ifNoneMatch;
      ocsHeaders['If-None-Match'] = ifNoneMatch;
    }
    final future = () async {
      for (final withIndex in [false, true]) {
        try {
          final uri = _buildUri(
              baseUrl, '/apps/deck/api/v1.0/boards/$boardId/stacks', withIndex);
          final r = await _send('GET', uri, restHeaders,
              priority: priority, timeout: const Duration(seconds: 12));
          if (r.statusCode == 304) {
            return const FetchStacksResult(
                columns: [], etag: null, notModified: true);
          }
          if (_isOk(r)) {
            res = r;
            data = _parseBodyOk(r);
            break;
          }
        } catch (_) {}
      }
      if (res == null || !_isOk(res!)) {
        for (final ocs in ['/ocs/v2.php', '/ocs/v1.php']) {
          for (final withIndex in [false, true]) {
            try {
              final uri = _buildUri(baseUrl,
                  '$ocs/apps/deck/api/v1.0/boards/$boardId/stacks', withIndex);
              final r = await _send('GET', uri, ocsHeaders,
                  priority: priority, timeout: const Duration(seconds: 12));
              if (r.statusCode == 304) {
                return const FetchStacksResult(
                    columns: [], etag: null, notModified: true);
              }
              if (_isOk(r)) {
                res = r;
                data = _parseBodyOk(r);
                break;
              }
            } catch (_) {}
          }
          if (res != null && _isOk(res!)) break;
        }
      }
      if (res == null || !_isOk(res!)) {
        _ensureOk(res, 'Spalten laden fehlgeschlagen');
        return const FetchStacksResult(
            columns: [], etag: null, notModified: false);
      }
      final r0 = res!;
      final etag =
          r0.headers['etag'] ?? r0.headers['ETag'] ?? r0.headers['Etag'];
      final List<dynamic> rawStacks = data is List
          ? data
          : (data is Map && data['stacks'] is List)
              ? (data['stacks'] as List)
              : const <dynamic>[];
      if (rawStacks.isEmpty) {
        return FetchStacksResult(
            columns: const [], etag: etag, notModified: false);
      }
      final List<deck.Column> columns = [];
      for (final s in rawStacks) {
        if (s is! Map) continue;
        final stack = s.cast<String, dynamic>();
        final stackId = (stack['id'] as num).toInt();
        final title = (stack['title'] ?? stack['name'] ?? '').toString();
        final inline = stack['cards'];
        if (inline is List) {
          final cards = inline
              .whereType<Map>()
              .map((e) => CardItem.fromJson(e.cast<String, dynamic>()))
              .toList();
          columns.add(deck.Column(id: stackId, title: title, cards: cards));
        } else {
          columns.add(deck.Column(id: stackId, title: title, cards: const []));
        }
      }
      // Memoize + cooldown
      _stacksMemo[cdKey] = columns;
      _stacksCooldown[cdKey] = DateTime.now();
      return FetchStacksResult(
          columns: columns, etag: etag, notModified: false);
    }();
    _stacksWithEtagFutures[cdKey] = future;
    try {
      return await future;
    } finally {
      _stacksWithEtagFutures.remove(cdKey);
    }
  }

  Future<deck.Column?> createStack(
      String baseUrl, String user, String pass, int boardId,
      {required String title, int? order}) async {
    // Build body including optional ordering
    final Map<String, dynamic> payload = {
      'title': title,
      if (order != null) 'order': order
    };
    final body = jsonEncode(payload);
    final headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'authorization': _basicAuth(user, pass)
    };
    // Try REST v1.1, then v1.0. Also try OCS path variants on some installations
    final paths = <String>[
      '/apps/deck/api/v1.1/boards/$boardId/stacks',
      '/apps/deck/api/v1.0/boards/$boardId/stacks',
      '/ocs/v2.php/apps/deck/api/v1.1/boards/$boardId/stacks',
      '/ocs/v1.php/apps/deck/api/v1.1/boards/$boardId/stacks',
      '/ocs/v2.php/apps/deck/api/v1.0/boards/$boardId/stacks',
      '/ocs/v1.php/apps/deck/api/v1.0/boards/$boardId/stacks',
    ];
    deck.Column? _parseStackResponse(dynamic data) {
      if (data is Map) {
        Map<String, dynamic>? m = data.cast<String, dynamic>();
        if (m['ocs'] is Map) {
          final d = (m['ocs'] as Map)['data'];
          if (d is Map) m = d.cast<String, dynamic>();
        }
        if (m['stack'] is Map) {
          m = (m['stack'] as Map).cast<String, dynamic>();
        }
        final id = (m['id'] as num?)?.toInt();
        final name = (m['title'] ?? m['name'] ?? title)?.toString();
        if (id != null && name != null) {
          return deck.Column(id: id, title: name, cards: const []);
        }
      }
      return null;
    }

    for (final p in paths) {
      for (final withIndex in [false, true]) {
        try {
          final res = await _send(
              'POST', _buildUri(baseUrl, p, withIndex), headers,
              body: body);
          if (_isOk(res)) {
            final data = _parseBodyOk(res);
            final col = _parseStackResponse(data);
            if (col != null) return col;
          }
        } catch (_) {}
      }
    }
    return null;
  }

  Future<List<CardItem>> fetchCards(String baseUrl, String username,
      String password, int boardId, int stackId,
      {bool priority = false}) async {
    // If a working variant is known for this server, try it fast.
    String cacheKey = baseUrl;
    final negExp = _cardsVariantExpiry[cacheKey];
    if (_cardsVariantCache.containsKey(cacheKey)) {
      final templ = _cardsVariantCache[cacheKey];
      if (templ != null) {
        final path = templ
            .replaceAll('{boardId}', '$boardId')
            .replaceAll('{stackId}', '$stackId');
        final isOcs = path.startsWith('/ocs/');
        final headers = {
          if (isOcs) ..._ocsHeader else ..._restHeader,
          'authorization': _basicAuth(username, password)
        };
        for (final withIndex in [false, true]) {
          try {
            final res = await _send(
                'GET', _buildUri(baseUrl, path, withIndex), headers,
                priority: priority);
            if (_isOk(res) && !_ocsFailure(res)) {
              return _parseCardsList(res.body);
            }
          } catch (_) {}
        }
        // Cached variant failed: clear and probe again
        _cardsVariantCache.remove(cacheKey);
      }
      // If we have a negative cache and it's still valid, fall back to stacks fetch to derive cards
      if (templ == null && negExp != null && negExp.isAfter(DateTime.now())) {
        return await _fallbackCardsViaStacks(
            baseUrl, username, password, boardId, stackId,
            priority: priority);
      }
    }

    // Try robust REST variants first, then older REST path, then OCS v2/v1 variants.
    final variants = <String>[
      '/apps/deck/api/v1.1/boards/{boardId}/stacks/{stackId}/cards',
      '/apps/deck/api/v1.0/boards/{boardId}/stacks/{stackId}/cards',
      // Some servers expose cards list under stacks without board scope
      '/apps/deck/api/v1.0/stacks/{stackId}/cards',
      // OCS variants (some installations only expose OCS for cards list)
      '/ocs/v2.php/apps/deck/api/v1.0/boards/{boardId}/stacks/{stackId}/cards',
      '/ocs/v1.php/apps/deck/api/v1.0/boards/{boardId}/stacks/{stackId}/cards',
    ];
    http.Response? last;
    for (final templ in variants) {
      final path = templ
          .replaceAll('{boardId}', '$boardId')
          .replaceAll('{stackId}', '$stackId');
      final isOcs = path.startsWith('/ocs/');
      final headers = {
        if (isOcs) ..._ocsHeader else ..._restHeader,
        'authorization': _basicAuth(username, password)
      };
      for (final withIndex in [false, true]) {
        try {
          final uri = _buildUri(baseUrl, path, withIndex);
          final res = await _send('GET', uri, headers, priority: priority);
          last = res;
          if (_isOk(res)) {
            _cardsVariantCache[cacheKey] = templ;
            _cardsVariantExpiry.remove(cacheKey);
            return _parseCardsList(res.body);
          }
        } catch (_) {}
      }
    }
    // If all REST endpoints failed, set negative cache briefly and fallback via stacks.
    _cardsVariantCache[cacheKey] = null;
    _cardsVariantExpiry[cacheKey] = DateTime.now().add(_capsTtl);
    return await _fallbackCardsViaStacks(
        baseUrl, username, password, boardId, stackId,
        priority: priority);
  }

  // Strict per-stack cards loader (no variant storm). Returns cards + ETag if present.
  Future<FetchCardsStrictResult> fetchStackCardsStrict(
      String baseUrl, String user, String pass, int boardId, int stackId,
      {String? ifNoneMatch, bool priority = false}) async {
    final headers = {
      ..._restHeader,
      'authorization': _basicAuth(user, pass),
      if (ifNoneMatch != null && ifNoneMatch.isNotEmpty)
        'If-None-Match': ifNoneMatch,
    };
    for (final withIndex in [false, true]) {
      try {
        final uri = _buildUri(
            baseUrl,
            '/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards',
            withIndex);
        final res = await _send('GET', uri, headers, priority: priority);
        if (res.statusCode == 304)
          return const FetchCardsStrictResult(
              cards: [], etag: null, notModified: true);
        if (_isOk(res)) {
          final etag =
              res.headers['etag'] ?? res.headers['ETag'] ?? res.headers['Etag'];
          final list = _extractCardsFromAny(res.body);
          return FetchCardsStrictResult(
              cards: list, etag: etag, notModified: false);
        }
      } catch (_) {}
    }
    // As last resort: treat as not modified to avoid storms
    return const FetchCardsStrictResult(
        cards: [], etag: null, notModified: true);
  }

  List<CardItem> _extractCardsFromAny(String body) {
    final decoded = jsonDecode(body);
    final out = <CardItem>[];
    dynamic data = decoded;
    if (decoded is Map && decoded['ocs'] is Map)
      data = (decoded['ocs'] as Map)['data'];
    if (data is List) {
      for (final c in data.whereType<Map>()) {
        out.add(CardItem.fromJson((c as Map).cast<String, dynamic>()));
      }
    } else if (data is Map && data['cards'] is List) {
      for (final c in (data['cards'] as List).whereType<Map>()) {
        out.add(CardItem.fromJson((c as Map).cast<String, dynamic>()));
      }
    }
    return out;
  }

  // Try board-wide cards listing for Deck; returns raw card maps to allow grouping by stackId
  Future<List<Map<String, dynamic>>> _fetchBoardCardsRaw(
      String baseUrl, String user, String pass, int boardId) async {
    final paths = <String>[
      '/apps/deck/api/v1.1/boards/$boardId/cards',
      '/apps/deck/api/v1.0/boards/$boardId/cards',
      '/ocs/v2.php/apps/deck/api/v1.0/boards/$boardId/cards',
      '/ocs/v1.php/apps/deck/api/v1.0/boards/$boardId/cards',
    ];
    for (final p in paths) {
      final isOcs = p.startsWith('/ocs/');
      final headers = {
        if (isOcs) ..._ocsHeader else ..._restHeader,
        'authorization': _basicAuth(user, pass)
      };
      for (final withIndex in [false, true]) {
        try {
          final res = await _send(
              'GET', _buildUri(baseUrl, p, withIndex), headers,
              priority: false);
          if (_isOk(res)) {
            final data = _parseBodyOk(res);
            if (data is List) {
              return data
                  .whereType<Map>()
                  .map((e) => (e as Map).cast<String, dynamic>())
                  .toList();
            }
            if (data is Map && data['cards'] is List) {
              return (data['cards'] as List)
                  .whereType<Map>()
                  .map((e) => (e as Map).cast<String, dynamic>())
                  .toList();
            }
          }
        } catch (_) {}
      }
    }
    return const <Map<String, dynamic>>[];
  }

  // Board-wide cards listing with ETag support (one request per board when variant known)
  Future<FetchBoardCardsResult> fetchBoardCardsRawWithEtag(
      String baseUrl, String user, String pass, int boardId,
      {String? ifNoneMatch}) async {
    final key = baseUrl; // per-server capability cache
    final negExp = _boardCardsVariantExpiry[key];
    // If we have a known working variant, try it first (one request)
    if (_boardCardsVariantCache.containsKey(key)) {
      final templ = _boardCardsVariantCache[key];
      if (templ != null) {
        final path = templ.replaceAll('{boardId}', '$boardId');
        final isOcs = path.startsWith('/ocs/');
        final headers = {
          if (isOcs) ..._ocsHeader else ..._restHeader,
          'authorization': _basicAuth(user, pass),
          if (ifNoneMatch != null && ifNoneMatch.isNotEmpty)
            'If-None-Match': ifNoneMatch
        };
        for (final withIndex in [false, true]) {
          try {
            final res = await _send(
                'GET', _buildUri(baseUrl, path, withIndex), headers,
                priority: false);
            if (res.statusCode == 304)
              return const FetchBoardCardsResult(
                  cards: [], etag: null, notModified: true);
            if (_isOk(res)) {
              final data = _parseBodyOk(res);
              final etag = res.headers['etag'] ??
                  res.headers['ETag'] ??
                  res.headers['Etag'];
              final list = _extractCardsList(data);
              return FetchBoardCardsResult(
                  cards: list, etag: etag, notModified: false);
            }
          } catch (_) {}
        }
        // Cached variant failed: clear and probe again
        _boardCardsVariantCache.remove(key);
      }
      // Respect negative cache
      if (templ == null && negExp != null && negExp.isAfter(DateTime.now())) {
        return const FetchBoardCardsResult(
            cards: [], etag: null, notModified: true);
      }
    }
    // Probe variants to find a working endpoint (may cost a few tries on first run only)
    final variants = <String>[
      '/apps/deck/api/v1.1/boards/{boardId}/cards',
      '/apps/deck/api/v1.0/boards/{boardId}/cards',
      '/ocs/v2.php/apps/deck/api/v1.0/boards/{boardId}/cards',
      '/ocs/v1.php/apps/deck/api/v1.0/boards/{boardId}/cards',
    ];
    http.Response? last;
    for (final templ in variants) {
      final path = templ.replaceAll('{boardId}', '$boardId');
      final isOcs = path.startsWith('/ocs/');
      final headers = {
        if (isOcs) ..._ocsHeader else ..._restHeader,
        'authorization': _basicAuth(user, pass),
        if (ifNoneMatch != null && ifNoneMatch.isNotEmpty)
          'If-None-Match': ifNoneMatch
      };
      for (final withIndex in [false, true]) {
        try {
          final res = await _send(
              'GET', _buildUri(baseUrl, path, withIndex), headers,
              priority: false);
          last = res;
          if (res.statusCode == 304)
            return const FetchBoardCardsResult(
                cards: [], etag: null, notModified: true);
          if (_isOk(res)) {
            _boardCardsVariantCache[key] = templ;
            _boardCardsVariantExpiry.remove(key);
            final data = _parseBodyOk(res);
            final etag = res.headers['etag'] ??
                res.headers['ETag'] ??
                res.headers['Etag'];
            final list = _extractCardsList(data);
            return FetchBoardCardsResult(
                cards: list, etag: etag, notModified: false);
          }
        } catch (_) {}
      }
    }
    // If nothing worked, set short negative cache and return empty
    _boardCardsVariantCache[key] = null;
    _boardCardsVariantExpiry[key] =
        DateTime.now().add(const Duration(minutes: 10));
    return const FetchBoardCardsResult(
        cards: [], etag: null, notModified: false);
  }

  List<Map<String, dynamic>> _extractCardsList(dynamic data) {
    if (data is List)
      return data
          .whereType<Map>()
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
    if (data is Map && data['cards'] is List)
      return (data['cards'] as List)
          .whereType<Map>()
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
    if (data is Map && data['ocs'] is Map && (data['ocs']['data'] is List)) {
      return (data['ocs']['data'] as List)
          .whereType<Map>()
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
    }
    return const <Map<String, dynamic>>[];
  }

  Future<List<CardItem>> _fallbackCardsViaStacks(String baseUrl,
      String username, String password, int boardId, int stackId,
      {bool priority = false}) async {
    try {
      final cols = await fetchColumns(baseUrl, username, password, boardId,
          lazyCards: false, priority: priority, bypassCooldown: true);
      final idx = cols.indexWhere((c) => c.id == stackId);
      if (idx >= 0) return cols[idx].cards;
    } catch (_) {}
    return const <CardItem>[];
  }

  bool _ocsFailure(http.Response res) {
    try {
      final obj = jsonDecode(res.body);
      if (obj is Map && obj['ocs'] is Map) {
        final meta = (obj['ocs']['meta'] as Map?)?.cast<String, dynamic>();
        if (meta != null) {
          final status = meta['status']?.toString().toLowerCase();
          final code = (meta['statuscode'] as num?)?.toInt();
          if (status != null && status != 'ok') return true;
          if (code != null && code != 200) return true;
        }
      }
    } catch (_) {}
    return false;
  }

  List<CardItem> _parseCardsList(String body) {
    final decoded = jsonDecode(body);
    final out = <CardItem>[];
    dynamic data = decoded;
    if (decoded is Map && decoded['ocs'] is Map) {
      data = (decoded['ocs'] as Map)['data'];
    }
    if (data is List) {
      for (final c in data) {
        out.add(CardItem.fromJson((c as Map).cast<String, dynamic>()));
      }
    } else if (data is Map && data['cards'] is List) {
      for (final c in (data['cards'] as List)) {
        out.add(CardItem.fromJson((c as Map).cast<String, dynamic>()));
      }
    }
    return out;
  }

  // Comments API (OCS v2)
  Future<List<Map<String, dynamic>>> fetchCommentsRaw(
      String baseUrl, String user, String pass, int cardId,
      {int limit = 50, int offset = 0}) async {
    final path = '/ocs/v2.php/apps/deck/api/v1.0/cards/$cardId/comments';
    for (final withIndex in [false, true]) {
      try {
        final uri =
            _buildUri(baseUrl, path, withIndex).replace(queryParameters: {
          ..._buildUri(baseUrl, path, withIndex).queryParameters,
          'limit': '$limit',
          'offset': '$offset',
        });
        final res = await _send('GET', uri,
            {..._ocsHeader, 'authorization': _basicAuth(user, pass)});
        _ensureOk(res, 'Kommentare laden fehlgeschlagen');
        final data = _parseBodyOk(res);
        if (data is List) {
          return data.map((e) => (e as Map).cast<String, dynamic>()).toList();
        }
      } catch (_) {}
    }
    return const [];
  }

  Future<Map<String, dynamic>?> createComment(
      String baseUrl, String user, String pass, int cardId,
      {required String message, int? parentId}) async {
    final headers = {
      ..._ocsHeader,
      'authorization': _basicAuth(user, pass),
      'Content-Type': 'application/json'
    };
    final body = jsonEncode({'message': message, 'parentId': parentId});
    final path = '/ocs/v2.php/apps/deck/api/v1.0/cards/$cardId/comments';
    for (final withIndex in [false, true]) {
      try {
        final res = await _send(
            'POST', _buildUri(baseUrl, path, withIndex), headers,
            body: body);
        _ensureOk(res, 'Kommentar erstellen fehlgeschlagen');
        final data = _parseBodyOk(res);
        if (data is Map) return data.cast<String, dynamic>();
      } catch (_) {}
    }
    return null;
  }

  Future<Map<String, dynamic>?> updateComment(
      String baseUrl, String user, String pass, int cardId, int commentId,
      {required String message}) async {
    final headers = {
      ..._ocsHeader,
      'authorization': _basicAuth(user, pass),
      'Content-Type': 'application/json'
    };
    final body = jsonEncode({'message': message});
    final path =
        '/ocs/v2.php/apps/deck/api/v1.0/cards/$cardId/comments/$commentId';
    for (final withIndex in [false, true]) {
      try {
        final res = await _send(
            'PUT', _buildUri(baseUrl, path, withIndex), headers,
            body: body);
        _ensureOk(res, 'Kommentar aktualisieren fehlgeschlagen');
        final data = _parseBodyOk(res);
        if (data is Map) return data.cast<String, dynamic>();
      } catch (_) {}
    }
    return null;
  }

  Future<bool> deleteComment(String baseUrl, String user, String pass,
      int cardId, int commentId) async {
    final headers = {..._ocsHeader, 'authorization': _basicAuth(user, pass)};
    final path =
        '/ocs/v2.php/apps/deck/api/v1.0/cards/$cardId/comments/$commentId';
    for (final withIndex in [false, true]) {
      try {
        final res =
            await _send('DELETE', _buildUri(baseUrl, path, withIndex), headers);
        if (_isOk(res)) return true;
      } catch (_) {}
    }
    return false;
  }

  // Attachments
  Future<List<Map<String, dynamic>>> fetchAttachments(
      String baseUrl, String user, String pass, int cardId) async {
    final path = '/apps/deck/api/v1.0/cards/$cardId/attachments';
    for (final withIndex in [false, true]) {
      try {
        final headers = {
          'Accept': 'application/json',
          'authorization': _basicAuth(user, pass)
        };
        final res =
            await _send('GET', _buildUri(baseUrl, path, withIndex), headers);
        if (_isOk(res)) {
          final data = _parseBodyOk(res);
          if (data is List) {
            return data.map((e) => (e as Map).cast<String, dynamic>()).toList();
          }
        }
      } catch (_) {}
    }
    return const [];
  }

  Future<bool> deleteAttachment(String baseUrl, String user, String pass,
      int cardId, int attachmentId) async {
    final path = '/apps/deck/api/v1.0/cards/$cardId/attachments/$attachmentId';
    for (final withIndex in [false, true]) {
      try {
        final headers = {
          'Accept': 'application/json',
          'authorization': _basicAuth(user, pass)
        };
        final res =
            await _send('DELETE', _buildUri(baseUrl, path, withIndex), headers);
        if (_isOk(res)) return true;
      } catch (_) {}
    }
    return false;
  }

  // Deck v1.1 attachments (preferred): paths with board/stack/card
  Future<List<Map<String, dynamic>>> fetchCardAttachments(
      String baseUrl, String user, String pass,
      {required int boardId, required int stackId, required int cardId}) async {
    final candidates = <String>[
      '/apps/deck/api/v1.1/boards/$boardId/stacks/$stackId/cards/$cardId/attachments',
      '/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId/attachments',
    ];
    for (final p in candidates) {
      for (final withIndex in [false, true]) {
        try {
          final res = await _send('GET', _buildUri(baseUrl, p, withIndex), {
            'Accept': 'application/json',
            'authorization': _basicAuth(user, pass)
          });
          if (_isOk(res)) {
            final data = _parseBodyOk(res);
            if (data is List)
              return data
                  .map((e) => (e as Map).cast<String, dynamic>())
                  .toList();
          }
        } catch (_) {}
      }
    }
    return const [];
  }

  Future<bool> deleteCardAttachment(String baseUrl, String user, String pass,
      {required int boardId,
      required int stackId,
      required int cardId,
      required int attachmentId,
      String? type}) async {
    // Strict per docs: REST v1.0 board/stack/card/attachment only, with and without index.php
    final path =
        '/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId/attachments/$attachmentId';
    // Some instances require OCS header even on /apps endpoints; include it to avoid 403s
    final headers = {..._ocsHeader, 'authorization': _basicAuth(user, pass)};
    for (final withIndex in [false, true]) {
      try {
        final baseUri = _buildUri(baseUrl, path, withIndex);
        final uri = (type == null || type.isEmpty)
            ? baseUri
            : baseUri.replace(
                queryParameters: {...baseUri.queryParameters, 'type': type});
        final res = await _send('DELETE', uri, headers);
        if (_isOk(res)) return true;
      } catch (_) {}
    }
    return false;
  }

  Future<Map<String, dynamic>?> fetchCardById(
      String baseUrl, String user, String pass, int cardId) async {
    final path = '/apps/deck/api/v1.0/cards/$cardId';
    for (final withIndex in [false, true]) {
      try {
        final res = await _send('GET', _buildUri(baseUrl, path, withIndex), {
          'Accept': 'application/json',
          'authorization': _basicAuth(user, pass),
        });
        if (_isOk(res)) {
          final data = _parseBodyOk(res);
          if (data is Map) return data.cast<String, dynamic>();
        }
      } catch (_) {}
    }
    // As a fallback, try OCS v1
    for (final withIndex in [false, true]) {
      try {
        final res = await _send(
            'GET',
            _buildUri(baseUrl, '/ocs/v1.php/apps/deck/api/v1.0/cards/$cardId',
                withIndex),
            {
              ..._ocsHeader,
              'authorization': _basicAuth(user, pass),
            });
        if (_isOk(res)) {
          final data = _parseBodyOk(res);
          if (data is Map) return data.cast<String, dynamic>();
        }
      } catch (_) {}
    }
    return null;
  }

  Future<int?> resolveCardStackId(
      String baseUrl, String user, String pass, int boardId, int cardId) async {
    final card = await fetchCardById(baseUrl, user, pass, cardId);
    if (card != null) {
      final sid = (card['stackId'] as num?)?.toInt() ??
          ((card['stack'] as Map?)?['id'] as num?)?.toInt();
      if (sid != null) return sid;
    }
    return null;
  }

  Future<bool> deleteCardAttachmentEnsureStack(
      String baseUrl, String user, String pass,
      {required int boardId,
      int? stackId,
      required int cardId,
      required int attachmentId,
      String? type}) async {
    int? sid = stackId;
    sid ??= await resolveCardStackId(baseUrl, user, pass, boardId, cardId);
    if (sid == null) return false;
    return deleteCardAttachment(baseUrl, user, pass,
        boardId: boardId,
        stackId: sid,
        cardId: cardId,
        attachmentId: attachmentId,
        type: type);
  }

  Future<bool> uploadCardAttachment(String baseUrl, String user, String pass,
      {required int boardId,
      required int stackId,
      required int cardId,
      required List<int> bytes,
      required String filename}) async {
    final candidates = <String>[
      '/apps/deck/api/v1.1/boards/$boardId/stacks/$stackId/cards/$cardId/attachments',
      '/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId/attachments',
    ];
    for (final p in candidates) {
      for (final withIndex in [false, true]) {
        try {
          final uri = _buildUri(baseUrl, p, withIndex);
          final req = http.MultipartRequest('POST', uri);
          req.headers['authorization'] = _basicAuth(user, pass);
          req.headers['Accept'] = 'application/json';
          // Try type=file (v1.1). For v1.0, server may accept default.
          req.fields['type'] = 'file';
          req.files.add(
              http.MultipartFile.fromBytes('file', bytes, filename: filename));
          final streamed = await req.send();
          final res = await http.Response.fromStream(streamed);
          if (_isOk(res)) return true;
        } catch (_) {}
      }
    }
    return false;
  }

  Future<http.Response?> fetchAttachmentContent(
      String baseUrl, String user, String pass,
      {required int boardId,
      required int stackId,
      required int cardId,
      required int attachmentId}) async {
    final candidates = <String>[
      '/apps/deck/api/v1.1/boards/$boardId/stacks/$stackId/cards/$cardId/attachments/$attachmentId',
      '/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId/attachments/$attachmentId',
    ];
    for (final p in candidates) {
      for (final withIndex in [false, true]) {
        try {
          final res = await _send('GET', _buildUri(baseUrl, p, withIndex),
              {'authorization': _basicAuth(user, pass)});
          if (_isOk(res)) return res;
        } catch (_) {}
      }
    }
    return null;
  }

  // Download a file via WebDAV using a known remote path under the user's files
  Future<http.Response?> webdavDownload(String baseUrl, String user,
      String pass, String username, String remotePath) async {
    final candidates = <String>[
      '/remote.php/dav/files/$username$remotePath',
    ];
    for (final p in candidates) {
      for (final withIndex in [false, true]) {
        try {
          final res = await _send('GET', _buildUri(baseUrl, p, withIndex),
              {'authorization': _basicAuth(user, pass)});
          if (_isOk(res)) return res;
        } catch (_) {}
      }
    }
    return null;
  }

  Future<bool> uploadFileToWebdav(String baseUrl, String user, String pass,
      String username, String remotePath, List<int> bytes) async {
    final logger = LogService();
    // Normalize remotePath
    String p = remotePath.startsWith('/') ? remotePath : '/$remotePath';
    p = p.replaceAll(RegExp(r'/{2,}'), '/');
    // Ensure parent folder exists recursively
    try {
      final lastSlash = p.lastIndexOf('/');
      final folder = lastSlash <= 0 ? '' : p.substring(0, lastSlash);
      if (folder.isNotEmpty) {
        final parts = folder.split('/').where((e) => e.isNotEmpty).toList();
        String current = '';
        for (final segment in parts) {
          current += '/$segment';
          for (final withIndex in [false, true]) {
            try {
              final uri = _buildUri(baseUrl,
                  '/remote.php/dav/files/$username$current', withIndex);
              final req = http.Request('MKCOL', uri);
              req.headers['authorization'] = _basicAuth(user, pass);
              final t0 = DateTime.now();
              final streamed = await req.send();
              final res = await http.Response.fromStream(streamed);
              final dur = DateTime.now().difference(t0).inMilliseconds;
              logger.add(LogEntry(
                  at: t0,
                  method: 'MKCOL',
                  url: uri.toString(),
                  status: res.statusCode,
                  durationMs: dur,
                  responseSnippet: res.body.length > 200
                      ? res.body.substring(0, 200) + '…'
                      : res.body));
              // 201 created or 405 Method Not Allowed (exists) are fine
              if (res.statusCode == 201 ||
                  res.statusCode == 200 ||
                  res.statusCode == 405) break;
            } catch (e) {
              final dur = 0;
              logger.add(LogEntry(
                  at: DateTime.now(),
                  method: 'MKCOL',
                  url: '/remote.php/dav/files/$username$current',
                  status: null,
                  durationMs: dur,
                  error: e.toString()));
            }
          }
        }
      }
    } catch (e) {
      logger.add(LogEntry(
          at: DateTime.now(),
          method: 'MKCOL',
          url: 'folder-ensure',
          status: null,
          durationMs: 0,
          error: e.toString()));
    }
    try {
      for (final withIndex in [false, true]) {
        final uri =
            _buildUri(baseUrl, '/remote.php/dav/files/$username$p', withIndex);
        final t0 = DateTime.now();
        final res = await http.put(uri,
            headers: {'authorization': _basicAuth(user, pass)}, body: bytes);
        final dur = DateTime.now().difference(t0).inMilliseconds;
        final snippet = (res.body.length > 200)
            ? res.body.substring(0, 200) + '…'
            : res.body;
        logger.add(LogEntry(
            at: t0,
            method: 'PUT',
            url: uri.toString(),
            status: res.statusCode,
            durationMs: dur,
            responseSnippet: snippet));
        if (_isOk(res)) return true;
      }
      return false;
    } catch (e) {
      logger.add(LogEntry(
          at: DateTime.now(),
          method: 'PUT',
          url: '/remote.php/dav/files/$username$p',
          status: null,
          durationMs: 0,
          error: e.toString()));
      return false;
    }
  }

  Future<int?> webdavGetFileId(String baseUrl, String user, String pass,
      String username, String remotePath) async {
    final logger = LogService();
    String p = remotePath.startsWith('/') ? remotePath : '/$remotePath';
    p = p.replaceAll(RegExp(r'/{2,}'), '/');
    try {
      final uri =
          _buildUri(baseUrl, '/remote.php/dav/files/$username$p', false);
      final req = http.Request('PROPFIND', uri);
      req.headers['authorization'] = _basicAuth(user, pass);
      req.headers['Depth'] = '0';
      req.headers['Content-Type'] = 'application/xml; charset=utf-8';
      req.body = '<?xml version="1.0" encoding="UTF-8"?>\n'
          '<d:propfind xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns">'
          '<d:prop><oc:fileid/></d:prop></d:propfind>';
      final t0 = DateTime.now();
      final streamed = await req.send();
      final res = await http.Response.fromStream(streamed);
      final dur = DateTime.now().difference(t0).inMilliseconds;
      logger.add(LogEntry(
          at: t0,
          method: 'PROPFIND',
          url: uri.toString(),
          status: res.statusCode,
          durationMs: dur,
          responseSnippet: res.body.length > 200
              ? res.body.substring(0, 200) + '…'
              : res.body));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final m =
            RegExp(r'<oc:fileid>([^<]+)</oc:fileid>').firstMatch(res.body);
        if (m != null) {
          final idStr = m.group(1);
          final id = int.tryParse(idStr ?? '');
          return id;
        }
      }
    } catch (e) {
      logger.add(LogEntry(
          at: DateTime.now(),
          method: 'PROPFIND',
          url: '/remote.php/dav/files/$username$p',
          status: null,
          durationMs: 0,
          error: e.toString()));
    }
    return null;
  }

  Future<bool> linkAttachment(
      String baseUrl, String user, String pass, int cardId,
      {required String filePath,
      int? fileId,
      int? boardId,
      int? stackId}) async {
    final List<String> candidates = [];
    if (boardId != null && stackId != null) {
      candidates.add(
          '/apps/deck/api/v1.1/boards/$boardId/stacks/$stackId/cards/$cardId/attachments');
      candidates.add(
          '/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId/attachments');
    }
    candidates.add('/apps/deck/api/v1.0/cards/$cardId/attachments');

    Map<String, dynamic> payload;
    if (fileId != null) {
      payload = {'type': 'file', 'fileId': fileId};
    } else {
      payload = {'type': 'file', 'file': filePath};
    }
    final body = jsonEncode(payload);
    for (final p in candidates) {
      for (final withIndex in [false, true]) {
        try {
          final res = await _send(
              'POST',
              _buildUri(baseUrl, p, withIndex),
              {
                'Accept': 'application/json',
                'Content-Type': 'application/json',
                'authorization': _basicAuth(user, pass)
              },
              body: body);
          if (_isOk(res)) return true;
        } catch (_) {}
      }
    }
    return false;
  }

  Future<Map<String, dynamic>?> createCard(String baseUrl, String username,
      String password, int boardId, int columnId, String title,
      {String? description}) async {
    final body = jsonEncode({
      'title': title,
      if (description != null) 'description': description,
    });
    final res = await _post(
      baseUrl,
      username,
      password,
      '/apps/deck/api/v1.0/boards/$boardId/stacks/$columnId/cards',
      body,
      priority: true,
    );
    final ok = _ensureOk(res, 'Karte erstellen fehlgeschlagen');
    final data = _parseBodyOk(ok);
    if (data is Map) return data.cast<String, dynamic>();
    if (data is List && data.isNotEmpty && data.first is Map) {
      return (data.first as Map).cast<String, dynamic>();
    }
    return null;
  }

  Future<bool> deleteCard(String baseUrl, String user, String pass,
      {required int boardId, required int stackId, required int cardId}) async {
    final headers = {
      'Accept': 'application/json',
      'authorization': _basicAuth(user, pass)
    };
    final paths = <String>[
      '/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId',
      '/apps/deck/api/v1.0/cards/$cardId',
      '/ocs/v1.php/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId',
      '/ocs/v1.php/apps/deck/api/v1.0/cards/$cardId',
    ];
    for (final p in paths) {
      try {
        final res =
            await _send('DELETE', _buildUri(baseUrl, p, false), headers);
        if (_isOk(res)) return true;
        final res2 =
            await _send('DELETE', _buildUri(baseUrl, p, true), headers);
        if (_isOk(res2)) return true;
      } catch (_) {}
    }
    return false;
  }

  // Cards: fetch single, update, labels management
  Future<Map<String, dynamic>?> fetchCard(String baseUrl, String user,
      String pass, int boardId, int stackId, int cardId) async {
    // Deck REST card endpoint under board/stack scope
    final res = await _get(baseUrl, user, pass,
        '/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId');
    final ok = _ensureOk(res, 'Karte laden fehlgeschlagen');
    final data = _parseBodyOk(ok);
    if (data is Map) return data.cast<String, dynamic>();
    return null;
  }

  Future<void> updateCard(String baseUrl, String user, String pass, int boardId,
      int stackId, int cardId, Map<String, dynamic> patch) async {
    // Build payload required by Deck (NC31 often requires type+owner+order)
    Map<String, dynamic> payload = {
      'type': 'plain',
      'owner': user,
      'order': 999,
      'boardId': boardId,
      ...patch,
    };
    if (payload.containsKey('duedate')) {
      final v = payload['duedate'];
      if (v is DateTime) {
        payload['duedate'] = v.toUtc().toIso8601String();
      } else if (v is int) {
        // treat as unix seconds
        payload['duedate'] =
            DateTime.fromMillisecondsSinceEpoch(v * 1000, isUtc: true)
                .toIso8601String();
      } else if (v is String) {
        // assume already ISO
      } else if (v == null) {
        payload['duedate'] = null;
      }
    }

    Future<http.Response?> trySend(
        String method, String path, Map<String, dynamic> body) async {
      final bodyJson = jsonEncode(body);
      final isOcs = path.startsWith('/ocs/');
      final headers = {
        if (isOcs) ..._ocsHeader,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'authorization': _basicAuth(user, pass),
      };
      http.Response? res;
      try {
        res = await _send(method, _buildUri(baseUrl, path, false), headers,
            body: bodyJson);
        if (!_isOk(res)) {
          res = await _send(method, _buildUri(baseUrl, path, true), headers,
              body: bodyJson);
        }
      } catch (_) {
        try {
          res = await _send(method, _buildUri(baseUrl, path, true), headers,
              body: bodyJson);
        } catch (_) {
          res = null;
        }
      }
      return res;
    }

    http.Response? res;
    final newStackId =
        payload['stackId'] is num ? (payload['stackId'] as num).toInt() : null;
    // Build prioritized attempts; minimize requests for speed
    final attempts = <Map<String, dynamic>>[];
    if (newStackId != null && newStackId != stackId) {
      // 1) REST new-stack path without stackId in body (matches your server success)
      attempts.add({
        'path':
            '/apps/deck/api/v1.0/boards/$boardId/stacks/$newStackId/cards/$cardId',
        'body': {...payload}..remove('stackId')
      });
      // 2) REST old-stack path with stackId in body
      attempts.add({
        'path':
            '/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId',
        'body': payload,
      });
      // 3) REST card root with stackId in body
      attempts.add({
        'path': '/apps/deck/api/v1.0/cards/$cardId',
        'body': payload,
      });
      // 4) OCS v1 new-stack path without stackId in body
      attempts.add({
        'path':
            '/ocs/v1.php/apps/deck/api/v1.0/boards/$boardId/stacks/$newStackId/cards/$cardId',
        'body': {...payload}..remove('stackId'),
      });
      // 5) OCS v1 old-stack path with stackId
      attempts.add({
        'path':
            '/ocs/v1.php/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId',
        'body': payload,
      });
      // 6) OCS v1 card root with stackId
      attempts.add({
        'path': '/ocs/v1.php/apps/deck/api/v1.0/cards/$cardId',
        'body': payload,
      });
    } else {
      // Not a move: try multiple paths for better compatibility
      attempts.addAll([
        {
          'path':
              '/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId',
          'body': payload,
        },
        {
          'path': '/apps/deck/api/v1.0/cards/$cardId',
          'body': payload,
        },
        {
          'path':
              '/ocs/v1.php/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId',
          'body': payload,
        },
        {
          'path': '/ocs/v1.php/apps/deck/api/v1.0/cards/$cardId',
          'body': payload,
        },
      ]);
    }

    bool accepted = false;
    for (final att in attempts) {
      final baseBody = (att['body'] as Map<String, dynamic>);
      final labelVariants = <Map<String, dynamic>>[baseBody];
      // Expand labels variants
      if (baseBody.containsKey('labels')) {
        final raw = baseBody['labels'];
        List<int> ids = [];
        if (raw is List) {
          ids = raw
              .map((e) => e is int
                  ? e
                  : (e is Map && e['id'] is int ? e['id'] as int : null))
              .whereType<int>()
              .toList();
        }
        final asIds = {...baseBody, 'labels': ids};
        final asObjs = {
          ...baseBody,
          'labels': ids.map((i) => {'id': i}).toList()
        };
        final asObjsWithBoard = {
          ...baseBody,
          'labels': ids.map((i) => {'id': i, 'boardId': boardId}).toList()
        };
        final asAltKey = {...baseBody, 'labelIds': ids}..remove('labels');
        labelVariants.clear();
        labelVariants.addAll([asIds, asObjs, asObjsWithBoard, asAltKey]);
      }
      // Expand assignees variants
      final withAssigneesExpanded = <Map<String, dynamic>>[];
      for (final b in labelVariants) {
        if (b.containsKey('assignedUsers') || b.containsKey('assignees')) {
          final raw = b['assignedUsers'] ?? b['assignees'];
          List<String> uids = [];
          if (raw is List) {
            for (final v in raw) {
              if (v is String)
                uids.add(v);
              else if (v is Map && v['id'] is String)
                uids.add(v['id'] as String);
              else if (v is Map && v['uid'] is String)
                uids.add(v['uid'] as String);
            }
          }
          final asUsers = {...b, 'assignedUsers': uids}..remove('assignees');
          final asMembers = {...b, 'members': uids}
            ..remove('assignedUsers')
            ..remove('assignees');
          withAssigneesExpanded.addAll([asUsers, asMembers]);
        } else {
          withAssigneesExpanded.add(b);
        }
      }
      for (final body in labelVariants) {
        // Try PUT then PATCH
        res = await trySend('PUT', att['path'] as String, body);
        if (!(res != null && _isOk(res))) {
          res = await trySend('PATCH', att['path'] as String, body);
        }
        if (res != null && _isOk(res)) {
          if (newStackId != null && newStackId != stackId) {
            // verify move in response
            try {
              final decoded = jsonDecode(res!.body);
              int? respStack;
              if (decoded is Map) {
                if (decoded['stackId'] is num)
                  respStack = (decoded['stackId'] as num).toInt();
                final stackObj = decoded['stack'] as Map?;
                if (respStack == null &&
                    stackObj != null &&
                    stackObj['id'] is num)
                  respStack = (stackObj['id'] as num).toInt();
              }
              if (respStack == newStackId) {
                accepted = true;
                break;
              }
            } catch (_) {}
          } else {
            accepted = true;
            break;
          }
        }
      }
      if (accepted) break;
    }
    if (!accepted) {
      _ensureOk(res, 'Karte aktualisieren fehlgeschlagen');
      // If OCS payload present, ensure meta.status == ok
      try {
        final decoded = jsonDecode(res!.body);
        if (decoded is Map && decoded['ocs'] is Map) {
          final meta =
              (decoded['ocs']['meta'] as Map?)?.cast<String, dynamic>();
          final status = meta?['status']?.toString().toLowerCase();
          if (status != null && status != 'ok') {
            final code = meta?['statuscode'];
            final msg = meta?['message'] ?? 'OCS-Fehler';
            throw Exception(
                'Karte aktualisieren fehlgeschlagen: OCS $code: $msg');
          }
        }
      } catch (_) {}
      if (newStackId != null && newStackId != stackId) {
        throw Exception(
            'Karte verschieben fehlgeschlagen (keine Variante akzeptiert)');
      }
    }
  }

  // Robust reorder within same stack: try dedicated order endpoint first, then generic update with order field.
  Future<void> reorderCard(String baseUrl, String user, String pass,
      int boardId, int stackId, int cardId, int newIndex,
      {CardItem? local}) async {
    final headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'authorization': _basicAuth(user, pass),
    };
    http.Response? res;
    CardItem? snapshot = local;
    if (snapshot == null || snapshot.title.trim().isEmpty) {
      try {
        final fetched =
            await fetchCard(baseUrl, user, pass, boardId, stackId, cardId);
        if (fetched != null) {
          snapshot = CardItem.fromJson(fetched);
        }
      } catch (_) {}
    }
    // Try both 0-based and 1-based order values
    for (final ord in <int>[newIndex + 1, newIndex]) {
      final body = jsonEncode({'order': ord});
      bool ok = false;
      for (final withIndex in [false, true]) {
        try {
          final uri = _buildUri(
              baseUrl,
              '/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId/order',
              withIndex);
          res = await _send('POST', uri, headers, body: body);
          if (_isOk(res)) {
            ok = true;
            break;
          }
        } catch (_) {}
        try {
          final uri = _buildUri(
              baseUrl,
              '/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId/order',
              withIndex);
          res = await _send('PUT', uri, headers, body: body);
          if (_isOk(res)) {
            ok = true;
            break;
          }
        } catch (_) {}
      }
      if (ok) return;
      try {
        final fallbackPatch = <String, dynamic>{
          'order': ord,
          'stackId': stackId,
          'position': newIndex,
        };
        if (snapshot != null) {
          final card = snapshot!;
          fallbackPatch['title'] = card.title;
          if (card.description != null) {
            fallbackPatch['description'] = card.description;
          }
          if (card.due != null) {
            fallbackPatch['duedate'] = card.due!.toUtc().toIso8601String();
          }
          if (card.labels.isNotEmpty) {
            fallbackPatch['labels'] = card.labels.map((l) => l.id).toList();
          }
          if (card.assignees.isNotEmpty) {
            fallbackPatch['assignedUsers'] = card.assignees
                .map((u) => u.id)
                .where((id) => id.isNotEmpty)
                .toList();
          }
        }
        await updateCard(
            baseUrl, user, pass, boardId, stackId, cardId, fallbackPatch);
        return;
      } catch (_) {}
      for (final withIndex in [false, true]) {
        try {
          final uri = _buildUri(
              baseUrl, '/apps/deck/api/v1.0/cards/$cardId', withIndex);
          final directPayload = <String, dynamic>{
            'order': ord,
            'stackId': stackId,
            'position': newIndex,
          };
          if (snapshot != null) {
            final card = snapshot!;
            directPayload['title'] = card.title;
            if (card.description != null) {
              directPayload['description'] = card.description;
            }
            if (card.due != null) {
              directPayload['duedate'] = card.due!.toUtc().toIso8601String();
            }
            if (card.labels.isNotEmpty) {
              directPayload['labels'] = card.labels.map((l) => l.id).toList();
            }
            if (card.assignees.isNotEmpty) {
              directPayload['assignedUsers'] = card.assignees
                  .map((u) => u.id)
                  .where((id) => id.isNotEmpty)
                  .toList();
            }
          }
          res =
              await _send('PUT', uri, headers, body: jsonEncode(directPayload));
          if (_isOk(res)) return;
        } catch (_) {}
      }
    }
    _ensureOk(res, 'Kartenreihenfolge aktualisieren fehlgeschlagen');
  }

  // Reorder preserving existing fields: try /order endpoint; else PATCH with existing fields to avoid clearing due/labels.
  Future<void> reorderCardSafe(String baseUrl, String user, String pass,
      int boardId, int stackId, int cardId, int newIndex,
      {CardItem? local}) async {
    // 1) Try dedicated order endpoint first
    try {
      await reorderCard(baseUrl, user, pass, boardId, stackId, cardId, newIndex,
          local: local);
      return;
    } catch (_) {/* fall through */}
    // 2) PATCH minimal payload including existing fields (do not clear due/labels when null)
    final payload = <String, dynamic>{
      'order': newIndex,
      'position': newIndex,
      'stackId': stackId,
      if (local != null) 'title': local.title,
      if (local != null && local.description != null)
        'description': local.description,
      if (local != null && local.due != null)
        'duedate': local.due!.toUtc().toIso8601String(),
      if (local != null && local.labels.isNotEmpty)
        'labels': local.labels.map((l) => l.id).toList(),
      if (local != null && local.assignees.isNotEmpty)
        'assignedUsers': local.assignees.map((u) => u.id).toList(),
    };
    final bodyJson = jsonEncode(payload);
    final headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'authorization': _basicAuth(user, pass),
    };
    http.Response? res;
    for (final withIndex in [false, true]) {
      try {
        final uri = _buildUri(
            baseUrl,
            '/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId',
            withIndex);
        res = await _send('PATCH', uri, headers, body: bodyJson);
        if (_isOk(res)) return;
      } catch (_) {}
    }
    _ensureOk(res, 'Kartenreihenfolge aktualisieren fehlgeschlagen (PATCH)');
  }

  // Minimalvariante: genau ein Pfad und höchstens PUT dann PATCH als Fallback.
  // Vermeidet die vielen Kompatibilitäts-Versuche, um Request-Stürme zu verhindern.
  Future<void> updateCardSimple(String baseUrl, String user, String pass,
      int boardId, int stackId, int cardId, Map<String, dynamic> patch) async {
    Map<String, dynamic> payload = {
      'type': 'plain',
      'owner': user,
      'order': 999,
      'boardId': boardId,
      ...patch,
    };
    if (payload.containsKey('duedate')) {
      final v = payload['duedate'];
      if (v is DateTime) {
        payload['duedate'] = v.toUtc().toIso8601String();
      } else if (v is int) {
        payload['duedate'] =
            DateTime.fromMillisecondsSinceEpoch(v * 1000, isUtc: true)
                .toIso8601String();
      }
    }
    final path =
        '/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId';
    final bodyJson = jsonEncode(payload);
    final headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'authorization': _basicAuth(user, pass),
    };
    http.Response res;
    try {
      res = await _send('PUT', _buildUri(baseUrl, path, false), headers,
          body: bodyJson);
      if (!_isOk(res)) {
        res = await _send('PUT', _buildUri(baseUrl, path, true), headers,
            body: bodyJson);
      }
    } catch (_) {
      // Fallback nur einmal mit PATCH
      res = await _send('PATCH', _buildUri(baseUrl, path, true), headers,
          body: bodyJson);
    }
    _ensureOk(res, 'Karte aktualisieren fehlgeschlagen');
  }

  Future<List<Map<String, dynamic>>> fetchBoardLabels(
      String baseUrl, String user, String pass, int boardId) async {
    http.Response? res = await _get(
        baseUrl, user, pass, '/apps/deck/api/v1.0/boards/$boardId/labels');
    if (res == null || res.statusCode == 405 || res.statusCode == 404) {
      // Try OCS variants
      res = await _get(baseUrl, user, pass,
          '/ocs/v2.php/apps/deck/api/v1.0/boards/$boardId/labels');
      if (res == null || res.statusCode == 405 || res.statusCode == 404) {
        res = await _get(baseUrl, user, pass,
            '/ocs/v1.php/apps/deck/api/v1.0/boards/$boardId/labels');
      }
    }
    final ok = _ensureOk(res, 'Labels laden fehlgeschlagen');
    final data = _parseBodyOk(ok);
    if (data is List) {
      return data.map((e) => (e as Map).cast<String, dynamic>()).toList();
    }
    return const [];
  }

  Future<Map<String, dynamic>> createBoardLabel(
      String baseUrl, String user, String pass, int boardId,
      {required String title, required String color}) async {
    String cleanColor = color.trim();
    if (cleanColor.startsWith('#')) cleanColor = cleanColor.substring(1);
    final body = jsonEncode({'title': title, 'color': cleanColor});
    http.Response? res = await _post(baseUrl, user, pass,
        '/apps/deck/api/v1.0/boards/$boardId/labels', body);
    if (res == null || res.statusCode < 200 || res.statusCode >= 300) {
      res = await _post(baseUrl, user, pass,
          '/ocs/v1.php/apps/deck/api/v1.0/boards/$boardId/labels', body);
    }
    final ok = _ensureOk(res, 'Label erstellen fehlgeschlagen');
    final data = _parseBodyOk(ok);
    if (data is Map) return data.cast<String, dynamic>();
    return {'id': null, 'title': title, 'color': cleanColor};
  }

  Future<Map<String, dynamic>> updateBoardLabel(
      String baseUrl, String user, String pass, int boardId, int labelId,
      {String? title, String? color}) async {
    final payload = <String, dynamic>{
      if (title != null) 'title': title,
      if (color != null)
        'color': color.startsWith('#') ? color.substring(1) : color,
    };
    final body = jsonEncode(payload);
    Future<http.Response?> tryPut(String path) async {
      final isOcs = path.startsWith('/ocs/');
      final headers = {
        if (isOcs) ..._ocsHeader,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'authorization': _basicAuth(user, pass),
      };
      http.Response? res;
      try {
        res = await _send('PUT', _buildUri(baseUrl, path, false), headers,
            body: body);
        if (!_isOk(res))
          res = await _send('PUT', _buildUri(baseUrl, path, true), headers,
              body: body);
      } catch (_) {}
      return res;
    }

    http.Response? res =
        await tryPut('/apps/deck/api/v1.0/boards/$boardId/labels/$labelId');
    res ??= await tryPut(
        '/ocs/v1.php/apps/deck/api/v1.0/boards/$boardId/labels/$labelId');
    final ok = _ensureOk(res, 'Label aktualisieren fehlgeschlagen');
    final data = _parseBodyOk(ok);
    if (data is Map) return data.cast<String, dynamic>();
    return {'id': labelId, 'title': title, 'color': color};
  }

  Future<void> deleteBoardLabel(String baseUrl, String user, String pass,
      int boardId, int labelId) async {
    final headersRest = {
      'Accept': 'application/json',
      'authorization': _basicAuth(user, pass)
    };
    http.Response? res;
    try {
      res = await http.delete(
          _buildUri(baseUrl,
              '/apps/deck/api/v1.0/boards/$boardId/labels/$labelId', false),
          headers: headersRest);
      if (!_isOk(res))
        res = await http.delete(
            _buildUri(baseUrl,
                '/apps/deck/api/v1.0/boards/$boardId/labels/$labelId', true),
            headers: headersRest);
    } catch (_) {}
    if (res == null || !_isOk(res)) {
      final headersOcs = {
        ..._ocsHeader,
        'authorization': _basicAuth(user, pass)
      };
      try {
        res = await http.delete(
            _buildUri(
                baseUrl,
                '/ocs/v1.php/apps/deck/api/v1.0/boards/$boardId/labels/$labelId',
                false),
            headers: headersOcs);
        if (!_isOk(res))
          res = await http.delete(
              _buildUri(
                  baseUrl,
                  '/ocs/v1.php/apps/deck/api/v1.0/boards/$boardId/labels/$labelId',
                  true),
              headers: headersOcs);
      } catch (_) {}
    }
    _ensureOk(res, 'Label löschen fehlgeschlagen');
  }

  Future<void> addLabelToCard(
      String baseUrl, String user, String pass, int cardId, int labelId,
      {int? boardId, int? stackId}) async {
    // Prefer API v1.1 assign endpoint when boardId/stackId known
    if (boardId != null && stackId != null) {
      final assignPaths = <String>[
        '/apps/deck/api/v1.1/boards/$boardId/stacks/$stackId/cards/$cardId/assignLabel',
        '/ocs/v1.php/apps/deck/api/v1.1/boards/$boardId/stacks/$stackId/cards/$cardId/assignLabel',
      ];
      final body = jsonEncode({'labelId': labelId});
      for (final p in assignPaths) {
        final isOcs = p.startsWith('/ocs/');
        final headers = {
          if (isOcs) ..._ocsHeader,
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'authorization': _basicAuth(user, pass),
        };
        try {
          var res = await _send('PUT', _buildUri(baseUrl, p, false), headers,
              body: body);
          if (_isOk(res)) {
            _parseBodyOk(res);
            return;
          }
          res = await _send('PUT', _buildUri(baseUrl, p, true), headers,
              body: body);
          if (_isOk(res)) {
            _parseBodyOk(res);
            return;
          }
        } catch (_) {}
      }
    }
    // Try multiple payload keys and REST/OCS variants, including path-with-id forms
    final payloads = [
      jsonEncode({'labelId': labelId}),
      jsonEncode({'label': labelId}),
    ];
    final postPaths = <String>[
      if (boardId != null && stackId != null)
        '/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId/labels',
      if (boardId != null)
        '/apps/deck/api/v1.0/boards/$boardId/cards/$cardId/labels',
      '/apps/deck/api/v1.0/cards/$cardId/labels',
      if (boardId != null && stackId != null)
        '/ocs/v1.php/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId/labels',
      if (boardId != null)
        '/ocs/v1.php/apps/deck/api/v1.0/boards/$boardId/cards/$cardId/labels',
      '/ocs/v1.php/apps/deck/api/v1.0/cards/$cardId/labels',
      '/ocs/v2.php/apps/deck/api/v1.0/cards/$cardId/labels',
    ];
    http.Response? last;
    // Body-based variants
    for (final p in postPaths) {
      for (final b in payloads) {
        final isOcs = p.startsWith('/ocs/');
        final headers = {
          if (isOcs) ..._ocsHeader,
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'authorization': _basicAuth(user, pass),
        };
        try {
          last = await _send('POST', _buildUri(baseUrl, p, false), headers,
              body: b);
          if (_isOk(last)) {
            try {
              _parseBodyOk(last);
              return;
            } catch (_) {}
          }
          last = await _send('POST', _buildUri(baseUrl, p, true), headers,
              body: b);
          if (_isOk(last)) {
            try {
              _parseBodyOk(last);
              return;
            } catch (_) {}
          }
        } catch (_) {}
      }
    }
    // Path-based variants (no body)
    final pathIdVariants = <String>[
      if (boardId != null && stackId != null)
        '/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId/labels/$labelId',
      if (boardId != null)
        '/apps/deck/api/v1.0/boards/$boardId/cards/$cardId/labels/$labelId',
      '/apps/deck/api/v1.0/cards/$cardId/labels/$labelId',
      if (boardId != null && stackId != null)
        '/ocs/v1.php/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId/labels/$labelId',
      if (boardId != null)
        '/ocs/v1.php/apps/deck/api/v1.0/boards/$boardId/cards/$cardId/labels/$labelId',
      '/ocs/v1.php/apps/deck/api/v1.0/cards/$cardId/labels/$labelId',
      '/ocs/v2.php/apps/deck/api/v1.0/cards/$cardId/labels/$labelId',
    ];
    for (final p in pathIdVariants) {
      final isOcs = p.startsWith('/ocs/');
      final headers = {
        if (isOcs) ..._ocsHeader,
        'Accept': 'application/json',
        'authorization': _basicAuth(user, pass),
      };
      try {
        last = await _send('PUT', _buildUri(baseUrl, p, false), headers);
        if (_isOk(last)) {
          try {
            _parseBodyOk(last);
            return;
          } catch (_) {}
        }
        last = await _send('POST', _buildUri(baseUrl, p, false), headers);
        if (_isOk(last)) {
          try {
            _parseBodyOk(last);
            return;
          } catch (_) {}
        }
        last = await _send('PUT', _buildUri(baseUrl, p, true), headers);
        if (_isOk(last)) {
          try {
            _parseBodyOk(last);
            return;
          } catch (_) {}
        }
        last = await _send('POST', _buildUri(baseUrl, p, true), headers);
        if (_isOk(last)) {
          try {
            _parseBodyOk(last);
            return;
          } catch (_) {}
        }
      } catch (_) {}
    }
    _ensureOk(last, 'Label hinzufügen fehlgeschlagen');
  }

  Future<void> removeLabelFromCard(
      String baseUrl, String user, String pass, int cardId, int labelId,
      {int? boardId, int? stackId}) async {
    // Prefer API v1.1 remove endpoint when boardId/stackId known
    if (boardId != null && stackId != null) {
      final removePaths = <String>[
        '/apps/deck/api/v1.1/boards/$boardId/stacks/$stackId/cards/$cardId/removeLabel',
        '/ocs/v1.php/apps/deck/api/v1.1/boards/$boardId/stacks/$stackId/cards/$cardId/removeLabel',
      ];
      final body = jsonEncode({'labelId': labelId});
      for (final p in removePaths) {
        final isOcs = p.startsWith('/ocs/');
        final headers = {
          if (isOcs) ..._ocsHeader,
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'authorization': _basicAuth(user, pass),
        };
        try {
          var res = await _send('PUT', _buildUri(baseUrl, p, false), headers,
              body: body);
          if (_isOk(res)) {
            _parseBodyOk(res);
            return;
          }
          res = await _send('PUT', _buildUri(baseUrl, p, true), headers,
              body: body);
          if (_isOk(res)) {
            _parseBodyOk(res);
            return;
          }
        } catch (_) {}
      }
    }
    // DELETE variants: REST and OCS v1/v2
    final paths = <String>[
      if (boardId != null && stackId != null)
        '/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId/labels/$labelId',
      if (boardId != null)
        '/apps/deck/api/v1.0/boards/$boardId/cards/$cardId/labels/$labelId',
      '/apps/deck/api/v1.0/cards/$cardId/labels/$labelId',
      if (boardId != null && stackId != null)
        '/ocs/v1.php/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId/labels/$labelId',
      if (boardId != null)
        '/ocs/v1.php/apps/deck/api/v1.0/boards/$boardId/cards/$cardId/labels/$labelId',
      '/ocs/v1.php/apps/deck/api/v1.0/cards/$cardId/labels/$labelId',
      '/ocs/v2.php/apps/deck/api/v1.0/cards/$cardId/labels/$labelId',
    ];
    http.Response? res;
    for (final p in paths) {
      final isOcs = p.startsWith('/ocs/');
      final headers = {
        if (isOcs) ..._ocsHeader,
        'Accept': 'application/json',
        'authorization': _basicAuth(user, pass),
      };
      try {
        res = await http.delete(_buildUri(baseUrl, p, false), headers: headers);
        if (_isOk(res)) {
          try {
            _parseBodyOk(res!);
            return;
          } catch (_) {}
        }
        res = await http.delete(_buildUri(baseUrl, p, true), headers: headers);
        if (_isOk(res)) {
          try {
            _parseBodyOk(res!);
            return;
          } catch (_) {}
        }
      } catch (_) {}
    }
    _ensureOk(res, 'Label entfernen fehlgeschlagen');
  }

  // Move card to another stack (robust across NC variants)
  Future<void> moveCard(
    String baseUrl,
    String user,
    String pass, {
    required int boardId,
    required int fromStackId,
    required int toStackId,
    required int cardId,
    int? order,
  }) async {
    final payload = jsonEncode({
      'stackId': toStackId,
      if (order != null) 'order': order,
    });
    final candidates = <Map<String, String>>[
      // Deck REST: move under old stack path
      {
        'method': 'POST',
        'path':
            '/apps/deck/api/v1.0/boards/$boardId/stacks/$fromStackId/cards/$cardId/move'
      },
      {
        'method': 'PUT',
        'path':
            '/apps/deck/api/v1.0/boards/$boardId/stacks/$fromStackId/cards/$cardId/move'
      },
      // Deck REST: card stack endpoint
      {'method': 'POST', 'path': '/apps/deck/api/v1.0/cards/$cardId/stack'},
      {'method': 'PUT', 'path': '/apps/deck/api/v1.0/cards/$cardId/stack'},
      // OCS v1 variants
      {
        'method': 'POST',
        'path':
            '/ocs/v1.php/apps/deck/api/v1.0/boards/$boardId/stacks/$fromStackId/cards/$cardId/move'
      },
      {
        'method': 'PUT',
        'path':
            '/ocs/v1.php/apps/deck/api/v1.0/boards/$boardId/stacks/$fromStackId/cards/$cardId/move'
      },
      {
        'method': 'POST',
        'path': '/ocs/v1.php/apps/deck/api/v1.0/cards/$cardId/stack'
      },
      {
        'method': 'PUT',
        'path': '/ocs/v1.php/apps/deck/api/v1.0/cards/$cardId/stack'
      },
    ];

    http.Response? last;
    var success = false;
    for (final c in candidates) {
      final isOcs = c['path']!.startsWith('/ocs/');
      final headers = {
        if (isOcs) ..._ocsHeader,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'authorization': _basicAuth(user, pass),
      };
      try {
        last = await _send(
            c['method']!, _buildUri(baseUrl, c['path']!, false), headers,
            body: payload);
        if (_isOk(last)) {
          // Validate OCS meta if present
          try {
            _parseBodyOk(last);
            success = true;
            break;
          } catch (_) {}
        }
        last = await _send(
            c['method']!, _buildUri(baseUrl, c['path']!, true), headers,
            body: payload);
        if (_isOk(last)) {
          try {
            _parseBodyOk(last);
            success = true;
            break;
          } catch (_) {}
        }
      } catch (_) {}
      if (success) break;
    }
    if (!success) {
      if (last == null || !_isOk(last)) {
        _ensureOk(last, 'Karte verschieben fehlgeschlagen');
      }
      throw Exception('Karte verschieben fehlgeschlagen (OCS/meta failure)');
    }
  }

  // Card assignees (robust: try multiple endpoint variants)
  Future<void> addAssigneeToCard(String baseUrl, String user, String pass,
      int cardId, String userId) async {
    final payloads = [
      jsonEncode({'userId': userId}),
      jsonEncode({'user': userId}),
      jsonEncode({'uid': userId}),
    ];
    final paths = [
      '/apps/deck/api/v1.0/cards/$cardId/assignments',
      '/apps/deck/api/v1.0/cards/$cardId/members',
      '/ocs/v1.php/apps/deck/api/v1.0/cards/$cardId/assignments',
      '/ocs/v1.php/apps/deck/api/v1.0/cards/$cardId/members',
    ];
    http.Response? last;
    for (final p in paths) {
      for (final body in payloads) {
        last = await _post(baseUrl, user, pass, p, body);
        if (last != null && _isOk(last)) return;
      }
    }
    _ensureOk(last, 'Zuweisung hinzufügen fehlgeschlagen');
  }

  Future<void> removeAssigneeFromCard(String baseUrl, String user, String pass,
      int cardId, String userId) async {
    final headersRest = {
      'Accept': 'application/json',
      'authorization': _basicAuth(user, pass)
    };
    final headersOcs = {..._ocsHeader, 'authorization': _basicAuth(user, pass)};
    final paths = [
      '/apps/deck/api/v1.0/cards/$cardId/assignments/$userId',
      '/apps/deck/api/v1.0/cards/$cardId/members/$userId',
      '/ocs/v1.php/apps/deck/api/v1.0/cards/$cardId/assignments/$userId',
      '/ocs/v1.php/apps/deck/api/v1.0/cards/$cardId/members/$userId',
    ];
    http.Response? last;
    for (final p in paths) {
      try {
        final isOcs = p.startsWith('/ocs/');
        final headers = isOcs ? headersOcs : headersRest;
        last =
            await http.delete(_buildUri(baseUrl, p, false), headers: headers);
        if (_isOk(last)) return;
        last = await http.delete(_buildUri(baseUrl, p, true), headers: headers);
        if (_isOk(last)) return;
      } catch (_) {}
    }
    _ensureOk(last, 'Zuweisung entfernen fehlgeschlagen');
  }

  // v1.1 Assign/Unassign user with board/stack context
  Future<void> assignUserToCard(
    String baseUrl,
    String user,
    String pass, {
    required int boardId,
    required int stackId,
    required int cardId,
    required String userId,
  }) async {
    final paths = <String>[
      '/apps/deck/api/v1.1/boards/$boardId/stacks/$stackId/cards/$cardId/assignUser',
      '/ocs/v1.php/apps/deck/api/v1.1/boards/$boardId/stacks/$stackId/cards/$cardId/assignUser',
    ];
    final payloads = [
      jsonEncode({'userId': userId}),
      jsonEncode({'user': userId}),
      jsonEncode({'uid': userId}),
    ];
    http.Response? last;
    for (final p in paths) {
      final isOcs = p.startsWith('/ocs/');
      final headers = {
        if (isOcs) ..._ocsHeader,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'authorization': _basicAuth(user, pass),
      };
      for (final method in ['PUT', 'POST']) {
        for (final body in payloads) {
          try {
            last = await _send(method, _buildUri(baseUrl, p, false), headers,
                body: body);
            if (_isOk(last)) {
              _parseBodyOk(last!);
              return;
            }
            last = await _send(method, _buildUri(baseUrl, p, true), headers,
                body: body);
            if (_isOk(last)) {
              _parseBodyOk(last!);
              return;
            }
          } catch (_) {}
        }
      }
    }
    _ensureOk(last, 'Benutzer zuweisen fehlgeschlagen');
  }

  Future<void> unassignUserFromCard(
    String baseUrl,
    String user,
    String pass, {
    required int boardId,
    required int stackId,
    required int cardId,
    required String userId,
  }) async {
    final paths = <String>[
      '/apps/deck/api/v1.1/boards/$boardId/stacks/$stackId/cards/$cardId/unassignUser',
      '/ocs/v1.php/apps/deck/api/v1.1/boards/$boardId/stacks/$stackId/cards/$cardId/unassignUser',
    ];
    final payloads = [
      jsonEncode({'userId': userId}),
      jsonEncode({'user': userId}),
      jsonEncode({'uid': userId}),
    ];
    http.Response? last;
    for (final p in paths) {
      final isOcs = p.startsWith('/ocs/');
      final headers = {
        if (isOcs) ..._ocsHeader,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'authorization': _basicAuth(user, pass),
      };
      for (final method in ['PUT', 'POST']) {
        for (final body in payloads) {
          try {
            last = await _send(method, _buildUri(baseUrl, p, false), headers,
                body: body);
            if (_isOk(last)) {
              _parseBodyOk(last!);
              return;
            }
            last = await _send(method, _buildUri(baseUrl, p, true), headers,
                body: body);
            if (_isOk(last)) {
              _parseBodyOk(last!);
              return;
            }
          } catch (_) {}
        }
      }
    }
    _ensureOk(last, 'Benutzer entfernen fehlgeschlagen');
  }

  // Board shares
  Future<List<Map<String, dynamic>>> fetchBoardShares(
      String baseUrl, String user, String pass, int boardId) async {
    final res = await _get(
        baseUrl, user, pass, '/apps/deck/api/v1.0/boards/$boardId/shares');
    final ok = _ensureOk(res, 'Board-Shares laden fehlgeschlagen');
    final data = _parseBodyOk(ok);
    if (data is List) {
      return data.map((e) => (e as Map).cast<String, dynamic>()).toList();
    }
    return const [];
  }

  Future<void> addBoardShare(
      String baseUrl, String user, String pass, int boardId,
      {required int shareType,
      required String shareWith,
      int? permissions}) async {
    final body = jsonEncode({
      'shareType': shareType,
      'shareWith': shareWith,
      if (permissions != null) 'permissions': permissions,
    });
    final res = await _post(baseUrl, user, pass,
        '/apps/deck/api/v1.0/boards/$boardId/shares', body);
    _ensureOk(res, 'Board teilen fehlgeschlagen');
  }

  Future<void> removeBoardShare(String baseUrl, String user, String pass,
      int boardId, int shareId) async {
    final headers = {
      'Accept': 'application/json',
      'authorization': _basicAuth(user, pass)
    };
    http.Response? res;
    try {
      res = await http.delete(
          _buildUri(baseUrl,
              '/apps/deck/api/v1.0/boards/$boardId/shares/$shareId', false),
          headers: headers);
      if (!_isOk(res)) {
        res = await http.delete(
            _buildUri(baseUrl,
                '/apps/deck/api/v1.0/boards/$boardId/shares/$shareId', true),
            headers: headers);
      }
    } catch (_) {}
    _ensureOk(res, 'Board-Freigabe entfernen fehlgeschlagen');
  }

  // Sharees search (users/groups) via OCS sharees API
  Future<List<UserRef>> searchSharees(
      String baseUrl, String user, String pass, String query,
      {int perPage = 20}) async {
    final normQ = query.trim();
    final cacheKey = 'sharees|$baseUrl|$user|$perPage|$normQ';
    final cached = _getCached(_shareesCache, cacheKey);
    if (cached != null) return cached;
    final path = '/ocs/v2.php/apps/files_sharing/api/v1/sharees';
    // Some servers require itemType and return 400 otherwise; avoid empty value
    final itemTypes = ['deck', 'deck-card', 'file'];
    http.Response? lastRes;
    Map<String, dynamic>? data;
    // Prefer lookup=false (fewer results but faster), fallback to lookup=true only if empty
    for (final it in itemTypes) {
      Map<String, dynamic>? merged;
      Future<Map<String, dynamic>?> run(String lookup) async {
        final base = _buildUri(baseUrl, path, false);
        final uri = base.replace(queryParameters: {
          ...base.queryParameters,
          'search': normQ,
          'page': '1',
          'perPage': perPage.toString(),
          'itemType': it,
          'lookup': lookup,
          'format': 'json',
        });
        http.Response? res;
        try {
          res = await _send('GET', uri,
              {..._ocsHeader, 'authorization': _basicAuth(user, pass)});
        } catch (_) {}
        if (res != null && _isOk(res)) {
          lastRes = res;
          final ok = _ensureOk(res, 'Sharees-Suche fehlgeschlagen');
          final parsed = _parseBodyOk(ok);
          if (parsed is Map) return parsed.cast<String, dynamic>();
        }
        return null;
      }

      bool hasAny(Map<String, dynamic>? m) {
        if (m == null) return false;
        final users = (m['users'] as List?) ?? const [];
        final groups = (m['groups'] as List?) ?? const [];
        final exactM = (m['exact'] as Map?)?.cast<String, dynamic>();
        final exactUsers = (exactM?['users'] as List?) ?? const [];
        final exactGroups = (exactM?['groups'] as List?) ?? const [];
        return users.isNotEmpty ||
            groups.isNotEmpty ||
            exactUsers.isNotEmpty ||
            exactGroups.isNotEmpty;
      }

      merged = await run('false');
      if (!hasAny(merged)) {
        merged = await run('true');
      }
      if (hasAny(merged)) {
        data = merged;
        break;
      }
    }
    if (data == null) {
      _ensureOk(lastRes, 'Sharees-Suche fehlgeschlagen');
      return const [];
    }
    final out = <UserRef>[];
    void pickList(dynamic lst) {
      if (lst is List) {
        for (final e in lst.whereType<Map>()) {
          final label = (e['label'] ?? '').toString();
          final value = (e['value'] as Map?)?.cast<String, dynamic>();
          if (value == null) continue;
          final shareType = (value['shareType'] as num?)?.toInt();
          final shareWith = (value['shareWith'] ?? '').toString();
          final unique = (e['shareWithDisplayNameUnique'] ?? '').toString();
          if (shareType == 0 || shareType == 1) {
            out.add(UserRef(
                id: shareWith,
                displayName: label,
                shareType: shareType,
                altId: unique.isEmpty ? null : unique));
          }
        }
      }
    }

    final exact = (data['exact'] as Map?)?.cast<String, dynamic>();
    if (exact != null) {
      pickList(exact['users']);
      pickList(exact['groups']);
    }
    pickList(data['users']);
    pickList(data['groups']);
    // Deduplicate by id (prefer first occurrence)
    final seen = <String>{};
    final dedup = <UserRef>[];
    for (final u in out) {
      if (seen.add(u.id)) dedup.add(u);
    }
    _setCached(_shareesCache, cacheKey, dedup);
    return dedup;
  }

  // Internal helpers
  dynamic _parseBodyOk(http.Response res) {
    final decoded = jsonDecode(res.body);
    if (decoded is Map && decoded['ocs'] is Map) {
      final ocs = (decoded['ocs'] as Map).cast<String, dynamic>();
      final meta = (ocs['meta'] as Map?)?.cast<String, dynamic>();
      final status = meta?['status']?.toString().toLowerCase();
      if (status != null && status != 'ok') {
        final code = meta?['statuscode'];
        final msg = meta?['message'] ?? 'OCS-Fehler';
        throw Exception('OCS $code: $msg');
      }
      return ocs['data'];
    }
    return decoded;
  }

  http.Response _ensureOk(http.Response? res, String message) {
    if (res == null) {
      throw Exception(message);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final body = res.body;
      final snippet = body.length > 400 ? body.substring(0, 400) + '…' : body;
      throw Exception('$message (HTTP ${res.statusCode})\n$snippet');
    }
    return res;
  }

  Future<http.Response?> _get(
      String baseUrl, String user, String pass, String path,
      {bool priority = false}) async {
    return _requestVariants(baseUrl, user, pass, path, 'GET',
        priority: priority);
  }

  Future<http.Response?> _post(
      String baseUrl, String user, String pass, String path, String body,
      {bool priority = false}) async {
    return _requestVariants(baseUrl, user, pass, path, 'POST',
        body: body, contentTypeJson: true, priority: priority);
  }

  Future<http.Response?> _requestVariants(
      String baseUrl, String user, String pass, String path, String method,
      {String? body,
      bool contentTypeJson = false,
      bool priority = false}) async {
    final isOcs = path.contains('/ocs/');
    final baseHeaders = isOcs ? _ocsHeader : _restHeader;
    final headers = {
      ...baseHeaders,
      'authorization': _basicAuth(user, pass),
    };
    if (contentTypeJson) headers['Content-Type'] = 'application/json';
    // Build candidate paths in robust order:
    // 1) original path with/without index
    // 2) if original was /apps/... also try OCS v2 and v1 variants
    // 3) if original was /ocs/v2.php/... also try v1 variant
    final variants = <Uri>[];
    variants.add(_buildUri(baseUrl, path, false));
    variants.add(_buildUri(baseUrl, path, true));
    // Do NOT auto-map Deck REST to OCS variants; REST endpoints live under /apps/deck/.
    if (path.startsWith('/ocs/v2.php/')) {
      final v1 = path.replaceFirst('/ocs/v2.php/', '/ocs/v1.php/');
      variants.add(_buildUri(baseUrl, v1, false));
      variants.add(_buildUri(baseUrl, v1, true));
    }

    http.Response? last;
    for (final uri in variants) {
      try {
        final res =
            await _send(method, uri, headers, body: body, priority: priority);
        last = res;
        if (_isOk(res)) return res;
      } catch (_) {
        // try next variant
      }
    }
    // If we were calling /apps/... and got a 403, retry once with OCS header for robustness.
    if (!isOcs && (last?.statusCode == 403)) {
      final headersOcs = {
        ..._ocsHeader,
        'authorization': _basicAuth(user, pass),
        if (contentTypeJson) 'Content-Type': 'application/json',
      };
      for (final uri in variants) {
        try {
          final res = await _send(method, uri, headersOcs,
              body: body, priority: priority);
          last = res;
          if (_isOk(res)) return res;
        } catch (_) {}
      }
    }
    return last;
  }

  bool _isOk(http.Response res) =>
      res.statusCode >= 200 && res.statusCode < 300;

  Uri _buildUri(String baseUrl, String path, bool withIndexPhp) {
    // Support server-relative baseUrl ('/' or '/path') to use current origin (especially on Web)
    String b = baseUrl.trim();
    final p = path.startsWith('/') ? path : '/$path';
    if (b.isEmpty || b.startsWith('/')) {
      // Normalize base prefix
      final basePrefix = b.isEmpty
          ? ''
          : (() {
              var s = '/' + b.replaceFirst(RegExp(r'^/+'), '');
              if (s.length > 1 && s.endsWith('/'))
                s = s.substring(0, s.length - 1);
              return s;
            })();
      final prefix = withIndexPhp ? '/index.php' : '';
      final uri = Uri.parse('$basePrefix$prefix$p');
      if (p.startsWith('/ocs/') && !uri.queryParameters.containsKey('format')) {
        return uri.replace(
            queryParameters: {...uri.queryParameters, 'format': 'json'});
      }
      return uri;
    }
    // Enforce HTTPS regardless of provided scheme
    if (b.startsWith('http://')) b = 'https://' + b.substring(7);
    if (!b.startsWith('https://'))
      b = 'https://' + b.replaceFirst(RegExp(r'^/+'), '');
    final normalized = b.endsWith('/') ? b.substring(0, b.length - 1) : b;
    final prefix = withIndexPhp ? '/index.php' : '';
    final uri = Uri.parse('$normalized$prefix$p');
    // Add `format=json` for OCS if not present
    if (p.startsWith('/ocs/') && !uri.queryParameters.containsKey('format')) {
      return uri
          .replace(queryParameters: {...uri.queryParameters, 'format': 'json'});
    }
    return uri;
  }

  String _basicAuth(String user, String pass) {
    final cred = base64Encode(utf8.encode('$user:$pass'));
    return 'Basic $cred';
  }

  Future<http.Response> _send(
      String method, Uri uri, Map<String, String> headers,
      {String? body, bool priority = false, Duration? timeout}) async {
    final logger = LogService();
    final tQueueStart = DateTime.now();
    http.Response res;
    try {
      await _acquireSlot(priority: priority);
      final t0 = DateTime.now();
      final to = timeout ?? _defaultTimeout;
      switch (method) {
        case 'GET':
          res = await http.get(uri, headers: headers).timeout(to);
          break;
        case 'POST':
          res = await http.post(uri, headers: headers, body: body).timeout(to);
          break;
        case 'PUT':
          res = await http.put(uri, headers: headers, body: body).timeout(to);
          break;
        case 'PATCH':
          res = await http.patch(uri, headers: headers, body: body).timeout(to);
          break;
        case 'DELETE':
          res = await http.delete(uri, headers: headers).timeout(to);
          break;
        default:
          res = await http.get(uri, headers: headers).timeout(to);
      }
      final dur = DateTime.now().difference(t0).inMilliseconds;
      final queued = t0.difference(tQueueStart).inMilliseconds;
      final snippet =
          (res.body.length > 400) ? res.body.substring(0, 400) + '…' : res.body;
      logger.add(LogEntry(
        at: t0,
        method: method,
        url: uri.toString(),
        status: res.statusCode,
        durationMs: dur,
        queuedMs: queued > 0 ? queued : null,
        requestBody: body,
        responseSnippet: snippet,
      ));
      return res;
    } catch (e) {
      final tNow = DateTime.now();
      final dur = 0; // network duration unknown in error pre-send; keep 0
      final queued = tNow.difference(tQueueStart).inMilliseconds;
      logger.add(LogEntry(
        at: tQueueStart,
        method: method,
        url: uri.toString(),
        status: null,
        durationMs: dur,
        queuedMs: queued > 0 ? queued : null,
        requestBody: body,
        error: e.toString(),
      ));
      rethrow;
    } finally {
      _releaseSlot();
    }
  }
}

class FetchStacksResult {
  final List<deck.Column> columns;
  final String? etag;
  final bool notModified;
  const FetchStacksResult(
      {required this.columns, required this.etag, required this.notModified});
}

class FetchCardsStrictResult {
  final List<CardItem> cards;
  final String? etag;
  final bool notModified;
  const FetchCardsStrictResult(
      {required this.cards, required this.etag, required this.notModified});
}

class FetchBoardCardsResult {
  final List<Map<String, dynamic>> cards;
  final String? etag;
  final bool notModified;
  const FetchBoardCardsResult(
      {required this.cards, required this.etag, required this.notModified});
}

class FetchBoardsDetailsResult {
  final List<Map<String, dynamic>>
      boards; // raw boards with nested stacks/cards/labels/etc.
  final String? etag;
  final bool notModified;
  const FetchBoardsDetailsResult(
      {required this.boards, required this.etag, required this.notModified});
}

class _CacheEntry<T> {
  final T value;
  final DateTime expires;
  _CacheEntry({required this.value, required this.expires});
}
