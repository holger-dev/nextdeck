import 'package:flutter/cupertino.dart';
import 'dart:async';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../models/card_item.dart';
import '../models/board.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import 'card_detail_page.dart';

enum SearchScope { current, all }

class BoardSearchPage extends StatefulWidget {
  final SearchScope initialScope;
  const BoardSearchPage({super.key, this.initialScope = SearchScope.current});
  @override
  State<BoardSearchPage> createState() => _BoardSearchPageState();
}

class _BoardSearchPageState extends State<BoardSearchPage> {
  final TextEditingController _query = TextEditingController();
  List<_SearchHit> _hits = const [];
  bool _loading = false;
  Timer? _debounce;
  late SearchScope _scope;
  // Live progress
  int _searchSeq = 0;
  int _totalBoards = 0;
  int _doneBoards = 0;
  int _totalStacks = 0;
  int _doneStacks = 0;
  String? _currentBoardTitle;
  // Track seen results to avoid duplicates across streaming phases
  Set<String> _seenHitKeys = <String>{};

  String _hitKey(int boardId, int cardId) => '$boardId:$cardId';
  void _addIfNew(List<_SearchHit> res, {required int boardId, required String boardTitle, required int stackId, required String stackTitle, required CardItem card}) {
    if (_seenHitKeys.add(_hitKey(boardId, card.id))) {
      res.add(_SearchHit(boardId: boardId, boardTitle: boardTitle, stackId: stackId, stackTitle: stackTitle, card: card));
    }
  }

  Future<void> _ensureAllCardsLoaded(AppState app) async {
    if (_scope == SearchScope.current) {
      final board = app.activeBoard;
      if (board == null) return;
      final cols = app.columnsForActiveBoard();
      // DISABLED: Use local data only - await Future.wait(cols.map((c) => app.ensureCardsFor(board.id, c.id)));
      return;
    }
    // DISABLED: Use local data only instead of old sync system  
    // for (final b in app.boards.where((x) => !x.archived)) {
    //   await app.refreshColumnsFor(b);
    //   for (final c in app.columnsForBoard(b.id)) {
    //     await app.ensureCardsFor(b.id, c.id);
    //   }
    // }
  }

  Future<void> _doSearch() async {
    final q = _query.text.trim().toLowerCase();
    final app = context.read<AppState>();
    final mySeq = ++_searchSeq; // cancel previous runs when new search starts
    // First: local (already loaded) search for instant feedback
    _seenHitKeys.clear();
    final res = <_SearchHit>[];
    if (_scope == SearchScope.current) {
      final board = app.activeBoard;
      if (board != null) {
        final cols = app.columnsForActiveBoard();
        for (final c in cols) {
          for (final k in c.cards) {
            final inTitle = k.title.toLowerCase().contains(q);
            final inDesc = (k.description ?? '').toLowerCase().contains(q);
            if (q.isEmpty || inTitle || inDesc) {
              _addIfNew(res, boardId: board.id, boardTitle: board.title, stackId: c.id, stackTitle: c.title, card: k);
            }
          }
        }
      }
      setState(() {
        _loading = true;
        _hits = List.of(res);
        _totalBoards = board == null ? 0 : 1;
        _doneBoards = 0;
        _totalStacks = 0; _doneStacks = 0; _currentBoardTitle = null;
      });

      if (board != null) {
        await _expandBoard(app, board.id, board.title, q, res, mySeq);
      }
    } else {
      final boards = app.boards.where((x) => !x.archived).toList();
      for (final b in boards) {
        final cols = app.columnsForBoard(b.id);
        for (final c in cols) {
          for (final k in c.cards) {
            final inTitle = k.title.toLowerCase().contains(q);
            final inDesc = (k.description ?? '').toLowerCase().contains(q);
            if (q.isEmpty || inTitle || inDesc) {
              _addIfNew(res, boardId: b.id, boardTitle: b.title, stackId: c.id, stackTitle: c.title, card: k);
            }
          }
        }
      }
      setState(() {
        _loading = true;
        _hits = List.of(res);
        _totalBoards = boards.length;
        _doneBoards = 0;
        _totalStacks = 0; _doneStacks = 0; _currentBoardTitle = null;
      });
      // Then expand per board to fetch missing stacks/cards and stream new hits
      for (final b in boards) {
        await _expandBoard(app, b.id, b.title, q, res, mySeq);
      }
    }
    if (mySeq != _searchSeq) return; // cancelled
    setState(() { _loading = false; _currentBoardTitle = null; });
  }

