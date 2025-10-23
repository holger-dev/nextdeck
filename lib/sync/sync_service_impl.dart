import 'dart:convert';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'sync_service.dart';

class SyncServiceImpl implements SyncService {
  final String baseUrl;
  final String username;
  final String password;
  final Box cache;

  SyncServiceImpl({
    required this.baseUrl,
    required this.username, 
    required this.password,
    required this.cache,
  });

  // Simple HTTP helper
  Future<http.Response> _get(String endpoint) async {
    final url = '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/index.php/apps/deck/api/v1.0$endpoint';
    final uri = Uri.parse(url);
    
    return await http.get(uri, headers: {
      'Authorization': 'Basic ${base64Encode(utf8.encode('$username:$password'))}',
      'OCS-APIRequest': 'true',
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    });
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
      
      // Step 2: Process each board and its stacks from the boards response
      for (final boardData in boardsData.cast<Map<String, dynamic>>()) {
        final boardId = boardData['id'] as int;
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
        
        // Check if boards response includes complete stack data with cards
        bool hasCompleteStackData = false;
        if (stacksData.isNotEmpty) {
          final firstStack = stacksData.first as Map<String, dynamic>?;
          hasCompleteStackData = firstStack?.containsKey('cards') == true;
        }
        
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
              cards.add({
                'id': cardData['id'] as int,
                'title': cardData['title'] as String,
                'description': cardData['description'] ?? '',
                'duedate': _parseDueDate(cardData['duedate']),
                'order': cardData['order'] as int?,
                'labels': (cardData['labels'] as List? ?? [])
                    .cast<Map<String, dynamic>>()
                    .map((l) => {
                          'id': l['id'] as int,
                          'title': l['title'] as String,
                          'color': l['color'] as String,
                        })
                    .toList(),
              });
            }

            columns.add({
              'id': stackId,
              'title': stackTitle,
              'order': stackOrder,
              'cards': cards,
            });
          }
        } else {
          // Fallback: Use separate GET /boards/{boardId}/stacks call
          final stacksResponse = await _get('/boards/$boardId/stacks');

          if (stacksResponse.statusCode == 200) {
            final stacksWithCards = jsonDecode(stacksResponse.body) as List;

            for (final stackData in stacksWithCards.cast<Map<String, dynamic>>()) {
              final stackId = stackData['id'] as int;
              final stackTitle = stackData['title'] as String;
              final stackOrder = stackData['order'] as int?;

              stacks.add({'id': stackId, 'title': stackTitle});

              // Cards are already included in the stacks response!
              final cardsData = stackData['cards'] as List? ?? [];
              final cards = <Map<String, dynamic>>[];

              for (final cardData in cardsData.cast<Map<String, dynamic>>()) {
                cards.add({
                  'id': cardData['id'] as int,
                  'title': cardData['title'] as String,
                  'description': cardData['description'] ?? '',
                  'duedate': _parseDueDate(cardData['duedate']),
                  'order': cardData['order'] as int?,
                  'labels': (cardData['labels'] as List? ?? [])
                      .cast<Map<String, dynamic>>()
                      .map((l) => {
                            'id': l['id'] as int,
                            'title': l['title'] as String,
                            'color': l['color'] as String,
                          })
                      .toList(),
                });
              }

              columns.add({
                'id': stackId,
                'title': stackTitle,
                'order': stackOrder,
                'cards': cards,
              });
            }
          } else {
            // Fallback to stacks from boards response without cards
            for (final stackData in stacksData.cast<Map<String, dynamic>>()) {
              final stackId = stackData['id'] as int;
              final stackTitle = stackData['title'] as String;
              final stackOrder = stackData['order'] as int?;
              stacks.add({'id': stackId, 'title': stackTitle});
              columns.add({
                'id': stackId,
                'title': stackTitle,
                'order': stackOrder,
                'cards': <Map<String, dynamic>>[],
              });
            }
          }
        }
        
        // Save stacks and columns for this board
        cache.put('stacks_$boardId', stacks);
        cache.put('columns_$boardId', columns);
      }
      
      // Save boards to cache
      cache.put('boards', boards);
      
    } catch (e) {
      // Error in initial sync
    }
  }
  
  /// Load one board's stacks and cards completely
  Future<void> _loadSingleBoardWithStacksAndCards(int boardId) async {
    try {
      // Use GET /boards/{boardId}/stacks to get stacks WITH cards included!
      final stacksResponse = await _get('/boards/$boardId/stacks');
      
      if (stacksResponse.statusCode != 200) {
        return;
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
          cards.add({
            'id': cardData['id'] as int,
            'title': cardData['title'] as String,
            'description': cardData['description'] ?? '',
            'duedate': _parseDueDate(cardData['duedate']),
            'order': cardData['order'] as int?,
            'labels': (cardData['labels'] as List? ?? [])
                .cast<Map<String, dynamic>>()
                .map((l) => {
                      'id': l['id'] as int,
                      'title': l['title'] as String,
                      'color': l['color'] as String,
                    })
                .toList(),
          });
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
      
    } catch (e) {
      // Error loading board
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
}
