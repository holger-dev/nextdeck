import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import '../models/board.dart';
import '../models/column.dart' as deck;
import '../models/card_item.dart';
import '../models/user_ref.dart';
import 'log_service.dart';

class NextcloudDeckApi {
  static const _ocsHeader = {'OCS-APIRequest': 'true', 'Accept': 'application/json'};
  static const _restHeader = {'Accept': 'application/json'};
  // Concurrency limiter and request timeout to reduce server load
  static int _maxConcurrent = 6;
  static int _inFlight = 0;
  static final List<Completer<void>> _prioWaiters = [];
  static final List<Completer<void>> _waiters = [];
  static const Duration _defaultTimeout = Duration(seconds: 30);

  Future<void> _acquireSlot({bool priority = false}) async {
    if (_inFlight < _maxConcurrent) {
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
    if (_prioWaiters.isNotEmpty) {
      final c = _prioWaiters.removeAt(0);
      c.complete();
    } else if (_waiters.isNotEmpty) {
      final c = _waiters.removeAt(0);
      c.complete();
    } else {
      _inFlight = (_inFlight - 1).clamp(0, 1 << 20);
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

  T? _getCached<T>(Map<String, _CacheEntry<T>> m, String key) {
    final e = m[key];
    if (e == null) return null;
    if (e.expires.isBefore(DateTime.now())) { m.remove(key); return null; }
    return e.value;
  }

  void _setCached<T>(Map<String, _CacheEntry<T>> m, String key, T value, {int ttlMs = _defaultTtlMs}) {
    m[key] = _CacheEntry(value: value, expires: DateTime.now().add(Duration(milliseconds: ttlMs)));
    if (m.length > _maxCacheEntries) {
      // prune expired, then oldest
      final now = DateTime.now();
      m.removeWhere((_, v) => v.expires.isBefore(now));
      if (m.length > _maxCacheEntries) {
        final oldest = m.entries.toList()..sort((a, b) => a.value.expires.compareTo(b.value.expires));
        for (int i = 0; i < oldest.length - _maxCacheEntries; i++) { m.remove(oldest[i].key); }
      }
    }
  }

  Future<bool> testLogin(String baseUrl, String username, String password) async {
    final res = await _get(baseUrl, username, password, '/ocs/v2.php/cloud/user');
    if (res == null) return false;
    try {
      _parseBodyOk(_ensureOk(res, 'Login fehlgeschlagen'));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<UserRef?> fetchCurrentUser(String baseUrl, String username, String password) async {
    final cacheKey = 'me|$baseUrl|$username';
    final cached = _getCached(_meCache, cacheKey);
    if (cached != null) return cached;
    final res = await _get(baseUrl, username, password, '/ocs/v2.php/cloud/user');
    final ok = _ensureOk(res, 'Benutzerinfo laden fehlgeschlagen');
    final data = _parseBodyOk(ok);
    try {
      if (data is Map) {
        final ocs = (data['ocs'] as Map?)?.cast<String, dynamic>();
        final d = (ocs?['data'] as Map?)?.cast<String, dynamic>();
        final id = (d?['id'] ?? '').toString();
        final dn = (d?['display-name'] ?? d?['displayName'] ?? '').toString();
        if (id.isNotEmpty) {
          final out = UserRef(id: id, displayName: dn.isEmpty ? id : dn, shareType: 0);
          _setCached(_meCache, cacheKey, out, ttlMs: _meTtlMs);
          return out;
        }
      }
    } catch (_) {}
    _setCached(_meCache, cacheKey, null, ttlMs: 5 * 1000);
    return null;
  }

  Future<bool> hasDeckEnabled(String baseUrl, String username, String password) async {
    final res = await _get(baseUrl, username, password, '/ocs/v2.php/cloud/capabilities');
    final okRes = _ensureOk(res, 'Capabilities laden fehlgeschlagen');
    final data = _parseBodyOk(okRes);
    if (data is Map && data['capabilities'] is Map) {
      final caps = (data['capabilities'] as Map).cast<String, dynamic>();
      return caps.containsKey('deck');
    }
    return false;
  }

  Future<List<Board>> fetchBoards(String baseUrl, String username, String password) async {
    // Prefer official Deck REST path, fall back to OCS if needed
    final res = await _get(baseUrl, username, password, '/apps/deck/api/v1.0/boards');
    final okRes = _ensureOk(res, 'Boards laden fehlgeschlagen');
    final data = _parseBodyOk(okRes);
    if (data is List) {
      return data.map((e) => Board.fromJson((e as Map).cast())).toList();
    }
    if (data is Map && data['boards'] is List) {
      return (data['boards'] as List).map((e) => Board.fromJson((e as Map).cast())).toList();
    }
    return [];
  }

  Future<Board?> createBoard(String baseUrl, String user, String pass, {required String title, String? color}) async {
    final body = jsonEncode({'title': title, if (color != null) 'color': color});
    final headers = {'Accept': 'application/json', 'Content-Type': 'application/json', 'authorization': _basicAuth(user, pass)};
    http.Response? last;
    for (final withIndex in [false, true]) {
      try {
        last = await _send('POST', _buildUri(baseUrl, '/apps/deck/api/v1.0/boards', withIndex), headers, body: body);
        if (_isOk(last)) {
          final data = _parseBodyOk(last!);
          if (data is Map) return Board.fromJson(data.cast<String, dynamic>());
        }
      } catch (_) {}
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> fetchBoardsRaw(String baseUrl, String username, String password) async {
    final res = await _get(baseUrl, username, password, '/apps/deck/api/v1.0/boards');
    final okRes = _ensureOk(res, 'Boards laden fehlgeschlagen');
    final data = _parseBodyOk(okRes);
    if (data is List) {
      return data.map((e) => (e as Map).cast<String, dynamic>()).toList();
    }
    if (data is Map && data['boards'] is List) {
      return (data['boards'] as List).map((e) => (e as Map).cast<String, dynamic>()).toList();
    }
    return const [];
  }

  Future<Map<String, dynamic>?> fetchBoardDetail(String baseUrl, String user, String pass, int boardId) async {
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
        final res = await _send('GET', _buildUri(baseUrl, '/apps/deck/api/v1.0/boards/$boardId', withIndex), headers);
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

  Future<Set<String>> fetchBoardMemberUids(String baseUrl, String user, String pass, int boardId) async {
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

  Future<List<deck.Column>> fetchColumns(String baseUrl, String username, String password, int boardId, {bool lazyCards = true, bool priority = false}) async {
    final res = await _get(baseUrl, username, password, '/apps/deck/api/v1.0/boards/$boardId/stacks', priority: priority);
    final okRes = _ensureOk(res, 'Spalten laden fehlgeschlagen');
    final data = _parseBodyOk(okRes);
    final List<deck.Column> columns = [];
    final List<Map<String, dynamic>> stacks;
    if (data is List) {
      stacks = data.map((e) => (e as Map).cast<String, dynamic>()).toList();
    } else if (data is Map && data['stacks'] is List) {
      stacks = (data['stacks'] as List).map((e) => (e as Map).cast<String, dynamic>()).toList();
    } else {
      return columns;
    }

    // Build deterministic ordering using explicit order field if present, else input order
    final Map<int, int> orderMap = {};
    for (int idx = 0; idx < stacks.length; idx++) {
      final s = stacks[idx];
      final id = (s['id'] as num).toInt();
      final ord = (s['order'] ?? s['position'] ?? s['sort'] ?? s['ordinal']);
      orderMap[id] = ord is num ? ord.toInt() : idx;
    }

    // Prefer inline cards if provided by the stacks response.
    final needFetch = <Map<String, dynamic>>[];
    for (final stack in stacks) {
      final stackId = stack['id'] as int;
      final title = (stack['title'] ?? stack['name'] ?? '').toString();
      final inline = stack['cards'];
      if (inline is List) {
        final cards = inline.map((e) => CardItem.fromJson((e as Map).cast<String, dynamic>())).toList();
        columns.add(deck.Column(id: stackId, title: title, cards: cards));
      } else {
        // Lazy mode: leave empty and fetch on demand later
        if (lazyCards) {
          columns.add(deck.Column(id: stackId, title: title, cards: const []));
        } else {
          needFetch.add({'id': stackId, 'title': title});
        }
      }
    }

    if (needFetch.isNotEmpty) {
      final results = await Future.wait(
        needFetch.map((m) => fetchCards(baseUrl, username, password, boardId, m['id'] as int)),
      );
      for (int i = 0; i < needFetch.length; i++) {
        columns.add(
          deck.Column(id: needFetch[i]['id'] as int, title: needFetch[i]['title'] as String, cards: results[i]),
        );
      }
    }

    // Sort by provided order/position; if equal, preserve original stacks order
    final indexMap = <int, int>{
      for (int i = 0; i < stacks.length; i++) (stacks[i]['id'] as num).toInt(): i
    };
    columns.sort((a, b) {
      final oa = orderMap[a.id] ?? 0;
      final ob = orderMap[b.id] ?? 0;
      if (oa != ob) return oa.compareTo(ob);
      final ia = indexMap[a.id] ?? 0;
      final ib = indexMap[b.id] ?? 0;
      return ia.compareTo(ib);
    });

    return columns;
  }

  Future<deck.Column?> createStack(String baseUrl, String user, String pass, int boardId, {required String title, int? order}) async {
    // Build body including optional ordering
    final Map<String, dynamic> payload = {'title': title, if (order != null) 'order': order};
    final body = jsonEncode(payload);
    final headers = {'Accept': 'application/json', 'Content-Type': 'application/json', 'authorization': _basicAuth(user, pass)};
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
          final res = await _send('POST', _buildUri(baseUrl, p, withIndex), headers, body: body);
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

  Future<List<CardItem>> fetchCards(String baseUrl, String username, String password, int boardId, int stackId, {bool priority = false}) async {
    // Try REST first; fallback to OCS variants. Return empty only if all fail.
    final headers = {..._restHeader, 'authorization': _basicAuth(username, password)};
    http.Response? last;
    for (final withIndex in [false, true]) {
      try {
        final uri = _buildUri(baseUrl, '/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards', withIndex);
        final res = await _send('GET', uri, headers, priority: priority);
        last = res;
        if (_isOk(res)) {
          return _parseCardsList(res.body);
        }
      } catch (_) {}
    }
    for (final ocsPrefix in ['/ocs/v2.php', '/ocs/v1.php']) {
      for (final withIndex in [false, true]) {
        try {
          final uri = _buildUri(baseUrl, '$ocsPrefix/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards', withIndex);
          final res = await _send('GET', uri, {..._ocsHeader, 'authorization': _basicAuth(username, password)}, priority: priority);
          last = res;
          if (_isOk(res)) {
            return _parseCardsList(res.body);
          }
        } catch (_) {}
      }
    }
    // Interpret as empty if every variant failed
    return const <CardItem>[];
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
  Future<List<Map<String, dynamic>>> fetchCommentsRaw(String baseUrl, String user, String pass, int cardId, {int limit = 50, int offset = 0}) async {
    final path = '/ocs/v2.php/apps/deck/api/v1.0/cards/$cardId/comments';
    for (final withIndex in [false, true]) {
      try {
        final uri = _buildUri(baseUrl, path, withIndex).replace(queryParameters: {
          ..._buildUri(baseUrl, path, withIndex).queryParameters,
          'limit': '$limit',
          'offset': '$offset',
        });
        final res = await _send('GET', uri, {..._ocsHeader, 'authorization': _basicAuth(user, pass)});
        _ensureOk(res, 'Kommentare laden fehlgeschlagen');
        final data = _parseBodyOk(res);
        if (data is List) {
          return data.map((e) => (e as Map).cast<String, dynamic>()).toList();
        }
      } catch (_) {}
    }
    return const [];
  }

  Future<Map<String, dynamic>?> createComment(String baseUrl, String user, String pass, int cardId, {required String message, int? parentId}) async {
    final headers = {..._ocsHeader, 'authorization': _basicAuth(user, pass), 'Content-Type': 'application/json'};
    final body = jsonEncode({'message': message, 'parentId': parentId});
    final path = '/ocs/v2.php/apps/deck/api/v1.0/cards/$cardId/comments';
    for (final withIndex in [false, true]) {
      try {
        final res = await _send('POST', _buildUri(baseUrl, path, withIndex), headers, body: body);
        _ensureOk(res, 'Kommentar erstellen fehlgeschlagen');
        final data = _parseBodyOk(res);
        if (data is Map) return data.cast<String, dynamic>();
      } catch (_) {}
    }
    return null;
  }

  Future<Map<String, dynamic>?> updateComment(String baseUrl, String user, String pass, int cardId, int commentId, {required String message}) async {
    final headers = {..._ocsHeader, 'authorization': _basicAuth(user, pass), 'Content-Type': 'application/json'};
    final body = jsonEncode({'message': message});
    final path = '/ocs/v2.php/apps/deck/api/v1.0/cards/$cardId/comments/$commentId';
    for (final withIndex in [false, true]) {
      try {
        final res = await _send('PUT', _buildUri(baseUrl, path, withIndex), headers, body: body);
        _ensureOk(res, 'Kommentar aktualisieren fehlgeschlagen');
        final data = _parseBodyOk(res);
        if (data is Map) return data.cast<String, dynamic>();
      } catch (_) {}
    }
    return null;
  }

  Future<bool> deleteComment(String baseUrl, String user, String pass, int cardId, int commentId) async {
    final headers = {..._ocsHeader, 'authorization': _basicAuth(user, pass)};
    final path = '/ocs/v2.php/apps/deck/api/v1.0/cards/$cardId/comments/$commentId';
    for (final withIndex in [false, true]) {
      try {
        final res = await _send('DELETE', _buildUri(baseUrl, path, withIndex), headers);
        if (_isOk(res)) return true;
      } catch (_) {}
    }
    return false;
  }

  // Attachments
  Future<List<Map<String, dynamic>>> fetchAttachments(String baseUrl, String user, String pass, int cardId) async {
    final path = '/apps/deck/api/v1.0/cards/$cardId/attachments';
    for (final withIndex in [false, true]) {
      try {
        final headers = {'Accept': 'application/json', 'authorization': _basicAuth(user, pass)};
        final res = await _send('GET', _buildUri(baseUrl, path, withIndex), headers);
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

  Future<bool> deleteAttachment(String baseUrl, String user, String pass, int cardId, int attachmentId) async {
    final path = '/apps/deck/api/v1.0/cards/$cardId/attachments/$attachmentId';
    for (final withIndex in [false, true]) {
      try {
        final headers = {'Accept': 'application/json', 'authorization': _basicAuth(user, pass)};
        final res = await _send('DELETE', _buildUri(baseUrl, path, withIndex), headers);
        if (_isOk(res)) return true;
      } catch (_) {}
    }
    return false;
  }

  // Deck v1.1 attachments (preferred): paths with board/stack/card
  Future<List<Map<String, dynamic>>> fetchCardAttachments(String baseUrl, String user, String pass, {required int boardId, required int stackId, required int cardId}) async {
    final candidates = <String>[
      '/apps/deck/api/v1.1/boards/$boardId/stacks/$stackId/cards/$cardId/attachments',
      '/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId/attachments',
    ];
    for (final p in candidates) {
      for (final withIndex in [false, true]) {
        try {
          final res = await _send('GET', _buildUri(baseUrl, p, withIndex), {'Accept': 'application/json', 'authorization': _basicAuth(user, pass)});
          if (_isOk(res)) {
            final data = _parseBodyOk(res);
            if (data is List) return data.map((e) => (e as Map).cast<String, dynamic>()).toList();
          }
        } catch (_) {}
      }
    }
    return const [];
  }

  Future<bool> deleteCardAttachment(String baseUrl, String user, String pass, {required int boardId, required int stackId, required int cardId, required int attachmentId, String? type}) async {
    // Strict per docs: REST v1.0 board/stack/card/attachment only, with and without index.php
    final path = '/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId/attachments/$attachmentId';
    // Some instances require OCS header even on /apps endpoints; include it to avoid 403s
    final headers = {..._ocsHeader, 'authorization': _basicAuth(user, pass)};
    for (final withIndex in [false, true]) {
      try {
        final baseUri = _buildUri(baseUrl, path, withIndex);
        final uri = (type == null || type.isEmpty)
            ? baseUri
            : baseUri.replace(queryParameters: {...baseUri.queryParameters, 'type': type});
        final res = await _send('DELETE', uri, headers);
        if (_isOk(res)) return true;
      } catch (_) {}
    }
    return false;
  }

  Future<Map<String, dynamic>?> fetchCardById(String baseUrl, String user, String pass, int cardId) async {
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
        final res = await _send('GET', _buildUri(baseUrl, '/ocs/v1.php/apps/deck/api/v1.0/cards/$cardId', withIndex), {
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

  Future<int?> resolveCardStackId(String baseUrl, String user, String pass, int boardId, int cardId) async {
    final card = await fetchCardById(baseUrl, user, pass, cardId);
    if (card != null) {
      final sid = (card['stackId'] as num?)?.toInt() ?? ((card['stack'] as Map?)?['id'] as num?)?.toInt();
      if (sid != null) return sid;
    }
    return null;
  }

  Future<bool> deleteCardAttachmentEnsureStack(String baseUrl, String user, String pass, {required int boardId, int? stackId, required int cardId, required int attachmentId, String? type}) async {
    int? sid = stackId;
    sid ??= await resolveCardStackId(baseUrl, user, pass, boardId, cardId);
    if (sid == null) return false;
    return deleteCardAttachment(baseUrl, user, pass, boardId: boardId, stackId: sid, cardId: cardId, attachmentId: attachmentId, type: type);
  }

  Future<bool> uploadCardAttachment(String baseUrl, String user, String pass, {required int boardId, required int stackId, required int cardId, required List<int> bytes, required String filename}) async {
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
          req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
          final streamed = await req.send();
          final res = await http.Response.fromStream(streamed);
          if (_isOk(res)) return true;
        } catch (_) {}
      }
    }
    return false;
  }

  Future<http.Response?> fetchAttachmentContent(String baseUrl, String user, String pass, {required int boardId, required int stackId, required int cardId, required int attachmentId}) async {
    final candidates = <String>[
      '/apps/deck/api/v1.1/boards/$boardId/stacks/$stackId/cards/$cardId/attachments/$attachmentId',
      '/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId/attachments/$attachmentId',
    ];
    for (final p in candidates) {
      for (final withIndex in [false, true]) {
        try {
          final res = await _send('GET', _buildUri(baseUrl, p, withIndex), {'authorization': _basicAuth(user, pass)});
          if (_isOk(res)) return res;
        } catch (_) {}
      }
    }
    return null;
  }

  // Download a file via WebDAV using a known remote path under the user's files
  Future<http.Response?> webdavDownload(String baseUrl, String user, String pass, String username, String remotePath) async {
    final candidates = <String>[
      '/remote.php/dav/files/$username$remotePath',
    ];
    for (final p in candidates) {
      for (final withIndex in [false, true]) {
        try {
          final res = await _send('GET', _buildUri(baseUrl, p, withIndex), {'authorization': _basicAuth(user, pass)});
          if (_isOk(res)) return res;
        } catch (_) {}
      }
    }
    return null;
  }

  Future<bool> uploadFileToWebdav(String baseUrl, String user, String pass, String username, String remotePath, List<int> bytes) async {
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
              final uri = _buildUri(baseUrl, '/remote.php/dav/files/$username$current', withIndex);
              final req = http.Request('MKCOL', uri);
              req.headers['authorization'] = _basicAuth(user, pass);
              final t0 = DateTime.now();
              final streamed = await req.send();
              final res = await http.Response.fromStream(streamed);
              final dur = DateTime.now().difference(t0).inMilliseconds;
              logger.add(LogEntry(at: t0, method: 'MKCOL', url: uri.toString(), status: res.statusCode, durationMs: dur, responseSnippet: res.body.length > 200 ? res.body.substring(0, 200) + '…' : res.body));
              // 201 created or 405 Method Not Allowed (exists) are fine
              if (res.statusCode == 201 || res.statusCode == 200 || res.statusCode == 405) break;
            } catch (e) {
              final dur = 0;
              logger.add(LogEntry(at: DateTime.now(), method: 'MKCOL', url: '/remote.php/dav/files/$username$current', status: null, durationMs: dur, error: e.toString()));
            }
          }
        }
      }
    } catch (e) {
      logger.add(LogEntry(at: DateTime.now(), method: 'MKCOL', url: 'folder-ensure', status: null, durationMs: 0, error: e.toString()));
    }
    try {
      for (final withIndex in [false, true]) {
        final uri = _buildUri(baseUrl, '/remote.php/dav/files/$username$p', withIndex);
        final t0 = DateTime.now();
        final res = await http.put(uri, headers: {'authorization': _basicAuth(user, pass)}, body: bytes);
        final dur = DateTime.now().difference(t0).inMilliseconds;
        final snippet = (res.body.length > 200) ? res.body.substring(0, 200) + '…' : res.body;
        logger.add(LogEntry(at: t0, method: 'PUT', url: uri.toString(), status: res.statusCode, durationMs: dur, responseSnippet: snippet));
        if (_isOk(res)) return true;
      }
      return false;
    } catch (e) {
      logger.add(LogEntry(at: DateTime.now(), method: 'PUT', url: '/remote.php/dav/files/$username$p', status: null, durationMs: 0, error: e.toString()));
      return false;
    }
  }

  Future<int?> webdavGetFileId(String baseUrl, String user, String pass, String username, String remotePath) async {
    final logger = LogService();
    String p = remotePath.startsWith('/') ? remotePath : '/$remotePath';
    p = p.replaceAll(RegExp(r'/{2,}'), '/');
    try {
      final uri = _buildUri(baseUrl, '/remote.php/dav/files/$username$p', false);
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
      logger.add(LogEntry(at: t0, method: 'PROPFIND', url: uri.toString(), status: res.statusCode, durationMs: dur, responseSnippet: res.body.length > 200 ? res.body.substring(0, 200) + '…' : res.body));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final m = RegExp(r'<oc:fileid>([^<]+)</oc:fileid>').firstMatch(res.body);
        if (m != null) {
          final idStr = m.group(1);
          final id = int.tryParse(idStr ?? '');
          return id;
        }
      }
    } catch (e) {
      logger.add(LogEntry(at: DateTime.now(), method: 'PROPFIND', url: '/remote.php/dav/files/$username$p', status: null, durationMs: 0, error: e.toString()));
    }
    return null;
  }

  Future<bool> linkAttachment(String baseUrl, String user, String pass, int cardId, {required String filePath, int? fileId, int? boardId, int? stackId}) async {
    final List<String> candidates = [];
    if (boardId != null && stackId != null) {
      candidates.add('/apps/deck/api/v1.1/boards/$boardId/stacks/$stackId/cards/$cardId/attachments');
      candidates.add('/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId/attachments');
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
          final res = await _send('POST', _buildUri(baseUrl, p, withIndex), {'Accept': 'application/json', 'Content-Type': 'application/json', 'authorization': _basicAuth(user, pass)}, body: body);
          if (_isOk(res)) return true;
        } catch (_) {}
      }
    }
    return false;
  }

  Future<void> createCard(String baseUrl, String username, String password, int boardId, int columnId, String title, {String? description}) async {
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
    );
    _ensureOk(res, 'Karte erstellen fehlgeschlagen');
  }

  Future<bool> deleteCard(String baseUrl, String user, String pass, {required int boardId, required int stackId, required int cardId}) async {
    final headers = {'Accept': 'application/json', 'authorization': _basicAuth(user, pass)};
    final paths = <String>[
      '/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId',
      '/apps/deck/api/v1.0/cards/$cardId',
      '/ocs/v1.php/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId',
      '/ocs/v1.php/apps/deck/api/v1.0/cards/$cardId',
    ];
    for (final p in paths) {
      try {
        final res = await _send('DELETE', _buildUri(baseUrl, p, false), headers);
        if (_isOk(res)) return true;
        final res2 = await _send('DELETE', _buildUri(baseUrl, p, true), headers);
        if (_isOk(res2)) return true;
      } catch (_) {}
    }
    return false;
  }

  // Cards: fetch single, update, labels management
  Future<Map<String, dynamic>?> fetchCard(String baseUrl, String user, String pass, int boardId, int stackId, int cardId) async {
    // Deck REST card endpoint under board/stack scope
    final res = await _get(baseUrl, user, pass, '/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId');
    final ok = _ensureOk(res, 'Karte laden fehlgeschlagen');
    final data = _parseBodyOk(ok);
    if (data is Map) return data.cast<String, dynamic>();
    return null;
  }

  Future<void> updateCard(String baseUrl, String user, String pass, int boardId, int stackId, int cardId, Map<String, dynamic> patch) async {
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
        payload['duedate'] = DateTime.fromMillisecondsSinceEpoch(v * 1000, isUtc: true).toIso8601String();
      } else if (v is String) {
        // assume already ISO
      } else if (v == null) {
        payload['duedate'] = null;
      }
    }

    Future<http.Response?> trySend(String method, String path, Map<String, dynamic> body) async {
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
        res = await _send(method, _buildUri(baseUrl, path, false), headers, body: bodyJson);
        if (!_isOk(res)) {
          res = await _send(method, _buildUri(baseUrl, path, true), headers, body: bodyJson);
        }
      } catch (_) {
        try {
          res = await _send(method, _buildUri(baseUrl, path, true), headers, body: bodyJson);
        } catch (_) {
          res = null;
        }
      }
      return res;
    }

    http.Response? res;
    final newStackId = payload['stackId'] is num ? (payload['stackId'] as num).toInt() : null;
    // Build prioritized attempts; minimize requests for speed
    final attempts = <Map<String, dynamic>>[];
    if (newStackId != null && newStackId != stackId) {
      // 1) REST new-stack path without stackId in body (matches your server success)
      attempts.add({
        'path': '/apps/deck/api/v1.0/boards/$boardId/stacks/$newStackId/cards/$cardId',
        'body': {...payload}..remove('stackId')
      });
      // 2) REST old-stack path with stackId in body
      attempts.add({
        'path': '/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId',
        'body': payload,
      });
      // 3) REST card root with stackId in body
      attempts.add({
        'path': '/apps/deck/api/v1.0/cards/$cardId',
        'body': payload,
      });
      // 4) OCS v1 new-stack path without stackId in body
      attempts.add({
        'path': '/ocs/v1.php/apps/deck/api/v1.0/boards/$boardId/stacks/$newStackId/cards/$cardId',
        'body': {...payload}..remove('stackId'),
      });
      // 5) OCS v1 old-stack path with stackId
      attempts.add({
        'path': '/ocs/v1.php/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId',
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
          'path': '/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId',
          'body': payload,
        },
        {
          'path': '/apps/deck/api/v1.0/cards/$cardId',
          'body': payload,
        },
        {
          'path': '/ocs/v1.php/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId',
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
          ids = raw.map((e) => e is int ? e : (e is Map && e['id'] is int ? e['id'] as int : null)).whereType<int>().toList();
        }
        final asIds = {...baseBody, 'labels': ids};
        final asObjs = {...baseBody, 'labels': ids.map((i) => {'id': i}).toList()};
        final asObjsWithBoard = {...baseBody, 'labels': ids.map((i) => {'id': i, 'boardId': boardId}).toList()};
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
              if (v is String) uids.add(v);
              else if (v is Map && v['id'] is String) uids.add(v['id'] as String);
              else if (v is Map && v['uid'] is String) uids.add(v['uid'] as String);
            }
          }
          final asUsers = {...b, 'assignedUsers': uids}..remove('assignees');
          final asMembers = {...b, 'members': uids}..remove('assignedUsers')..remove('assignees');
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
                if (decoded['stackId'] is num) respStack = (decoded['stackId'] as num).toInt();
                final stackObj = decoded['stack'] as Map?;
                if (respStack == null && stackObj != null && stackObj['id'] is num) respStack = (stackObj['id'] as num).toInt();
              }
              if (respStack == newStackId) { accepted = true; break; }
            } catch (_) {}
          } else {
            accepted = true; break;
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
          final meta = (decoded['ocs']['meta'] as Map?)?.cast<String, dynamic>();
          final status = meta?['status']?.toString().toLowerCase();
          if (status != null && status != 'ok') {
            final code = meta?['statuscode'];
            final msg = meta?['message'] ?? 'OCS-Fehler';
            throw Exception('Karte aktualisieren fehlgeschlagen: OCS $code: $msg');
          }
        }
      } catch (_) {}
      if (newStackId != null && newStackId != stackId) {
        throw Exception('Karte verschieben fehlgeschlagen (keine Variante akzeptiert)');
      }
    }
  }

  Future<List<Map<String, dynamic>>> fetchBoardLabels(String baseUrl, String user, String pass, int boardId) async {
    http.Response? res = await _get(baseUrl, user, pass, '/apps/deck/api/v1.0/boards/$boardId/labels');
    if (res == null || res.statusCode == 405 || res.statusCode == 404) {
      // Try OCS variants
      res = await _get(baseUrl, user, pass, '/ocs/v2.php/apps/deck/api/v1.0/boards/$boardId/labels');
      if (res == null || res.statusCode == 405 || res.statusCode == 404) {
        res = await _get(baseUrl, user, pass, '/ocs/v1.php/apps/deck/api/v1.0/boards/$boardId/labels');
      }
    }
    final ok = _ensureOk(res, 'Labels laden fehlgeschlagen');
    final data = _parseBodyOk(ok);
    if (data is List) {
      return data.map((e) => (e as Map).cast<String, dynamic>()).toList();
    }
    return const [];
  }

  Future<Map<String, dynamic>> createBoardLabel(String baseUrl, String user, String pass, int boardId, {required String title, required String color}) async {
    String cleanColor = color.trim();
    if (cleanColor.startsWith('#')) cleanColor = cleanColor.substring(1);
    final body = jsonEncode({'title': title, 'color': cleanColor});
    http.Response? res = await _post(baseUrl, user, pass, '/apps/deck/api/v1.0/boards/$boardId/labels', body);
    if (res == null || res.statusCode < 200 || res.statusCode >= 300) {
      res = await _post(baseUrl, user, pass, '/ocs/v1.php/apps/deck/api/v1.0/boards/$boardId/labels', body);
    }
    final ok = _ensureOk(res, 'Label erstellen fehlgeschlagen');
    final data = _parseBodyOk(ok);
    if (data is Map) return data.cast<String, dynamic>();
    return {'id': null, 'title': title, 'color': cleanColor};
  }

  Future<Map<String, dynamic>> updateBoardLabel(String baseUrl, String user, String pass, int boardId, int labelId, {String? title, String? color}) async {
    final payload = <String, dynamic>{
      if (title != null) 'title': title,
      if (color != null) 'color': color.startsWith('#') ? color.substring(1) : color,
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
        res = await _send('PUT', _buildUri(baseUrl, path, false), headers, body: body);
        if (!_isOk(res)) res = await _send('PUT', _buildUri(baseUrl, path, true), headers, body: body);
      } catch (_) {}
      return res;
    }
    http.Response? res = await tryPut('/apps/deck/api/v1.0/boards/$boardId/labels/$labelId');
    res ??= await tryPut('/ocs/v1.php/apps/deck/api/v1.0/boards/$boardId/labels/$labelId');
    final ok = _ensureOk(res, 'Label aktualisieren fehlgeschlagen');
    final data = _parseBodyOk(ok);
    if (data is Map) return data.cast<String, dynamic>();
    return {'id': labelId, 'title': title, 'color': color};
  }

  Future<void> deleteBoardLabel(String baseUrl, String user, String pass, int boardId, int labelId) async {
    final headersRest = {'Accept': 'application/json', 'authorization': _basicAuth(user, pass)};
    http.Response? res;
    try {
      res = await http.delete(_buildUri(baseUrl, '/apps/deck/api/v1.0/boards/$boardId/labels/$labelId', false), headers: headersRest);
      if (!_isOk(res)) res = await http.delete(_buildUri(baseUrl, '/apps/deck/api/v1.0/boards/$boardId/labels/$labelId', true), headers: headersRest);
    } catch (_) {}
    if (res == null || !_isOk(res)) {
      final headersOcs = {..._ocsHeader, 'authorization': _basicAuth(user, pass)};
      try {
        res = await http.delete(_buildUri(baseUrl, '/ocs/v1.php/apps/deck/api/v1.0/boards/$boardId/labels/$labelId', false), headers: headersOcs);
        if (!_isOk(res)) res = await http.delete(_buildUri(baseUrl, '/ocs/v1.php/apps/deck/api/v1.0/boards/$boardId/labels/$labelId', true), headers: headersOcs);
      } catch (_) {}
    }
    _ensureOk(res, 'Label löschen fehlgeschlagen');
  }

  Future<void> addLabelToCard(String baseUrl, String user, String pass, int cardId, int labelId, {int? boardId, int? stackId}) async {
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
          var res = await _send('PUT', _buildUri(baseUrl, p, false), headers, body: body);
          if (_isOk(res)) { _parseBodyOk(res); return; }
          res = await _send('PUT', _buildUri(baseUrl, p, true), headers, body: body);
          if (_isOk(res)) { _parseBodyOk(res); return; }
        } catch (_) {}
      }
    }
    // Try multiple payload keys and REST/OCS variants, including path-with-id forms
    final payloads = [
      jsonEncode({'labelId': labelId}),
      jsonEncode({'label': labelId}),
    ];
    final postPaths = <String>[
      if (boardId != null && stackId != null) '/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId/labels',
      if (boardId != null) '/apps/deck/api/v1.0/boards/$boardId/cards/$cardId/labels',
      '/apps/deck/api/v1.0/cards/$cardId/labels',
      if (boardId != null && stackId != null) '/ocs/v1.php/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId/labels',
      if (boardId != null) '/ocs/v1.php/apps/deck/api/v1.0/boards/$boardId/cards/$cardId/labels',
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
          last = await _send('POST', _buildUri(baseUrl, p, false), headers, body: b);
          if (_isOk(last)) { try { _parseBodyOk(last); return; } catch (_) {} }
          last = await _send('POST', _buildUri(baseUrl, p, true), headers, body: b);
          if (_isOk(last)) { try { _parseBodyOk(last); return; } catch (_) {} }
        } catch (_) {}
      }
    }
    // Path-based variants (no body)
    final pathIdVariants = <String>[
      if (boardId != null && stackId != null) '/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId/labels/$labelId',
      if (boardId != null) '/apps/deck/api/v1.0/boards/$boardId/cards/$cardId/labels/$labelId',
      '/apps/deck/api/v1.0/cards/$cardId/labels/$labelId',
      if (boardId != null && stackId != null) '/ocs/v1.php/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId/labels/$labelId',
      if (boardId != null) '/ocs/v1.php/apps/deck/api/v1.0/boards/$boardId/cards/$cardId/labels/$labelId',
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
        if (_isOk(last)) { try { _parseBodyOk(last); return; } catch (_) {} }
        last = await _send('POST', _buildUri(baseUrl, p, false), headers);
        if (_isOk(last)) { try { _parseBodyOk(last); return; } catch (_) {} }
        last = await _send('PUT', _buildUri(baseUrl, p, true), headers);
        if (_isOk(last)) { try { _parseBodyOk(last); return; } catch (_) {} }
        last = await _send('POST', _buildUri(baseUrl, p, true), headers);
        if (_isOk(last)) { try { _parseBodyOk(last); return; } catch (_) {} }
      } catch (_) {}
    }
    _ensureOk(last, 'Label hinzufügen fehlgeschlagen');
  }

  Future<void> removeLabelFromCard(String baseUrl, String user, String pass, int cardId, int labelId, {int? boardId, int? stackId}) async {
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
          var res = await _send('PUT', _buildUri(baseUrl, p, false), headers, body: body);
          if (_isOk(res)) { _parseBodyOk(res); return; }
          res = await _send('PUT', _buildUri(baseUrl, p, true), headers, body: body);
          if (_isOk(res)) { _parseBodyOk(res); return; }
        } catch (_) {}
      }
    }
    // DELETE variants: REST and OCS v1/v2
    final paths = <String>[
      if (boardId != null && stackId != null) '/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId/labels/$labelId',
      if (boardId != null) '/apps/deck/api/v1.0/boards/$boardId/cards/$cardId/labels/$labelId',
      '/apps/deck/api/v1.0/cards/$cardId/labels/$labelId',
      if (boardId != null && stackId != null) '/ocs/v1.php/apps/deck/api/v1.0/boards/$boardId/stacks/$stackId/cards/$cardId/labels/$labelId',
      if (boardId != null) '/ocs/v1.php/apps/deck/api/v1.0/boards/$boardId/cards/$cardId/labels/$labelId',
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
          try { _parseBodyOk(res!); return; } catch (_) {}
        }
        res = await http.delete(_buildUri(baseUrl, p, true), headers: headers);
        if (_isOk(res)) {
          try { _parseBodyOk(res!); return; } catch (_) {}
        }
      } catch (_) {}
    }
    _ensureOk(res, 'Label entfernen fehlgeschlagen');
  }

  // Move card to another stack (robust across NC variants)
  Future<void> moveCard(String baseUrl, String user, String pass, {
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
      {'method': 'POST', 'path': '/apps/deck/api/v1.0/boards/$boardId/stacks/$fromStackId/cards/$cardId/move'},
      {'method': 'PUT',  'path': '/apps/deck/api/v1.0/boards/$boardId/stacks/$fromStackId/cards/$cardId/move'},
      // Deck REST: card stack endpoint
      {'method': 'POST', 'path': '/apps/deck/api/v1.0/cards/$cardId/stack'},
      {'method': 'PUT',  'path': '/apps/deck/api/v1.0/cards/$cardId/stack'},
      // OCS v1 variants
      {'method': 'POST', 'path': '/ocs/v1.php/apps/deck/api/v1.0/boards/$boardId/stacks/$fromStackId/cards/$cardId/move'},
      {'method': 'PUT',  'path': '/ocs/v1.php/apps/deck/api/v1.0/boards/$boardId/stacks/$fromStackId/cards/$cardId/move'},
      {'method': 'POST', 'path': '/ocs/v1.php/apps/deck/api/v1.0/cards/$cardId/stack'},
      {'method': 'PUT',  'path': '/ocs/v1.php/apps/deck/api/v1.0/cards/$cardId/stack'},
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
        last = await _send(c['method']!, _buildUri(baseUrl, c['path']!, false), headers, body: payload);
        if (_isOk(last)) {
          // Validate OCS meta if present
          try { _parseBodyOk(last); success = true; break; } catch (_) {}
        }
        last = await _send(c['method']!, _buildUri(baseUrl, c['path']!, true), headers, body: payload);
        if (_isOk(last)) {
          try { _parseBodyOk(last); success = true; break; } catch (_) {}
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
  Future<void> addAssigneeToCard(String baseUrl, String user, String pass, int cardId, String userId) async {
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

  Future<void> removeAssigneeFromCard(String baseUrl, String user, String pass, int cardId, String userId) async {
    final headersRest = {'Accept': 'application/json', 'authorization': _basicAuth(user, pass)};
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
        last = await http.delete(_buildUri(baseUrl, p, false), headers: headers);
        if (_isOk(last)) return;
        last = await http.delete(_buildUri(baseUrl, p, true), headers: headers);
        if (_isOk(last)) return;
      } catch (_) {}
    }
    _ensureOk(last, 'Zuweisung entfernen fehlgeschlagen');
  }

  // v1.1 Assign/Unassign user with board/stack context
  Future<void> assignUserToCard(String baseUrl, String user, String pass, {
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
            last = await _send(method, _buildUri(baseUrl, p, false), headers, body: body);
            if (_isOk(last)) { _parseBodyOk(last!); return; }
            last = await _send(method, _buildUri(baseUrl, p, true), headers, body: body);
            if (_isOk(last)) { _parseBodyOk(last!); return; }
          } catch (_) {}
        }
      }
    }
    _ensureOk(last, 'Benutzer zuweisen fehlgeschlagen');
  }

  Future<void> unassignUserFromCard(String baseUrl, String user, String pass, {
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
            last = await _send(method, _buildUri(baseUrl, p, false), headers, body: body);
            if (_isOk(last)) { _parseBodyOk(last!); return; }
            last = await _send(method, _buildUri(baseUrl, p, true), headers, body: body);
            if (_isOk(last)) { _parseBodyOk(last!); return; }
          } catch (_) {}
        }
      }
    }
    _ensureOk(last, 'Benutzer entfernen fehlgeschlagen');
  }

  // Board shares
  Future<List<Map<String, dynamic>>> fetchBoardShares(String baseUrl, String user, String pass, int boardId) async {
    final res = await _get(baseUrl, user, pass, '/apps/deck/api/v1.0/boards/$boardId/shares');
    final ok = _ensureOk(res, 'Board-Shares laden fehlgeschlagen');
    final data = _parseBodyOk(ok);
    if (data is List) {
      return data.map((e) => (e as Map).cast<String, dynamic>()).toList();
    }
    return const [];
  }

  Future<void> addBoardShare(String baseUrl, String user, String pass, int boardId, {required int shareType, required String shareWith, int? permissions}) async {
    final body = jsonEncode({
      'shareType': shareType,
      'shareWith': shareWith,
      if (permissions != null) 'permissions': permissions,
    });
    final res = await _post(baseUrl, user, pass, '/apps/deck/api/v1.0/boards/$boardId/shares', body);
    _ensureOk(res, 'Board teilen fehlgeschlagen');
  }

  Future<void> removeBoardShare(String baseUrl, String user, String pass, int boardId, int shareId) async {
    final headers = {'Accept': 'application/json', 'authorization': _basicAuth(user, pass)};
    http.Response? res;
    try {
      res = await http.delete(_buildUri(baseUrl, '/apps/deck/api/v1.0/boards/$boardId/shares/$shareId', false), headers: headers);
      if (!_isOk(res)) {
        res = await http.delete(_buildUri(baseUrl, '/apps/deck/api/v1.0/boards/$boardId/shares/$shareId', true), headers: headers);
      }
    } catch (_) {}
    _ensureOk(res, 'Board-Freigabe entfernen fehlgeschlagen');
  }

  // Sharees search (users/groups) via OCS sharees API
  Future<List<UserRef>> searchSharees(String baseUrl, String user, String pass, String query, {int perPage = 20}) async {
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
        try { res = await _send('GET', uri, {..._ocsHeader, 'authorization': _basicAuth(user, pass)}); } catch (_) {}
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
        return users.isNotEmpty || groups.isNotEmpty || exactUsers.isNotEmpty || exactGroups.isNotEmpty;
      }
      merged = await run('false');
      if (!hasAny(merged)) {
        merged = await run('true');
      }
      if (hasAny(merged)) { data = merged; break; }
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
            out.add(UserRef(id: shareWith, displayName: label, shareType: shareType, altId: unique.isEmpty ? null : unique));
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

  Future<http.Response?> _get(String baseUrl, String user, String pass, String path, {bool priority = false}) async {
    return _requestVariants(baseUrl, user, pass, path, 'GET', priority: priority);
  }

  Future<http.Response?> _post(String baseUrl, String user, String pass, String path, String body, {bool priority = false}) async {
    return _requestVariants(baseUrl, user, pass, path, 'POST', body: body, contentTypeJson: true, priority: priority);
  }

  Future<http.Response?> _requestVariants(
    String baseUrl,
    String user,
    String pass,
    String path,
    String method,
    {String? body, bool contentTypeJson = false, bool priority = false}
  ) async {
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
        final res = await _send(method, uri, headers, body: body, priority: priority);
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
          final res = await _send(method, uri, headersOcs, body: body, priority: priority);
          last = res;
          if (_isOk(res)) return res;
        } catch (_) {}
      }
    }
    return last;
  }

  bool _isOk(http.Response res) => res.statusCode >= 200 && res.statusCode < 300;

  Uri _buildUri(String baseUrl, String path, bool withIndexPhp) {
    // Enforce HTTPS regardless of provided scheme
    String b = baseUrl.trim();
    if (b.startsWith('http://')) b = 'https://' + b.substring(7);
    if (!b.startsWith('https://')) b = 'https://' + b.replaceFirst(RegExp(r'^/+'), '');
    final normalized = b.endsWith('/') ? b.substring(0, b.length - 1) : b;
    final prefix = withIndexPhp ? '/index.php' : '';
    final p = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$normalized$prefix$p');
    // Add `format=json` for OCS if not present
    if (p.startsWith('/ocs/') && !uri.queryParameters.containsKey('format')) {
      return uri.replace(queryParameters: {...uri.queryParameters, 'format': 'json'});
    }
    return uri;
  }

  String _basicAuth(String user, String pass) {
    final cred = base64Encode(utf8.encode('$user:$pass'));
    return 'Basic $cred';
  }

  Future<http.Response> _send(String method, Uri uri, Map<String, String> headers, {String? body, bool priority = false}) async {
    final logger = LogService();
    final t0 = DateTime.now();
    http.Response res;
    try {
      await _acquireSlot(priority: priority);
      switch (method) {
        case 'GET':
          res = await http.get(uri, headers: headers).timeout(_defaultTimeout);
          break;
        case 'POST':
          res = await http.post(uri, headers: headers, body: body).timeout(_defaultTimeout);
          break;
        case 'PUT':
          res = await http.put(uri, headers: headers, body: body).timeout(_defaultTimeout);
          break;
        case 'PATCH':
          res = await http.patch(uri, headers: headers, body: body).timeout(_defaultTimeout);
          break;
        case 'DELETE':
          res = await http.delete(uri, headers: headers).timeout(_defaultTimeout);
          break;
        default:
          res = await http.get(uri, headers: headers).timeout(_defaultTimeout);
      }
      final dur = DateTime.now().difference(t0).inMilliseconds;
      final snippet = (res.body.length > 400) ? res.body.substring(0, 400) + '…' : res.body;
      logger.add(LogEntry(
        at: t0,
        method: method,
        url: uri.toString(),
        status: res.statusCode,
        durationMs: dur,
        requestBody: body,
        responseSnippet: snippet,
      ));
      return res;
    } catch (e) {
      final dur = DateTime.now().difference(t0).inMilliseconds;
      logger.add(LogEntry(
        at: t0,
        method: method,
        url: uri.toString(),
        status: null,
        durationMs: dur,
        requestBody: body,
        error: e.toString(),
      ));
      rethrow;
    } finally {
      _releaseSlot();
    }
  }
}

class _CacheEntry<T> {
  final T value;
  final DateTime expires;
  _CacheEntry({required this.value, required this.expires});
}