  Future<void> _expandBoard(AppState app, int boardId, String boardTitle, String q, List<_SearchHit> res, int mySeq) async {
    if (mySeq != _searchSeq) return;
    // Ensure columns exist for this board (lazy refresh if empty)
    if (app.columnsForBoard(boardId).isEmpty) {
      _currentBoardTitle = boardTitle; _totalStacks = 0; _doneStacks = 0; setState(() {});
      // We need the Board object for refreshColumnsFor; find it by id or construct minimal
      final bObj = app.boards.firstWhere(
        (x) => x.id == boardId,
        orElse: () => Board(id: boardId, title: boardTitle, archived: false),
      );
      // DISABLED: Use local data only - await app.refreshColumnsFor(bObj);
      if (mySeq != _searchSeq) return;
    }
    final cols = app.columnsForBoard(boardId);
    _currentBoardTitle = boardTitle; _totalStacks = cols.length; _doneStacks = 0; setState(() {});
    // First search stacks that already have cards (instant)
    for (final c in cols.where((c) => c.cards.isNotEmpty)) {
      if (mySeq != _searchSeq) return;
      for (final k in c.cards) {
        final inTitle = k.title.toLowerCase().contains(q);
        final inDesc = (k.description ?? '').toLowerCase().contains(q);
        if (q.isEmpty || inTitle || inDesc) {
          _addIfNew(res, boardId: boardId, boardTitle: boardTitle, stackId: c.id, stackTitle: c.title, card: k);
        }
      }
      _doneStacks++;
      setState(() { _hits = List.of(res); });
    }
    // Then ensure and search stacks that are still empty
    final pending = cols.where((c) => c.cards.isEmpty).toList();
    const pool = 4;
    for (int i = 0; i < pending.length; i += pool) {
      if (mySeq != _searchSeq) return;
      final slice = pending.skip(i).take(pool).toList();
      await Future.wait(slice.map((c) async {
        if (mySeq != _searchSeq) return;
        // DISABLED: Use local data only - await app.ensureCardsFor(boardId, c.id);
        if (mySeq != _searchSeq) return;
        final fresh = app.columnsForBoard(boardId).firstWhere((x) => x.id == c.id, orElse: () => c);
        for (final k in fresh.cards) {
          final inTitle = k.title.toLowerCase().contains(q);
          final inDesc = (k.description ?? '').toLowerCase().contains(q);
          if (q.isEmpty || inTitle || inDesc) {
            _addIfNew(res, boardId: boardId, boardTitle: boardTitle, stackId: c.id, stackTitle: c.title, card: k);
          }
        }
        _doneStacks++;
        setState(() { _hits = List.of(res); });
      }));
    }
    _doneBoards++;
    setState(() { _hits = List.of(res); });
  }

