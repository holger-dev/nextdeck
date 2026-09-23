import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'sync_service.dart';

class SyncServiceImpl implements SyncService {
  final String baseUrl;
  final String username;
  final String password;
  final Box cache;

  // Wiederverwendbarer HTTP-Client mit Keep-Alive. Spart pro Sync-Pass
  // dutzende TLS-Handshakes gegenüber `http.get`, das pro Aufruf eine
  // frische Connection aufbaut.
  final http.Client _client = http.Client();

  // Timeout für Sync-Calls. Ohne diesen Wert wartet die App im Worst Case
  // im OS-Default (~75 s+) auf einen toten Server — währenddessen läuft
  // der AutoSync alle 60 s erneut an und Calls stapeln sich.
  // 25 s statt 15 s: Nextclouds Brute-Force-Protection verzögert nach
  // Fehlversuchen JEDE Antwort derselben IP um bis zu ~30 s — mit dem
  // alten 15-s-Timeout liefen gedrosselte Server reihenweise in den
  // Timeout und die Karten blieben leer (User-Report).
  static const Duration _requestTimeout = Duration(seconds: 25);

  /// Siehe SyncService.lastSyncFailedBoards.
  int _lastSyncFailedBoards = 0;
  @override
  int get lastSyncFailedBoards => _lastSyncFailedBoards;

  SyncServiceImpl({
    required this.baseUrl,
    required this.username,
    required this.password,
    required this.cache,
  });

  @override
  void dispose() {
    _client.close();
  }

