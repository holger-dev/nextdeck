import 'dart:convert';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import '../net/api_client.dart';
import '../net/api_response.dart';
import '../net/request_deduplicator.dart';
import '../sync/sync_queue.dart';
import '../models/board.dart';
import '../models/column.dart' as deck;
import '../models/card_item.dart';
import 'sync_service.dart';

class SyncServiceImpl implements SyncService {
  final String base;
  final String user;
  final String pass;
  final Box cache;
  final ApiClient client;

  SyncServiceImpl(
      {required this.base,
      required this.user,
      required this.pass,
      required this.cache})
      : client = ApiClient(http.Client(), RequestDeduplicator());

  Uri _abs(String path, [Map<String, String>? query]) {
    final pfx = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final idx = path.startsWith('/') ? path : '/$path';
    var uri = Uri.parse('$pfx$idx');
    if (query != null && query.isNotEmpty)
      uri = uri.replace(queryParameters: {...uri.queryParameters, ...query});
    if (idx.startsWith('/ocs/') && !uri.queryParameters.containsKey('format')) {
      uri = uri
          .replace(queryParameters: {...uri.queryParameters, 'format': 'json'});
    }
    return uri;
  }

  Map<String, String> _authHeaders() => {
        'authorization': 'Basic ' + base64Encode(utf8.encode('$user:$pass')),
      };

  @override
  Future<void> initSyncOnAppStart() async {
    // Gatekeeper: boards?details=true (no ETag on first boot)
    await _gatekeeper(initial: true);
    // After boards+stacks stored, do a light stacks fetch per board (to get inline cards where available)
    final boards = _readBoardsFromCache();
    for (final b in boards) {
      await SyncQueue.run(() async {
        await _fetchStacksForBoard(b.id);
      });
    }
  }

  @override
  Future<void> periodicDeltaSync() async {
    await _gatekeeper(initial: false);
  }

  @override
  Future<void> refreshUpcoming() async {
    await periodicDeltaSync();
  }

  @override
  Future<void> ensureBoardFresh(int boardId) async {
    await _fetchStacksForBoard(boardId);
  }

  @override
  Future<void> verifyAfterWrite(
      {required int boardId, Set<int> stackIds = const {}}) async {
    await ensureBoardFresh(boardId);
  }

  Future<void> _gatekeeper({required bool initial}) async {
    final metaKey = 'meta_boards_index';
    final prev = cache.get(metaKey);
    final prevEtag =
        initial ? null : (prev is Map ? prev['etag'] as String? : null);
    Future<http.Response> fetchBoards({required bool details}) {
      final query = details ? {'details': 'true'} : null;
      final uri = _abs('/apps/deck/api/v1.0/boards', query);
      return http.get(uri, headers: {
        'Accept': 'application/json',
        ..._authHeaders(),
        if (prevEtag != null && details) 'If-None-Match': prevEtag,
      });
    }

    List<Map<String, dynamic>>? parseBoards(http.Response resp) {
      if (!(resp.statusCode >= 200 && resp.statusCode < 300) &&
          resp.statusCode != 404) {
        return null;
      }
      try {
        final decoded = jsonDecode(resp.body);
        final dynamic raw = decoded is List
            ? decoded
            : (decoded is Map && decoded['boards'] is List)
                ? decoded['boards']
                : null;
        if (raw is List) {
          return raw
              .whereType<Map>()
              .map((e) => (e as Map).cast<String, dynamic>())
              .toList();
        }
      } catch (_) {
        return null;
      }
      return null;
    }

    http.Response response = await fetchBoards(details: true);
    if (response.statusCode == 304) return;
    var boards = parseBoards(response);
    if (boards == null && response.statusCode == 404) {
      response = await fetchBoards(details: false);
      if (response.statusCode == 304) return;
      boards = parseBoards(response);
    }
    if (boards == null) {
      throw HttpException('${response.statusCode}: ${response.reasonPhrase}');
    }

    final et = response.headers['etag'] ??
        response.headers['ETag'] ??
        response.headers['Etag'];
    cache.put(
        'boards',
        boards
            .map((m) => {
                  'id': (m['id'] as num).toInt(),
                  'title': (m['title'] ?? m['name'] ?? '').toString(),
                  'archived': (m['archived'] ?? false) == true,
                  if (m['color'] != null) 'color': m['color'].toString(),
                })
            .toList());
    for (final m in boards) {
      final bid = (m['id'] as num).toInt();
      final stacks = (m['stacks'] ?? m['columns'] ?? m['lists']);
      if (stacks is List) {
        final cols = <Map<String, dynamic>>[];
        for (final s in stacks.whereType<Map>()) {
          cols.add({
            'id': (s['id'] as num).toInt(),
            'title': (s['title'] ?? s['name'] ?? '').toString()
          });
        }
        cache.put('stacks_$bid', cols);
        // For UI: columns_{boardId} with empty cards initially
        cache.put(
            'columns_$bid',
            cols
                .map((c) =>
                    {'id': c['id'], 'title': c['title'], 'cards': const []})
                .toList());
      }
    }
    cache.put(metaKey,
        {'etag': et, 'lastChecked': DateTime.now().millisecondsSinceEpoch});
  }