  @override
  void initState() {
    super.initState();
    _scope = widget.initialScope;
    _query.addListener(() {
      final q = _query.text.trim();
      _debounce?.cancel();
      if (q.length >= 3) {
        _debounce = Timer(const Duration(milliseconds: 250), () {
          if (mounted) _doSearch();
        });
      } else if (q.isEmpty) {
        setState(() { _hits = const []; });
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final l10n = L10n.of(context);
    final title = _scope == SearchScope.all
        ? l10n.searchAllBoards
        : (app.activeBoard == null ? l10n.search : l10n.searchInBoard(app.activeBoard!.title));
    return CupertinoPageScaffold(
      backgroundColor: AppTheme.appBackground(app),
      navigationBar: CupertinoNavigationBar(middle: Text(title)),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: CupertinoSlidingSegmentedControl<SearchScope>(
                groupValue: _scope,
                children: {
                  SearchScope.current: Padding(padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8), child: Text(l10n.searchScopeCurrent)),
                  SearchScope.all: Padding(padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8), child: Text(l10n.searchScopeAll)),
                },
                onValueChanged: (v) {
                  if (v == null) return;
                  setState(() { _scope = v; _hits = const []; });
                  if (_query.text.trim().length >= 3) _doSearch();
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoTextField(
                      controller: _query,
                      placeholder: l10n.searchPlaceholder,
                      onSubmitted: (_) => _doSearch(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CupertinoButton.filled(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    onPressed: _doSearch,
                    child: const Icon(CupertinoIcons.search),
                  ),
                ],
              ),
            ),
            if (_loading) _ProgressHeader(
              scope: _scope,
              totalBoards: _totalBoards,
              doneBoards: _doneBoards,
              totalStacks: _totalStacks,
              doneStacks: _doneStacks,
              currentBoardTitle: _currentBoardTitle,
            ),
            Expanded(
                child: ListView.builder(
                  itemCount: _hits.length,
                  itemBuilder: (ctx, i) {
                    final h = _hits[i];
                    return CupertinoButton(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                      onPressed: () {
                        Navigator.of(context).push(CupertinoPageRoute(builder: (_) {
                          final app = context.read<AppState>();
                          final cols = app.columnsForBoard(h.boardId);
                          final colIdx = cols.indexWhere((c) => c.id == h.stackId);
                          final bg = AppTheme.cardBg(app, h.card.labels, colIdx < 0 ? 0 : colIdx, 0);
                          return CardDetailPage(cardId: h.card.id, boardId: h.boardId, stackId: h.stackId, bgColor: bg);
                        }));
                      },
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(h.card.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text(_scope == SearchScope.all ? '${h.boardTitle} · ${h.stackTitle}' : h.stackTitle, style: const TextStyle(fontSize: 12, color: CupertinoColors.systemGrey)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SearchHit {
  final int boardId;
  final String boardTitle;
  final int stackId;
  final String stackTitle;
  final CardItem card;
  _SearchHit({required this.boardId, required this.boardTitle, required this.stackId, required this.stackTitle, required this.card});
}

class _ProgressHeader extends StatelessWidget {
  final SearchScope scope;
  final int totalBoards;
  final int doneBoards;
  final int totalStacks;
  final int doneStacks;
  final String? currentBoardTitle;
  const _ProgressHeader({
    required this.scope,
    required this.totalBoards,
    required this.doneBoards,
    required this.totalStacks,
    required this.doneStacks,
    required this.currentBoardTitle,
  });

  @override
  Widget build(BuildContext context) {
    if (scope == SearchScope.current) {
      // Keep it compact for current-board mode
      return const Padding(
        padding: EdgeInsets.only(top: 8.0),
        child: CupertinoActivityIndicator(),
      );
    }
    final boardsFrac = totalBoards <= 0 ? 0.0 : (doneBoards / totalBoards).clamp(0.0, 1.0);
    final stacksFrac = totalStacks <= 0 ? 0.0 : (doneStacks / totalStacks).clamp(0.0, 1.0);
    final l10n = L10n.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CupertinoActivityIndicator(),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  currentBoardTitle == null
                      ? l10n.searchingInProgress
                      : l10n.searchingBoard(currentBoardTitle!),
                  style: const TextStyle(color: CupertinoColors.systemGrey),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _LinearBar(value: boardsFrac, label: l10n.boardsProgress(doneBoards, totalBoards)),
          const SizedBox(height: 6),
          _LinearBar(value: stacksFrac, label: l10n.listsProgress(doneStacks, totalStacks)),
        ],
      ),
    );
  }
}

class _LinearBar extends StatelessWidget {
  final double value; // 0..1
  final String label;
  const _LinearBar({required this.value, required this.label});
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, cns) {
        final w = cns.maxWidth;
        final filled = (w * value).clamp(0.0, w);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(height: 6, width: w, decoration: BoxDecoration(color: CupertinoColors.systemGrey4, borderRadius: BorderRadius.circular(4))),
                Container(height: 6, width: filled, decoration: BoxDecoration(color: CupertinoColors.activeBlue, borderRadius: BorderRadius.circular(4))),
              ],
            ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12, color: CupertinoColors.systemGrey)),
          ],
        );
      },
    );
  }
}