  // Simple HTTP helper — mit Wiederholungsversuchen.
  //
  // Hintergrund (User-Report „Boards da, aber keine Karten, nur
  // Ladescreens"): Ein einziger fehlgeschlagener Login-Versuch reicht,
  // damit Nextclouds Brute-Force-Protection alle weiteren Antworten der
  // IP drosselt; auch knappe PHP-Worker bei Shared-Hostern verzögern
  // parallele Requests stark. Ohne Retry starben die Stacks-Calls dann
  // still im Timeout. Jetzt: bis zu 3 Versuche mit Backoff, 429/5xx
  // werden wiederholt, Retry-After wird respektiert.
  Future<http.Response> _get(String endpoint) async {
    final url =
        '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/index.php/apps/deck/api/v1.0$endpoint';
    final uri = Uri.parse(url);
    final headers = {
      'Authorization':
          'Basic ${base64Encode(utf8.encode('$username:$password'))}',
      'OCS-APIRequest': 'true',
      'Accept': 'application/json',
    };
    Object? lastErr;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future.delayed(Duration(seconds: attempt == 1 ? 2 : 5));
      }
      try {
        final res =
            await _client.get(uri, headers: headers).timeout(_requestTimeout);
        // Drosselung/transiente Serverfehler → erneut versuchen
        if (res.statusCode == 429 ||
            res.statusCode == 502 ||
            res.statusCode == 503 ||
            res.statusCode == 504) {
          lastErr = 'HTTP ${res.statusCode}';
          final ra = int.tryParse(res.headers['retry-after'] ?? '');
          if (ra != null && ra > 0 && attempt < 2) {
            await Future.delayed(Duration(seconds: ra > 15 ? 15 : ra));
          }
          continue;
        }
        return res;
      } on TimeoutException catch (e) {
        lastErr = e;
      } catch (e) {
        lastErr = e;
      }
    }
    throw TimeoutException('GET $endpoint failed after retries: $lastErr');
  }

  @override
  Future<void> initSyncOnAppStart() async {
    // Simple: Load all boards, then load all stacks with cards
    await _loadAllBoardsWithStacksAndCards();
  }

  @override
  Future<void> periodicDeltaSync() async {
    // Not used in simple sync
  }

  @override  
  Future<void> refreshUpcoming() async {
    // Simple: Reload all boards, respect 304s
    await _loadAllBoardsWithStacksAndCards();
  }

  @override
  Future<void> ensureBoardFresh(int boardId) async {
    // Simple: Just reload this one board completely
    await _loadSingleBoardWithStacksAndCards(boardId);
  }

  @override
  Future<void> verifyAfterWrite({required int boardId, Set<int> stackIds = const {}}) async {
    await ensureBoardFresh(boardId);
  }

  // NEW SIMPLE SYSTEM BASED ON API DOCS

  /// Load all boards and then all their stacks with cards
  Future<void> _loadAllBoardsWithStacksAndCards() async {
    try {
      // Step 1: Load all boards with details=true to get stacks
      final boardsResponse = await _get('/boards?details=true');
      
      if (boardsResponse.statusCode != 200) {
        return;
      }
      
      final boardsData = jsonDecode(boardsResponse.body) as List;
      final boards = <Map<String, dynamic>>[];
      // Boards, deren Karten nicht im details=true-Response stecken und
      // die einen separaten Stacks-Call brauchen — werden NACH der
      // Schleife PARALLEL geladen (statt wie früher sequenziell).
      final needsStackFetch = <int>[];

      // Step 2: Process each board and its stacks from the boards response.
      // Stabilität: jedes Board hat sein EIGENES try/catch — vorher hat ein
      // einziges Board mit kaputten Daten (oder ein Timeout mittendrin) den
      // Sync ALLER nachfolgenden Boards abgebrochen, inklusive des
      // abschließenden cache.put('boards', ...). Ergebnis war eine halb
      // aktualisierte, inkonsistente App („Synchronisation klappt nicht").
      for (final boardData in boardsData.cast<Map<String, dynamic>>()) {
        try {
        final boardId = boardData['id'] as int;
        // Skip boards marked as deleted (Nextcloud sets deletedAt timestamp)
        final deletedAt = boardData['deletedAt'] ?? boardData['deleted_at'] ?? boardData['deleted_at_utc'];
        if (deletedAt is num && deletedAt.toInt() != 0) {
          cache.delete('columns_$boardId');
          cache.delete('stacks_$boardId');
          cache.delete('board_members_$boardId');
          cache.delete('board_lastmod_$boardId');
          cache.delete('board_lastmod_prev_$boardId');
          continue;
        }
        final boardTitle = boardData['title'] as String;
        
        boards.add({
          'id': boardId,
          'title': boardTitle,
          'archived': boardData['archived'] ?? false,
          if (boardData['color'] != null) 'color': boardData['color'].toString(),
        });
        
        // Use stacks from boards response first (more efficient)
        final stacksData = boardData['stacks'] as List? ?? [];
        final stacks = <Map<String, dynamic>>[];
        final columns = <Map<String, dynamic>>[];
        
        // Check if boards response includes complete stack data with cards.
        // Verschärft: WIRKLICH nur nutzen, wenn ALLE Stacks eine Karten-
        // LISTE tragen — `containsKey('cards')` war zu lasch: bei
        // `cards: null` (je nach Deck-/Serverversion) wurden sonst leere
        // Spalten gecacht und der Nachlade-Pass übersprungen → Boards
        // ohne eine einzige Karte.
        final bool hasCompleteStackData = stacksData.isNotEmpty &&
            stacksData
                .cast<Map<String, dynamic>>()
                .every((s) => s['cards'] is List);
        
        if (hasCompleteStackData) {
          // Use stacks data from boards response (efficient)
          for (final stackData in stacksData.cast<Map<String, dynamic>>()) {
            final stackId = stackData['id'] as int;
            final stackTitle = stackData['title'] as String;
            final stackOrder = stackData['order'] as int?;

            stacks.add({'id': stackId, 'title': stackTitle});

            // Cards are already included in the boards response!
            final cardsData = stackData['cards'] as List? ?? [];
            final cards = <Map<String, dynamic>>[];

            for (final cardData in cardsData.cast<Map<String, dynamic>>()) {
              cards.add(_buildCardCache(cardData));
            }

            columns.add({
              'id': stackId,
              'title': stackTitle,
              'order': stackOrder,
              'cards': cards,
            });
          }
        } else {
          // Fallback nötig: Karten stecken nicht im Boards-Response.
          // Board für den PARALLELEN Nachlade-Pass nach der Schleife
          // vormerken (früher: sequenzieller Einzel-Fetch hier im Loop —
          // bei 15 Boards und trägem Server viele Sekunden Boot-Sync).
          // Cache-Schutz bleibt: _loadSingleBoardWithStacksAndCards fasst
          // den Board-Cache bei Fehlern nicht an.
          needsStackFetch.add(boardId);
          continue;
        }

        // Save stacks and columns for this board
        cache.put('stacks_$boardId', stacks);
        cache.put('columns_$boardId', columns);
        } catch (e) {
          // Board-lokaler Fehler: Cache dieses Boards bleibt auf letztem
          // gutem Stand, die übrigen Boards synchronisieren weiter.
          debugPrint('[sync] board sync failed, keeping cache: $e');
        }
      }

      // Paralleler Nachlade-Pass für Boards ohne eingebettete Karten:
      // Batches à 4 gleichzeitig — schont den Server, ist aber um ein
      // Vielfaches schneller als die alte sequenzielle Kette.
      final failedStacks = <int>{};
      if (needsStackFetch.isNotEmpty) {
        const parallel = 4;
        for (var i = 0; i < needsStackFetch.length; i += parallel) {
          final batch = needsStackFetch.skip(i).take(parallel);
          await Future.wait(batch.map((bId) async {
            try {
              if (!await _loadSingleBoardWithStacksAndCards(bId)) {
                failedStacks.add(bId);
              }
            } catch (e) {
              failedStacks.add(bId);
              debugPrint('[sync] parallel stacks load for $bId failed: $e');
            }
          }));
        }
      }
      // Heil-Pass: gescheiterte Boards nach kurzer Pause SEQUENZIELL
      // nachladen — wenn der Server drosselt (Brute-Force-Protection,
      // knappe PHP-Worker), macht Parallelität es nur schlimmer.
      if (failedStacks.isNotEmpty) {
        await Future.delayed(const Duration(seconds: 3));
        for (final bId in List<int>.of(failedStacks)) {
          try {
            if (await _loadSingleBoardWithStacksAndCards(bId)) {
              failedStacks.remove(bId);
            }
          } catch (_) {}
        }
      }
      _lastSyncFailedBoards = failedStacks.length;
      if (failedStacks.isNotEmpty) {
        debugPrint('[sync] cards still missing for boards: $failedStacks');
      }
      
      // Remove caches for boards that no longer exist (compare previous IDs)
      final previousRaw = cache.get('boards');
      final previousIds = <int>{};
      if (previousRaw is List) {
        for (final b in previousRaw.whereType<Map>()) {
          final id = b['id'];
          if (id is num) previousIds.add(id.toInt());
        }
      }
      final currentIds = boards.map((b) => (b['id'] as num).toInt()).toSet();
      // Save boards to cache
      cache.put('boards', boards);
      for (final rid in previousIds.difference(currentIds)) {
        cache.delete('columns_$rid');
        cache.delete('stacks_$rid');
        cache.delete('board_members_$rid');
        cache.delete('board_lastmod_$rid');
        cache.delete('board_lastmod_prev_$rid');
      }
    } on TimeoutException catch (e) {
      debugPrint('[sync] initSyncOnAppStart timed out: $e');
    } catch (e, st) {
      debugPrint('[sync] initSyncOnAppStart failed: $e\n$st');
    }
  }

  /// Load one board's stacks and cards completely.
  /// Liefert true bei Erfolg (Cache aktualisiert), false wenn der Fetch
  /// scheiterte — der Aufrufer kann dann ehrlich melden statt zu schweigen.
  Future<bool> _loadSingleBoardWithStacksAndCards(int boardId) async {
    try {
      // Use GET /boards/{boardId}/stacks to get stacks WITH cards included!
      final stacksResponse = await _get('/boards/$boardId/stacks');

      if (stacksResponse.statusCode != 200) {
        debugPrint(
            '[sync] stacks for board $boardId -> HTTP ${stacksResponse.statusCode}');
        return false;
      }
      
      final stacksWithCards = jsonDecode(stacksResponse.body) as List;
      final stacks = <Map<String, dynamic>>[];
      final columns = <Map<String, dynamic>>[];
      
      for (final stackData in stacksWithCards.cast<Map<String, dynamic>>()) {
        final stackId = stackData['id'] as int;
        final stackTitle = stackData['title'] as String;
        final stackOrder = stackData['order'] as int?;

        stacks.add({'id': stackId, 'title': stackTitle});

        // Cards are already included in the stacks response!
        final cardsData = stackData['cards'] as List? ?? [];
        final cards = <Map<String, dynamic>>[];

        for (final cardData in cardsData.cast<Map<String, dynamic>>()) {
          cards.add(_buildCardCache(cardData));
        }

        columns.add({
          'id': stackId,
          'title': stackTitle,
          'order': stackOrder,
          'cards': cards,
        });
      }
      
      // Save to cache
      cache.put('stacks_$boardId', stacks);
      cache.put('columns_$boardId', columns);
      return true;
    } on TimeoutException catch (e) {
      debugPrint('[sync] board $boardId refresh timed out: $e');
      return false;
    } catch (e, st) {
      debugPrint('[sync] board $boardId refresh failed: $e\n$st');
      return false;
    }
  }

  int? _parseDueDate(dynamic duedate) {
    if (duedate == null) return null;
    if (duedate is String) {
      try {
        return DateTime.parse(duedate).toUtc().millisecondsSinceEpoch;
      } catch (_) {}
    }
    return null;
  }

  int? _parseDoneDate(dynamic done) {
    if (done == null || done == false) return null;
    if (done is bool) return done ? 0 : null;
    if (done is num) {
      final v = done.toInt();
      return v < 1000000000000 ? v * 1000 : v;
    }
    if (done is String) {
      final trimmed = done.trim();
      if (trimmed.isEmpty || trimmed == '0' || trimmed.toLowerCase() == 'false') {
        return null;
      }
      if (trimmed == '1' || trimmed.toLowerCase() == 'true') return 0;
      try {
        return DateTime.parse(trimmed).toUtc().millisecondsSinceEpoch;
      } catch (_) {}
    }
    return null;
  }

  List<Map<String, dynamic>> _normalizeAssignees(dynamic raw) {
    if (raw is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is Map) {
        Map<String, dynamic> data = item.cast<String, dynamic>();
        final participant = data['participant'];
        if (participant is Map) {
          data = participant.cast<String, dynamic>();
        }
        final id = (data['uid'] ?? data['id'] ?? data['userId'] ?? data['userid'] ?? '').toString();
        final label = (data['displayname'] ?? data['displayName'] ?? data['label'] ?? data['name'] ?? '').toString();
        final displayName = label.isNotEmpty ? label : id;
        if (id.isEmpty && displayName.isEmpty) continue;
        final entry = <String, dynamic>{
          'id': id,
          'displayName': displayName,
        };
        final unique = data['shareWithDisplayNameUnique'] ?? data['unique'];
        if (unique != null && unique.toString().isNotEmpty) {
          entry['unique'] = unique;
        }
        if (data['shareType'] != null) {
          entry['shareType'] = data['shareType'];
        }
        out.add(entry);
      } else if (item is String || item is num) {
        final id = item.toString();
        if (id.isNotEmpty) {
          out.add({'id': id, 'displayName': id});
        }
      }
    }
    return out;
  }

  Map<String, dynamic> _buildCardCache(Map<String, dynamic> cardData) {
    final rawDone = cardData['done'] ?? cardData['doneDate'] ?? cardData['doneAt'];
    final rawAssignees = cardData['assignedUsers'] ?? cardData['assigned'] ?? cardData['members'];
    // Stabilität: alle Felder defensiv lesen. Harte `as`-Casts haben hier
    // früher bei einzelnen Karten mit unerwarteten Werten (null-Titel,
    // Label ohne Farbe, id als String) den Sync des ganzen Boards gekillt.
    return {
      'id': (cardData['id'] as num).toInt(),
      'title': (cardData['title'] ?? '').toString(),
      'description': cardData['description'] ?? '',
      'duedate': _parseDueDate(cardData['duedate']),
      'done': _parseDoneDate(rawDone),
      'order': (cardData['order'] is num)
          ? (cardData['order'] as num).toInt()
          : null,
      'labels': (cardData['labels'] as List? ?? [])
          .whereType<Map>()
          .where((l) => l['id'] is num)
          .map((l) => {
                'id': (l['id'] as num).toInt(),
                'title': (l['title'] ?? '').toString(),
                'color': (l['color'] ?? '999999').toString(),
              })
          .toList(),
      'assignedUsers': _normalizeAssignees(rawAssignees),
    };
  }
}