  Future<void> _fetchStacksForBoard(int boardId) async {
    final metaKey = 'meta_board_$boardId';
    final prev = cache.get(metaKey);
    final prevEtag = prev is Map ? prev['etag'] as String? : null;
    // Try REST stacks endpoint (v1.0)
    Future<bool> tryPath(String path) async {
      final uri = _abs(path);
      final res = await http.get(uri, headers: {
        'Accept': 'application/json',
        ..._authHeaders(),
        if (prevEtag != null) 'If-None-Match': prevEtag
      });
      if (res.statusCode == 304) return true;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final et =
            res.headers['etag'] ?? res.headers['ETag'] ?? res.headers['Etag'];
        final decoded = jsonDecode(res.body);
        final stacks = decoded is List
            ? decoded
            : (decoded is Map && decoded['stacks'] is List)
                ? (decoded['stacks'] as List)
                : const [];
        final cols = <Map<String, dynamic>>[];
        final cardsByStack = <int, List<Map<String, dynamic>>>{};
        for (final s in stacks.whereType<Map>()) {
          final sm = (s as Map).cast<String, dynamic>();
          final sid = (sm['id'] as num).toInt();
          final title = (sm['title'] ?? sm['name'] ?? '').toString();
          cols.add({'id': sid, 'title': title});
          final cards = sm['cards'];
          if (cards is List) {
            cardsByStack[sid] = cards
                .whereType<Map>()
                .map((e) => (e as Map).cast<String, dynamic>())
                .toList();
          }
        }
        cache.put('stacks_$boardId', cols);
        cache.put(
            'columns_$boardId',
            cols
                .map((c) => {
                      'id': c['id'],
                      'title': c['title'],
                      'cards': (cardsByStack[c['id']] ??
                              const <Map<String, dynamic>>[])
                          .map((e) => {
                                'id': (e['id'] as num).toInt(),
                                'title':
                                    (e['title'] ?? e['name'] ?? '').toString(),
                                'description': (e['description'] as String?),
                                'duedate': _cardDueMs(e),
                                'labels': ((e['labels'] as List?) ?? const [])
                                    .whereType<Map>()
                                    .map((l) => {
                                          'id':
                                              (l['id'] as num?)?.toInt() ?? -1,
                                          'title':
                                              (l['title'] ?? '').toString(),
                                          'color': (l['color'] ?? '').toString()
                                        })
                                    .toList(),
                              })
                          .toList(),
                    })
                .toList());
        cache.put(metaKey,
            {'etag': et, 'lastChecked': DateTime.now().millisecondsSinceEpoch});
        return true;
      }
      return false;
    }

    // Try REST with and without index.php
    if (await tryPath('/apps/deck/api/v1.0/boards/$boardId/stacks')) return;
    if (await tryPath('/index.php/apps/deck/api/v1.0/boards/$boardId/stacks'))
      return;
    // As a last resort, do nothing (no stacks endpoint)
  }

  int? _cardDueMs(Map<String, dynamic> m) {
    final v =
        m['duedate'] ?? m['due'] ?? m['duedateAt'] ?? m['duedateTimestamp'];
    if (v == null) return null;
    if (v is num) {
      final ms = v.toInt() < 1000000000000 ? v.toInt() * 1000 : v.toInt();
      return ms;
    }
    try {
      return DateTime.parse(v.toString()).toUtc().millisecondsSinceEpoch;
    } catch (_) {}
    return null;
  }

  List<Board> _readBoardsFromCache() {
    final rawBoards = cache.get('boards');
    if (rawBoards is List) {
      return rawBoards
          .whereType<Map>()
          .map((e) => Board.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    }
    return const [];
  }
}
