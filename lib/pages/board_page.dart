import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart'
    show ReorderableListView, ReorderableDragStartListener;
import 'dart:async';
import 'dart:math' as math;

import '../state/app_state.dart';
import '../models/column.dart' as deck;
import 'card_detail_page.dart';
import '../models/label.dart';
import '../models/card_item.dart';
import '../models/user_ref.dart';
import 'board_search_page.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';

const TextStyle _destructiveActionTextStyle =
    TextStyle(color: CupertinoColors.white);

class BoardPage extends StatefulWidget {
  const BoardPage({super.key});

  @override
  State<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends State<BoardPage> with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  double _page = 0;
  int? _lastBoardId;
  late final AnimationController _spinCtrl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Kein Netz-Refresh hier: Daten kommen aus dem einmaligen Global-Fetch (details=true)
  }

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _pageController.addListener(() {
      setState(() {
        _page = _pageController.hasClients ? (_pageController.page ?? 0) : 0;
      });
    });
  }

  @override
  void dispose() {
    _spinCtrl.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final board = app.activeBoard;
    final columns = app.columnsForActiveBoard();
    if (board != null && app.boardArchivedOnly) {
      final archived = app.archivedCardsForBoard(board.id);
      if (archived.isEmpty && !app.isArchivedCardsLoading(board.id)) {
        app.refreshArchivedCardsForBoard(board.id);
      }
    }

    final isTablet = MediaQuery.of(context).size.shortestSide >= 600;
    // Reset to first column when board changes
    if (board?.id != _lastBoardId) {
      _lastBoardId = board?.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients) {
          _pageController.jumpToPage(0);
          setState(() => _page = 0);
        }
      });
    }
    return CupertinoPageScaffold(
      backgroundColor: AppTheme.appBackground(app),
      navigationBar: CupertinoNavigationBar(
        backgroundColor: CupertinoColors.transparent,
        border: null,
        leading: (board == null)
            ? null
            : Builder(builder: (context) {
                final boards = app.boards;
                final idx = boards.indexWhere((b) => b.id == board.id);
                final ncColor = (idx >= 0 && idx < boards.length)
                    ? boards[idx].color
                    : null;
                final base = AppTheme.boardColorFrom(ncColor) ??
                    AppTheme.boardStrongColor(idx < 0 ? 0 : idx);
                final topColor = app.isDarkMode
                    ? AppTheme.blend(base, const Color(0xFF000000), 0.25)
                    : AppTheme.blend(base, const Color(0xFF000000), 0.15);
                final txtColor = app.isDarkMode
                    ? AppTheme.textOn(topColor)
                    : CupertinoColors.black;
                return CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    Navigator.of(context).push(CupertinoPageRoute(
                        builder: (_) => const BoardSearchPage()));
                  },
                  child: Icon(CupertinoIcons.search, size: 18, color: txtColor),
                );
              }),
        middle: (board == null)
            ? const SizedBox.shrink()
            : Builder(builder: (context) {
                final boards = app.boards;
                final idx = boards.indexWhere((b) => b.id == board.id);
                final ncColor = (idx >= 0 && idx < boards.length)
                    ? boards[idx].color
                    : null;
                final base = AppTheme.boardColorFrom(ncColor) ??
                    AppTheme.boardStrongColor(idx < 0 ? 0 : idx);
                // Use the same color as header gradient top for contrast decision
                final topColor = app.isDarkMode
                    ? AppTheme.blend(base, const Color(0xFF000000), 0.25)
                    : AppTheme.blend(base, const Color(0xFF000000), 0.15);
                // In Light Mode we want black text regardless of computed contrast
                final txtColor = app.isDarkMode
                    ? AppTheme.textOn(topColor)
                    : CupertinoColors.black;
                // Truncate very long titles: if > 20 chars, cut at 18 and append '...'
                final String displayTitle = () {
                  final t = board.title;
                  if (t.length > 20) {
                    return t.substring(0, 18) + '...';
                  }
                  return t;
                }();
                return SizedBox(
                  width: double.infinity,
                  child: Row(
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      Container(
                        width: 16,
                        height: 6,
                        decoration: BoxDecoration(
                          color: topColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.w700, color: txtColor),
                        ),
                      ),
                    ],
                  ),
                );
              }),
        trailing: (board == null)
            ? null
            : Builder(builder: (context) {
                final boards = app.boards;
                final idx = boards.indexWhere((b) => b.id == board.id);
                final ncColor = (idx >= 0 && idx < boards.length)
                    ? boards[idx].color
                    : null;
                final base = AppTheme.boardColorFrom(ncColor) ??
                    AppTheme.boardStrongColor(idx < 0 ? 0 : idx);
                // Force black icon in Light Mode for readability
                final txtColor = app.isDarkMode
                    ? AppTheme.textOn(base)
                    : CupertinoColors.black;
                final isTablet =
                    MediaQuery.of(context).size.shortestSide >= 600;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isTablet)
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () async {
                          final cols = app.columnsForActiveBoard();
                          if (cols.isEmpty) return;
                          await showCupertinoModalPopup(
                            context: context,
                            builder: (ctx) => CupertinoActionSheet(
                              title: Text(L10n.of(context).selectColumn),
                              actions: cols
                                  .asMap()
                                  .entries
                                  .map((e) => CupertinoActionSheetAction(
                                        onPressed: () {
                                          Navigator.of(ctx).pop();
                                          final target = e.key;
                                          if (_pageController.hasClients) {
                                            _pageController.animateToPage(
                                                target,
                                                duration: const Duration(
                                                    milliseconds: 220),
                                                curve: Curves.easeOut);
                                          }
                                        },
                                        child: Text(e.value.title),
                                      ))
                                  .toList(),
                              cancelButton: CupertinoActionSheetAction(
                                onPressed: () => Navigator.of(ctx).pop(),
                                isDefaultAction: true,
                                child: Text(L10n.of(context).cancel),
                              ),
                            ),
                          );
                        },
                        child: Icon(CupertinoIcons.list_bullet,
                            size: 22, color: txtColor),
                      ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        app.setUpcomingAssignedOnly(
                            !app.upcomingAssignedOnly);
                      },
                      child: Icon(
                          app.upcomingAssignedOnly
                              ? CupertinoIcons.person_fill
                              : CupertinoIcons.person,
                          size: 22,
                          color: txtColor),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        final next = !app.boardArchivedOnly;
                        app.setBoardArchivedOnly(next);
                        final boardId = app.activeBoard?.id;
                        if (next && boardId != null) {
                          app.refreshArchivedCardsForBoard(boardId);
                        }
                      },
                      child: Icon(
                          app.boardArchivedOnly
                              ? CupertinoIcons.archivebox_fill
                              : CupertinoIcons.archivebox,
                          size: 22,
                          color: txtColor),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: app.isSyncing
                          ? null
                          : () async {
                              await app.runWithSyncing(() async {
                                final b = app.activeBoard;
                                if (b != null) {
                                  await app.refreshBoards(forceNetwork: true);
                                  // Use new sync system instead of old refreshColumnsFor
                                  await app.refreshSingleBoard(b.id);
                                }
                              });
                            },
                      child: (app.isSyncing)
                          ? const CupertinoActivityIndicator()
                          : const Icon(CupertinoIcons.refresh),
                    ),
                    // Add-list button removed for v1; planned for v2.0
                  ],
                );
              }),
      ),
      child: Stack(
        children: [
          // Gradient under transparent navbar
          if (board != null) ...[
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Builder(builder: (context) {
                final topPad = MediaQuery.of(context).padding.top;
                final boards = app.boards;
                final idx = boards.indexWhere((b) => b.id == board.id);
                final ncColor = (idx >= 0 && idx < boards.length)
                    ? boards[idx].color
                    : null;
                final base = AppTheme.boardColorFrom(ncColor) ??
                    AppTheme.boardStrongColor(idx < 0 ? 0 : idx);
                final topColor = app.isDarkMode
                    ? AppTheme.blend(base, const Color(0xFF000000), 0.25)
                    : AppTheme.blend(base, const Color(0xFF000000), 0.15);
                final bottomColor = base;
                return Container(
                  height: topPad + 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [topColor, bottomColor],
                    ),
                  ),
                );
              }),
            ),
            // Title row now provided by navigationBar.middle; keep only gradient background
          ],
          SafeArea(
            top: true,
            child: Stack(
              children: [
                if (board == null)
                  Center(child: Text(L10n.of(context).pleaseSelectBoard))
                else if ((app.bootSyncing && columns.isEmpty) ||
                    (columns.isEmpty && (app.lastError == null)))
                  const Center(child: CupertinoActivityIndicator())
                else if (app.lastError != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text(
                        app.lastError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: CupertinoColors.destructiveRed),
                      ),
                    ),
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final mq = MediaQuery.of(context);
                      final isTablet =
                          mq.size.shortestSide >= 600; // iPad/tablet heuristic
                      final isWide = constraints.maxWidth >= 900 || isTablet;
                      if (isWide) {
                        return _WideColumnsView(
                            columns: columns,
                            boardId: board.id,
                            onCreateCard: (colId) async {
                              await _showCreateCard(context, board.id, colId);
                            });
                      }
                      // Preload neighbors for smoother swiping
                      _preloadNeighbors(
                          context, board.id, columns, _page.round());
                      return PageView.builder(
                        controller: _pageController,
                        itemCount: columns.length,
                        itemBuilder: (context, index) => _ColumnView(
                          column: columns[index],
                          columnIndex: index,
                          requestPrevPage: () {
                            final target =
                                (_pageController.page ?? 0).floor() - 1;
                            if (target >= 0) {
                              _pageController.animateToPage(target,
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOut);
                            }
                          },
                          requestNextPage: () {
                            final target =
                                (_pageController.page ?? 0).ceil() + 1;
                            if (target < columns.length) {
                              _pageController.animateToPage(target,
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOut);
                            }
                          },
                          onTapCard: (cardId) {
                            final app = context.read<AppState>();
                            final stack = columns[index];
                            final archived = app.archivedCardsForBoard(board.id)[stack.id] ?? const <CardItem>[];
                            final list = app.boardArchivedOnly ? archived : stack.cards;
                            if (list.isEmpty) return;
                            final card = list.firstWhere(
                              (c) => c.id == cardId,
                              orElse: () => list.first,
                            );
                            final colIdx = index;
                            final cardIdx = list.indexOf(card);
                            final bg = AppTheme.cardBg(
                                app, card.labels, colIdx, cardIdx);
                            Navigator.of(context).push(
                              CupertinoPageRoute(
                                builder: (_) => CardDetailPage(
                                  cardId: cardId,
                                  boardId: board.id,
                                  stackId: stack.id,
                                  bgColor: bg,
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                if (board != null &&
                    columns.isNotEmpty &&
                    !(MediaQuery.of(context).size.width >= 900 || isTablet))
                  _EdgeIndicators(
                      currentPage: _page,
                      total: columns.length,
                      onPrev: () {
                        final target = (_pageController.page ?? 0).floor() - 1;
                        if (target >= 0) {
                          _pageController.animateToPage(target,
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOut);
                        }
                      },
                      onNext: () {
                        final target = (_pageController.page ?? 0).ceil() + 1;
                        if (target < columns.length) {
                          _pageController.animateToPage(target,
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOut);
                        }
                      }),
                if (!isTablet)
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: CupertinoButton.filled(
                      padding: const EdgeInsets.all(12),
                      child: const Icon(CupertinoIcons.add),
                      onPressed: () async {
                        if (board == null || columns.isEmpty) return;
                        final currentPage = _pageController.hasClients
                            ? _pageController.page?.round() ?? 0
                            : 0;
                        final columnId = columns[currentPage].id;
                        await _showCreateCard(context, board.id, columnId);
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateCard(
      BuildContext context, int boardId, int columnId) async {
    final titleCtrl = TextEditingController();
    final app = context.read<AppState>();
    // Einheitliche Bottom-Sheet UI für Phone und iPad, Titel im Content für volle Sichtbarkeit
    await showCupertinoModalPopup(
      context: context,
      builder: (sheetCtx) {
        // Derive card base color from target column for contrast-aware text in the field
        final cols = app.columnsForActiveBoard();
        final colIdx = cols.indexWhere((c) => c.id == columnId);
        final baseForCards = app.smartColors && colIdx >= 0
            ? AppTheme.preferredColumnColor(app, cols[colIdx].title, colIdx)
            : (CupertinoTheme.of(sheetCtx).brightness == Brightness.dark
                ? CupertinoColors.systemGrey5
                : CupertinoColors.systemGrey6);
        final tileBg = AppTheme.cardBgFromBase(app, const [], baseForCards, 0);
        final inputColor = AppTheme.textOn(tileBg);
        return AnimatedPadding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: CupertinoActionSheet(
            message: StatefulBuilder(
              builder: (ctx, setS) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 80),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        L10n.of(ctx).newCard,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 10),
                      CupertinoTextField(
                        controller: titleCtrl,
                        placeholder: L10n.of(ctx).title,
                        autofocus: true,
                        style: TextStyle(color: inputColor),
                        placeholderStyle:
                            TextStyle(color: inputColor.withOpacity(0.6)),
                        cursorColor: inputColor,
                        decoration: BoxDecoration(
                          color: tileBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        onChanged: (_) => setS(() {}),
                        onSubmitted: (v) async {
                          final t = v.trim();
                          if (t.isEmpty) return;
                          Navigator.of(sheetCtx).pop();
                          await app.createCard(
                              boardId: boardId, columnId: columnId, title: t);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              CupertinoActionSheetAction(
                onPressed: () async {
                  final t = titleCtrl.text.trim();
                  Navigator.of(sheetCtx).pop();
                  if (t.isEmpty) return;
                  await app.createCard(
                      boardId: boardId, columnId: columnId, title: t);
                },
                child: Text(L10n.of(sheetCtx).create),
              ),
            ],
            cancelButton: CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetCtx).pop(),
              isDefaultAction: true,
              child: Text(L10n.of(sheetCtx).cancel),
            ),
          ),
        );
      },
    );
  }
}

class _ColumnView extends StatefulWidget {
  final deck.Column column;
  final int columnIndex;
  final ValueChanged<int>? onTapCard;
  final VoidCallback? requestPrevPage;
  final VoidCallback? requestNextPage;
  const _ColumnView(
      {required this.column,
      required this.columnIndex,
      this.onTapCard,
      this.requestPrevPage,
      this.requestNextPage});

  @override
  State<_ColumnView> createState() => _ColumnViewState();
}

class _ColumnViewState extends State<_ColumnView> {
  bool _requested = false;
  bool _hover = false;
  final ScrollController _listCtrl = ScrollController();
  DateTime? _edgeLastNav;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppState>();
    final board = app.activeBoard;
    // Keine per-Stack Karten-Nachläufe mehr; wir verlassen uns auf details=true
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final col = app.columnsForActiveBoard().firstWhere(
        (c) => c.id == widget.column.id,
        orElse: () => widget.column);
    final isLoading = app.isStackLoading(widget.column.id);
    final boardId = app.activeBoard?.id;
    final showArchivedOnly = app.boardArchivedOnly;
    final archivedByStack = boardId == null
        ? const <int, List<CardItem>>{}
        : app.archivedCardsForBoard(boardId);
    final archivedCards = archivedByStack[col.id] ?? const <CardItem>[];
    final isArchivedLoading =
        boardId != null && app.isArchivedCardsLoading(boardId);
    final isTablet = MediaQuery.of(context).size.shortestSide >= 600;
    final Color containerBg = () {
      if (!app.smartColors) {
        return CupertinoTheme.of(context).brightness == Brightness.dark
            ? CupertinoColors.black
            : CupertinoColors.systemGrey6;
      }
      final baseCol =
          AppTheme.preferredColumnColor(app, col.title, widget.columnIndex);
      return app.isDarkMode
          ? AppTheme.blend(baseCol, const Color(0xFF000000), 0.75)
          : AppTheme.blend(baseCol, const Color(0xFFFFFFFF), 0.55);
    }();
    final baseForCards = app.smartColors
        ? AppTheme.preferredColumnColor(app, col.title, widget.columnIndex)
        : (CupertinoTheme.of(context).brightness == Brightness.dark
            ? CupertinoColors.systemGrey5
            : CupertinoColors.systemGrey6);
    final filterAssigned = app.upcomingAssignedOnly;
    final sourceCards = showArchivedOnly ? archivedCards : col.cards;
    final cards = sourceCards
        .where((c) => showArchivedOnly ? true : !c.archived)
        .where((c) => !filterAssigned || app.shouldIncludeAssignedCard(c))
        .toList();
    final showArchivedLoading = showArchivedOnly &&
        isArchivedLoading &&
        archivedByStack.isEmpty;

    Future<void> _handleAccept(_DragCard d) async {
      final app = context.read<AppState>();
      final boardId = app.activeBoard?.id;
      if (boardId == null) return;
      app.updateLocalCard(
          boardId: boardId,
          stackId: d.fromStackId,
          cardId: d.cardId,
          moveToStackId: widget.column.id);
      CardItem? cur;
      for (final x in app.columnsForActiveBoard()) {
        final hit = x.cards.where((c) => c.id == d.cardId).toList();
        if (hit.isNotEmpty) {
          cur = hit.first;
          break;
        }
      }
      final patch = <String, dynamic>{
        'stackId': widget.column.id,
        'title': cur?.title ?? d.title,
        if (cur?.description != null) 'description': cur!.description,
        if (cur?.due != null) 'duedate': cur!.due!.toUtc().toIso8601String(),
        if (cur != null && cur!.labels.isNotEmpty)
          'labels': cur!.labels.map((l) => l.id).toList(),
        if (cur != null && cur!.assignees.isNotEmpty)
          'assignedUsers': cur!.assignees.map((u) => u.id).toList(),
      };
      try {
        await app.updateCardAndRefresh(
            boardId: boardId,
            stackId: d.fromStackId,
            cardId: d.cardId,
            patch: patch);
        await app.syncStackOrder(boardId: boardId, stackId: widget.column.id);
        if (d.fromStackId != widget.column.id) {
          await app.syncStackOrder(boardId: boardId, stackId: d.fromStackId);
        }
      } catch (_) {}
    }

    Widget header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Center(
          child: Text(col.title,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
    );

    if (isTablet) {
      if (filterAssigned) {
        return Container(
          decoration: BoxDecoration(color: containerBg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              Expanded(
                child: (isLoading && cards.isNotEmpty)
                    ? const Center(child: CupertinoActivityIndicator())
                    : (showArchivedLoading && cards.isEmpty)
                        ? const Center(child: CupertinoActivityIndicator())
                        : CupertinoScrollbar(
                            controller: _listCtrl.hasClients ? _listCtrl : null,
                            child: ListView.builder(
                              controller: _listCtrl,
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                              itemCount: cards.length,
                              itemBuilder: (context, idx) {
                                final card = cards[idx];
                                final bg = AppTheme.cardBgFromBase(
                                    app, card.labels, baseForCards, idx);
                                return Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 6),
                                  child: _CardTile(
                                    title: card.title,
                                    subtitle: _markdownPreviewLine(
                                        card.description ?? ''),
                                    labels: card.labels,
                                    assignees: card.assignees,
                                    onTap: widget.onTapCard == null
                                        ? null
                                        : () => widget.onTapCard!(card.id),
                                    background: bg,
                                    due: card.due,
                                    done: card.done,
                                    footer: _CardMetaRow(
                                        boardId: app.activeBoard?.id,
                                        stackId: widget.column.id,
                                        cardId: card.id,
                                        textColor: AppTheme.textOn(bg),
                                        description: card.description),
                                  ),
                                );
                              },
                            ),
                          ),
              ),
            ],
          ),
        );
      }
      return DragTarget<_DragCard>(
        onWillAccept: (d) {
          final ok = d != null && d.fromStackId != widget.column.id;
          if (ok) setState(() => _hover = true);
          return ok;
        },
        onLeave: (_) => setState(() => _hover = false),
        onAccept: (d) async {
          setState(() => _hover = false);
          await _handleAccept(d);
        },
        builder: (ctx, cand, rej) => Container(
          decoration: BoxDecoration(
              color: containerBg,
              border: _hover
                  ? Border.all(color: CupertinoColors.activeBlue, width: 2)
                  : null),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              Expanded(
                child: (isLoading && cards.isNotEmpty)
                    ? const Center(child: CupertinoActivityIndicator())
                    : CupertinoScrollbar(
                        controller: _listCtrl.hasClients ? _listCtrl : null,
                        child: ListView.builder(
                          controller: _listCtrl,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                          primary: false,
                          itemCount: cards.length,
                          itemBuilder: (context, idx) {
                            final card = cards[idx];
                            final bg = AppTheme.cardBgFromBase(
                                app, card.labels, baseForCards, idx);
                            Widget buildInsertTarget(int insertIndex) {
                              return DragTarget<_DragCard>(
                                onWillAccept: (d) =>
                                    d != null &&
                                    d.fromStackId != widget.column.id,
                                onAccept: (d) async {
                                  final app = context.read<AppState>();
                                  final boardId = app.activeBoard?.id;
                                  if (boardId == null) return;
                                  app.updateLocalCard(
                                      boardId: boardId,
                                      stackId: d.fromStackId,
                                      cardId: d.cardId,
                                      moveToStackId: widget.column.id,
                                      insertIndex: insertIndex);
                                  CardItem? cur;
                                  for (final x in app.columnsForActiveBoard()) {
                                    final hit = x.cards
                                        .where((c) => c.id == d.cardId)
                                        .toList();
                                    if (hit.isNotEmpty) {
                                      cur = hit.first;
                                      break;
                                    }
                                  }
                                  final patch = <String, dynamic>{
                                    'stackId': widget.column.id,
                                    'order': insertIndex + 1,
                                    'title': cur?.title ?? d.title,
                                    if (cur?.description != null)
                                      'description': cur!.description,
                                    if (cur?.due != null)
                                      'duedate':
                                          cur!.due!.toUtc().toIso8601String(),
                                    if (cur != null && cur!.labels.isNotEmpty)
                                      'labels':
                                          cur!.labels.map((l) => l.id).toList(),
                                    if (cur != null &&
                                        cur!.assignees.isNotEmpty)
                                      'assignedUsers': cur!.assignees
                                          .map((u) => u.id)
                                          .toList(),
                                  };
                                  try {
                                    await app.updateCardAndRefresh(
                                        boardId: boardId,
                                        stackId: d.fromStackId,
                                        cardId: d.cardId,
                                        patch: patch);
                                    await app.syncStackOrder(
                                        boardId: boardId,
                                        stackId: widget.column.id);
                                    if (d.fromStackId != widget.column.id) {
                                      await app.syncStackOrder(
                                          boardId: boardId,
                                          stackId: d.fromStackId);
                                    }
                                  } catch (_) {}
                                },
                                builder: (ctx, cand, rej) => Container(
                                  height: 10,
                                  margin: const EdgeInsets.only(bottom: 6),
                                  decoration: BoxDecoration(
                                    color: cand.isNotEmpty
                                        ? CupertinoColors.activeBlue
                                            .withOpacity(0.25)
                                        : CupertinoColors.transparent,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              );
                            }

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  buildInsertTarget(idx),
                                  _CardDragWrapper(
                                    data: _DragCard(
                                        cardId: card.id,
                                        fromStackId: widget.column.id,
                                        title: card.title),
                                    feedback: ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxWidth: 300),
                                      child: Opacity(
                                        opacity: 0.95,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: bg,
                                            borderRadius:
                                                BorderRadius.circular(14),
                                            boxShadow: [
                                              BoxShadow(
                                                  color: CupertinoColors.black
                                                      .withOpacity(0.2),
                                                  blurRadius: 12,
                                                  offset: const Offset(0, 6))
                                            ],
                                            border: Border.all(
                                                color: CupertinoColors.separator
                                                    .withOpacity(0.6)),
                                          ),
                                          padding: const EdgeInsets.all(12),
                                          child: Text(card.title,
                                              style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppTheme.textOn(bg))),
                                        ),
                                      ),
                                    ),
                                    childWhenDragging: Opacity(
                                      opacity: 0.4,
                                      child: _CardTile(
                                        title: card.title,
                                        subtitle: _markdownPreviewLine(
                                            card.description ?? ''),
                                        labels: card.labels,
                                        assignees: card.assignees,
                                        onTap: null,
                                        background: bg,
                                        due: card.due,
                                        done: card.done,
                                        footer: _CardMetaRow(
                                            boardId: app.activeBoard?.id,
                                            stackId: widget.column.id,
                                            cardId: card.id,
                                            textColor: AppTheme.textOn(bg),
                                            description: card.description),
                                      ),
                                    ),
                                    child: GestureDetector(
                                      onLongPress: () async {
                                        final l10n = L10n.of(context);
                                        final rootNav = Navigator.of(context,
                                            rootNavigator: true);
                                        await showCupertinoModalPopup(
                                          context: rootNav.context,
                                          builder: (ctx) =>
                                              CupertinoActionSheet(
                                            actions: [
                                              ...() {
                                                final items = <Widget>[];
                                                final app =
                                                    context.read<AppState>();
                                                final boardId =
                                                    app.activeBoard?.id;
                                                final isDone =
                                                    card.done != null;
                                                if (!isDone) {
                                                  items.add(
                                                      CupertinoActionSheetAction(
                                                    onPressed: () async {
                                                      Navigator.of(ctx).pop();
                                                      if (boardId == null)
                                                        return;
                                                      final doneAt =
                                                          DateTime.now()
                                                              .toUtc();
                                                      app.updateLocalCard(
                                                          boardId: boardId,
                                                          stackId:
                                                              widget.column.id,
                                                          cardId: card.id,
                                                          done: doneAt);
                                                      final base = app.baseUrl;
                                                      final user = app.username;
                                                      final pass = await app
                                                          .storage
                                                          .read(
                                                              key: 'password');
                                                      if (base != null &&
                                                          user != null &&
                                                          pass != null) {
                                                        try {
                                                          await app
                                                              .updateCardAndRefresh(
                                                                  boardId:
                                                                      boardId,
                                                                  stackId: widget
                                                                      .column
                                                                      .id,
                                                                  cardId: card.id,
                                                                  patch: {
                                                                'title':
                                                                    card.title,
                                                                'done': doneAt,
                                                              });
                                                        } catch (_) {}
                                                      }
                                                    },
                                                    child: Text(l10n.markDone),
                                                  ));
                                                } else {
                                                  // Mark as undone: move to first non-done column (left-most)
                                                  items.add(
                                                      CupertinoActionSheetAction(
                                                    onPressed: () async {
                                                      Navigator.of(ctx).pop();
                                                      if (boardId == null)
                                                        return;
                                                      app.updateLocalCard(
                                                          boardId: boardId,
                                                          stackId:
                                                              widget.column.id,
                                                          cardId: card.id,
                                                          clearDone: true);
                                                      final base = app.baseUrl;
                                                      final user = app.username;
                                                      final pass = await app
                                                          .storage
                                                          .read(
                                                              key: 'password');
                                                      if (base != null &&
                                                          user != null &&
                                                          pass != null) {
                                                        try {
                                                          await app
                                                              .updateCardAndRefresh(
                                                                  boardId:
                                                                      boardId,
                                                                  stackId: widget
                                                                      .column
                                                                      .id,
                                                                  cardId: card.id,
                                                                  patch: {
                                                                'title':
                                                                    card.title,
                                                                'done': null,
                                                              });
                                                        } catch (_) {}
                                                      }
                                                    },
                                                    child:
                                                        Text(l10n.markUndone),
                                                  ));
                                                }
                                                return items;
                                              }(),
                                              CupertinoActionSheetAction(
                                                isDestructiveAction: true,
                                                onPressed: () async {
                                                  Navigator.of(ctx).pop();
                                                  final app =
                                                      context.read<AppState>();
                                                  final bId =
                                                      app.activeBoard?.id;
                                                  if (bId == null) return;
                                                  final confirmed =
                                                      await showCupertinoDialog<
                                                          bool>(
                                                    context: rootNav.context,
                                                    builder: (dCtx) =>
                                                        CupertinoAlertDialog(
                                                      title:
                                                          Text(l10n.deleteCard),
                                                      content: Text(l10n
                                                          .confirmDeleteCard),
                                                      actions: [
                                                        CupertinoDialogAction(
                                                            onPressed: () =>
                                                                Navigator.of(
                                                                        dCtx)
                                                                    .pop(false),
                                                            child: Text(
                                                                l10n.cancel)),
                                                        CupertinoDialogAction(
                                                          isDestructiveAction:
                                                              true,
                                                          onPressed: () =>
                                                              Navigator.of(dCtx)
                                                                  .pop(true),
                                                          child: Text(
                                                              l10n.delete,
                                                              style:
                                                                  _destructiveActionTextStyle),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                  if (confirmed == true) {
                                                    await context
                                                        .read<AppState>()
                                                        .deleteCard(
                                                            boardId: bId,
                                                            stackId: widget
                                                                .column.id,
                                                            cardId: card.id);
                                                  }
                                                },
                                                child: Text(l10n.deleteCard,
                                                    style:
                                                        _destructiveActionTextStyle),
                                              ),
                                            ],
                                            cancelButton:
                                                CupertinoActionSheetAction(
                                                    onPressed: () =>
                                                        Navigator.of(ctx).pop(),
                                                    isDefaultAction: true,
                                                    child: Text(l10n.cancel)),
                                          ),
                                        );
                                      },
                                      child: _CardTile(
                                        title: card.title,
                                        subtitle: _markdownPreviewLine(
                                            card.description ?? ''),
                                        labels: card.labels,
                                        assignees: card.assignees,
                                        onTap: widget.onTapCard == null
                                            ? null
                                            : () => widget.onTapCard!(card.id),
                                        background: bg,
                                        due: card.due,
                                        done: card.done,
                                        footer: _CardMetaRow(
                                            boardId: app.activeBoard?.id,
                                            stackId: widget.column.id,
                                            cardId: card.id,
                                            textColor: AppTheme.textOn(bg),
                                            description: card.description),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      );
    }

    // Phone
    if (filterAssigned) {
      return Container(
        decoration: BoxDecoration(color: containerBg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            Expanded(
                child: (isLoading && cards.isNotEmpty)
                    ? const Center(child: CupertinoActivityIndicator())
                    : (showArchivedLoading && cards.isEmpty)
                        ? const Center(child: CupertinoActivityIndicator())
                        : CupertinoScrollbar(
                            controller: _listCtrl.hasClients ? _listCtrl : null,
                            child: ListView.builder(
                              controller: _listCtrl,
                              padding:
                                  const EdgeInsets.fromLTRB(16, 8, 16, 80),
                              itemCount: cards.length,
                              itemBuilder: (context, idx) {
                                final card = cards[idx];
                                final bg = AppTheme.cardBgFromBase(
                                    app, card.labels, baseForCards, idx);
                                return Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 6),
                                  child: _CardTile(
                                    title: card.title,
                                    subtitle: _markdownPreviewLine(
                                        card.description ?? ''),
                                    labels: card.labels,
                                    assignees: card.assignees,
                                    onTap: widget.onTapCard == null
                                        ? null
                                        : () => widget.onTapCard!(card.id),
                                    background: bg,
                                    due: card.due,
                                    done: card.done,
                                    footer: _CardMetaRow(
                                        boardId: app.activeBoard?.id,
                                        stackId: widget.column.id,
                                        cardId: card.id,
                                        textColor: AppTheme.textOn(bg),
                                        description: card.description),
                                  ),
                                );
                              },
                            ),
                          ),
            ),
          ],
        ),
      );
    }
    return DragTarget<_DragCard>(
      onWillAccept: (d) {
        final ok = d != null && d.fromStackId != widget.column.id;
        if (ok) setState(() => _hover = true);
        return ok;
      },
      onLeave: (_) => setState(() => _hover = false),
      onAccept: (d) async {
        setState(() => _hover = false);
        await _handleAccept(d);
      },
      builder: (ctx, cand, rej) => Container(
        decoration: BoxDecoration(
            color: containerBg,
            border: _hover
                ? Border.all(color: CupertinoColors.activeBlue, width: 2)
                : null),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            Expanded(
              child: (isLoading && cards.isNotEmpty)
                  ? const Center(child: CupertinoActivityIndicator())
                  : (showArchivedLoading && cards.isEmpty)
                      ? const Center(child: CupertinoActivityIndicator())
                      : CupertinoScrollbar(
                          controller: _listCtrl.hasClients ? _listCtrl : null,
                          child: ReorderableListView.builder(
                            buildDefaultDragHandles: false,
                            padding:
                                const EdgeInsets.fromLTRB(16, 8, 16, 80),
                            itemCount: cards.length,
                            onReorder: (oldIndex, newIndex) async {
                              if (showArchivedOnly) return;
                              final app = context.read<AppState>();
                              final boardId = app.activeBoard?.id;
                              if (boardId == null) return;
                              if (newIndex > oldIndex) newIndex -= 1;
                              final movedCard = cards[oldIndex];
                              final cardId = movedCard.id;
                              app.reorderCardLocal(
                                  boardId: boardId,
                                  stackId: widget.column.id,
                                  cardId: cardId,
                                  newIndex: newIndex);
                              await app.syncStackOrder(
                                  boardId: boardId, stackId: widget.column.id);
                            },
                            itemBuilder: (context, idx) {
                              final card = cards[idx];
                              final bg = AppTheme.cardBgFromBase(
                                  app, card.labels, baseForCards, idx);
                              final key = ValueKey('card_${card.id}');
                              Widget buildInsertTarget(int insertIndex) {
                                return DragTarget<_DragCard>(
                                  onWillAccept: (d) =>
                                      d != null &&
                                      d.fromStackId != widget.column.id,
                                  onAccept: (d) async {
                                    final app = context.read<AppState>();
                                    final boardId = app.activeBoard?.id;
                                    if (boardId == null) return;
                                    app.updateLocalCard(
                                        boardId: boardId,
                                        stackId: d.fromStackId,
                                        cardId: d.cardId,
                                        moveToStackId: widget.column.id,
                                        insertIndex: insertIndex);
                                    CardItem? cur;
                                    for (final x in app.columnsForActiveBoard()) {
                                      final hit = x.cards
                                          .where((c) => c.id == d.cardId)
                                          .toList();
                                      if (hit.isNotEmpty) {
                                        cur = hit.first;
                                        break;
                                      }
                                    }
                                    final patch = <String, dynamic>{
                                      'stackId': widget.column.id,
                                      'order': insertIndex + 1,
                                      'title': cur?.title ?? d.title,
                                      if (cur?.description != null)
                                        'description': cur!.description,
                                      if (cur?.due != null)
                                        'duedate': cur!.due!
                                            .toUtc()
                                            .toIso8601String(),
                                      if (cur != null && cur!.labels.isNotEmpty)
                                        'labels': cur!.labels
                                            .map((l) => l.id)
                                            .toList(),
                                      if (cur != null &&
                                          cur!.assignees.isNotEmpty)
                                        'assignedUsers': cur!.assignees
                                            .map((u) => u.id)
                                            .toList(),
                                    };
                                    try {
                                      await app.updateCardAndRefresh(
                                          boardId: boardId,
                                          stackId: d.fromStackId,
                                          cardId: d.cardId,
                                          patch: patch);
                                      await app.syncStackOrder(
                                          boardId: boardId,
                                          stackId: widget.column.id);
                                      if (d.fromStackId != widget.column.id) {
                                        await app.syncStackOrder(
                                            boardId: boardId,
                                            stackId: d.fromStackId);
                                      }
                                    } catch (_) {}
                                  },
                                  builder: (ctx, cand, rej) => Container(
                                    height: 10,
                                    margin: const EdgeInsets.only(bottom: 6),
                                    decoration: BoxDecoration(
                                      color: cand.isNotEmpty
                                          ? CupertinoColors.activeBlue
                                              .withOpacity(0.25)
                                          : CupertinoColors.transparent,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                );
                              }

                          return Padding(
                            key: key,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                buildInsertTarget(idx),
                                Stack(
                                  children: [
                                    _CardDragWrapper(
                                      data: _DragCard(
                                          cardId: card.id,
                                          fromStackId: widget.column.id,
                                          title: card.title),
                                      feedback: ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 300),
                                        child: Opacity(
                                          opacity: 0.95,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: bg,
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              boxShadow: [
                                                BoxShadow(
                                                    color: CupertinoColors.black
                                                        .withOpacity(0.2),
                                                    blurRadius: 12,
                                                    offset: const Offset(0, 6))
                                              ],
                                              border: Border.all(
                                                  color: CupertinoColors
                                                      .separator
                                                      .withOpacity(0.6)),
                                            ),
                                            padding: const EdgeInsets.all(12),
                                            child: Text(card.title,
                                                style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w700,
                                                    color:
                                                        AppTheme.textOn(bg))),
                                          ),
                                        ),
                                      ),
                                      childWhenDragging: Opacity(
                                        opacity: 0.4,
                                        child: _CardTile(
                                          title: card.title,
                                          subtitle: _markdownPreviewLine(
                                              card.description ?? ''),
                                          labels: card.labels,
                                          assignees: card.assignees,
                                          onTap: null,
                                          background: bg,
                                          due: card.due,
                                          done: card.done,
                                          footer: _CardMetaRow(
                                              boardId: app.activeBoard?.id,
                                              stackId: widget.column.id,
                                              cardId: card.id,
                                              textColor: AppTheme.textOn(bg),
                                              description: card.description),
                                        ),
                                      ),
                                      onDragUpdate: (details) {
                                        final now = DateTime.now();
                                        if (_edgeLastNav != null &&
                                            now
                                                    .difference(_edgeLastNav!)
                                                    .inMilliseconds <
                                                350) return;
                                        final w =
                                            MediaQuery.of(context).size.width;
                                        final x = details.globalPosition.dx;
                                        if (x <= 24) {
                                          widget.requestPrevPage?.call();
                                          _edgeLastNav = now;
                                        } else if (x >= w - 24) {
                                          widget.requestNextPage?.call();
                                          _edgeLastNav = now;
                                        }
                                      },
                                      child: _CardTile(
                                        title: card.title,
                                        subtitle: _markdownPreviewLine(
                                            card.description ?? ''),
                                        labels: card.labels,
                                        assignees: card.assignees,
                                        onTap: widget.onTapCard == null
                                            ? null
                                            : () => widget.onTapCard!(card.id),
                                        background: bg,
                                        due: card.due,
                                        done: card.done,
                                        footer: _CardMetaRow(
                                            boardId: app.activeBoard?.id,
                                            stackId: widget.column.id,
                                            cardId: card.id,
                                            textColor: AppTheme.textOn(bg),
                                            description: card.description),
                                        onMore: () async {
                                          final l10n = L10n.of(context);
                                          final rootNav = Navigator.of(context,
                                              rootNavigator: true);
                                          await showCupertinoModalPopup(
                                            context: rootNav.context,
                                            builder: (ctx) =>
                                                CupertinoActionSheet(
                                              actions: [
                                                ...() {
                                                  final app =
                                                      context.read<AppState>();
                                                  final isDone =
                                                      card.done != null;
                                                  if (!isDone) {
                                                    return [
                                                      CupertinoActionSheetAction(
                                                        onPressed: () async {
                                                          Navigator.of(ctx)
                                                              .pop();
                                                          final boardId = app
                                                              .activeBoard?.id;
                                                          if (boardId == null)
                                                            return;
                                                          final doneAt =
                                                              DateTime.now()
                                                                  .toUtc();
                                                          app.updateLocalCard(
                                                              boardId: boardId,
                                                              stackId: widget
                                                                  .column.id,
                                                              cardId: card.id,
                                                              done: doneAt);
                                                          final base =
                                                              app.baseUrl;
                                                          final user =
                                                              app.username;
                                                          final pass = await app
                                                              .storage
                                                              .read(
                                                                  key:
                                                                      'password');
                                                          if (base != null &&
                                                              user != null &&
                                                              pass != null) {
                                                            try {
                                                              await app.updateCardAndRefresh(
                                                                  boardId:
                                                                      boardId,
                                                                  stackId: widget
                                                                      .column
                                                                      .id,
                                                                  cardId: card.id,
                                                                  patch: {
                                                                    'title': card
                                                                        .title,
                                                                    'done':
                                                                        doneAt,
                                                                  });
                                                            } catch (_) {}
                                                          }
                                                        },
                                                        child:
                                                            Text(l10n.markDone),
                                                      ),
                                                    ];
                                                  } else {
                                                    return [
                                                      CupertinoActionSheetAction(
                                                        onPressed: () async {
                                                          Navigator.of(ctx)
                                                              .pop();
                                                          final boardId = app
                                                              .activeBoard?.id;
                                                          if (boardId == null)
                                                            return;
                                                          app.updateLocalCard(
                                                              boardId: boardId,
                                                              stackId: widget
                                                                  .column.id,
                                                              cardId: card.id,
                                                              clearDone: true);
                                                          final base =
                                                              app.baseUrl;
                                                          final user =
                                                              app.username;
                                                          final pass = await app
                                                              .storage
                                                              .read(
                                                                  key:
                                                                      'password');
                                                          if (base != null &&
                                                              user != null &&
                                                              pass != null) {
                                                            try {
                                                              await app.updateCardAndRefresh(
                                                                  boardId:
                                                                      boardId,
                                                                  stackId: widget
                                                                      .column
                                                                      .id,
                                                                  cardId: card.id,
                                                                  patch: {
                                                                    'title': card
                                                                        .title,
                                                                    'done': null,
                                                                  });
                                                            } catch (_) {}
                                                          }
                                                        },
                                                        child: Text(
                                                            l10n.markUndone),
                                                      ),
                                                    ];
                                                  }
                                                }(),
                                                CupertinoActionSheetAction(
                                                  isDestructiveAction: true,
                                                  onPressed: () async {
                                                    Navigator.of(ctx).pop();
                                                    final app = context
                                                        .read<AppState>();
                                                    final bId =
                                                        app.activeBoard?.id;
                                                    if (bId == null) return;
                                                    final confirmed =
                                                        await showCupertinoDialog<
                                                            bool>(
                                                      context: rootNav.context,
                                                      builder: (dCtx) =>
                                                          CupertinoAlertDialog(
                                                        title: Text(
                                                            l10n.deleteCard),
                                                        content: Text(l10n
                                                            .confirmDeleteCard),
                                                        actions: [
                                                          CupertinoDialogAction(
                                                              onPressed: () =>
                                                                  Navigator.of(
                                                                          dCtx)
                                                                      .pop(
                                                                          false),
                                                              child: Text(
                                                                  l10n.cancel)),
                                                          CupertinoDialogAction(
                                                            isDestructiveAction:
                                                                true,
                                                            onPressed: () =>
                                                                Navigator.of(
                                                                        dCtx)
                                                                    .pop(true),
                                                            child: Text(
                                                                l10n.delete,
                                                                style:
                                                                    _destructiveActionTextStyle),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                    if (confirmed == true) {
                                                      await context
                                                          .read<AppState>()
                                                          .deleteCard(
                                                              boardId: bId,
                                                              stackId: widget
                                                                  .column.id,
                                                              cardId: card.id);
                                                    }
                                                  },
                                                  child: Text(l10n.deleteCard,
                                                      style:
                                                          _destructiveActionTextStyle),
                                                ),
                                              ],
                                              cancelButton:
                                                  CupertinoActionSheetAction(
                                                      onPressed: () =>
                                                          Navigator.of(ctx)
                                                              .pop(),
                                                      isDefaultAction: true,
                                                      child: Text(l10n.cancel)),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    Positioned(
                                      right: 6,
                                      top: 6,
                                      child: ReorderableDragStartListener(
                                        index: idx,
                                        child: const Icon(
                                            CupertinoIcons.arrow_up_arrow_down,
                                            size: 18,
                                            color: CupertinoColors.systemGrey),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _listCtrl.dispose();
    super.dispose();
  }
}

class _CardTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Color background;
  final List<Label> labels;
  final List<UserRef> assignees;
  final DateTime? due;
  final DateTime? done;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final Widget? footer;
  final VoidCallback? onMore;
  const _CardTile(
      {required this.title,
      this.subtitle,
      this.onTap,
      required this.background,
      this.labels = const [],
      this.assignees = const [],
      this.due,
      this.done,
      this.onMoveUp,
      this.onMoveDown,
      this.footer,
      this.onMore});

  String _assigneesText() {
    final names = assignees
        .map((u) => u.displayName.isNotEmpty ? u.displayName : u.id)
        .where((n) => n.isNotEmpty)
        .toList();
    if (names.isEmpty) return '';
    if (names.length <= 2) return names.join(', ');
    final remaining = names.length - 2;
    return '${names.take(2).join(', ')} +$remaining';
  }

  @override
  Widget build(BuildContext context) {
    final textColor = AppTheme.textOn(background);
    final assigneesText = _assigneesText();
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: CupertinoColors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: CupertinoColors.separator.withOpacity(0.6)),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: textColor),
                  ),
                ),
                if (done != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6, top: 2),
                    child: Icon(
                      CupertinoIcons.checkmark_seal_fill,
                      size: 18,
                      color: CupertinoColors.systemGreen,
                    ),
                  ),
                if (onMore != null)
                  CupertinoButton(
                    padding: const EdgeInsets.all(4),
                    minSize: 26,
                    onPressed: onMore,
                    child: Icon(CupertinoIcons.ellipsis,
                        size: 18, color: textColor.withOpacity(0.9)),
                  ),
                // Reserve space for external drag handle so icons don't overlap
                const SizedBox(width: 22),
              ],
            ),
            if (labels.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.start,
                children: labels.map((l) => _LabelChip(label: l)).toList(),
              ),
            ],
            if (subtitle != null && subtitle!.isNotEmpty)
              Builder(builder: (context) {
                final app = context.watch<AppState>();
                if (app.showDescriptionText) {
                  final s = subtitle!;
                  final trimmed =
                      s.length > 200 ? (s.substring(0, 200) + '…') : s;
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      trimmed,
                      style: TextStyle(
                          color: textColor.withOpacity(0.85), fontSize: 14),
                    ),
                  );
                } else {
                  return const SizedBox.shrink();
                }
              }),
            if (assigneesText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Icon(CupertinoIcons.person,
                        size: 14, color: textColor.withOpacity(0.9)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        assigneesText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: textColor.withOpacity(0.9)),
                      ),
                    ),
                  ],
                ),
              ),
            if (due != null)
              Builder(builder: (context) {
                final now = DateTime.now();
                final isOverdue = due!.isBefore(now);
                final hoursTo = due!.difference(now).inHours;
                final Color dueColor = isOverdue
                    ? CupertinoColors.systemRed
                    : (hoursTo <= 24
                        ? CupertinoColors.activeOrange
                        : textColor.withOpacity(0.98));
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Icon(CupertinoIcons.time, size: 14, color: dueColor),
                      const SizedBox(width: 4),
                      Text(
                        _formatDue(due!),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          fontStyle: FontStyle.normal,
                          color: dueColor,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            if (footer != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: footer!,
              ),
            if (onMoveUp != null || onMoveDown != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (onMoveUp != null)
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        onPressed: onMoveUp,
                        child: Icon(CupertinoIcons.chevron_up,
                            size: 16, color: textColor.withOpacity(0.9)),
                      ),
                    if (onMoveDown != null)
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        onPressed: onMoveDown,
                        child: Icon(CupertinoIcons.chevron_down,
                            size: 16, color: textColor.withOpacity(0.9)),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DragCard {
  final int cardId;
  final int fromStackId;
  final String title;
  _DragCard(
      {required this.cardId, required this.fromStackId, required this.title});
}

class _CardDragWrapper extends StatelessWidget {
  final _DragCard data;
  final Widget child;
  final Widget feedback;
  final Widget? childWhenDragging;
  final void Function(DragUpdateDetails)? onDragUpdate;
  const _CardDragWrapper(
      {required this.data,
      required this.child,
      required this.feedback,
      this.childWhenDragging,
      this.onDragUpdate});

  @override
  Widget build(BuildContext context) {
    // Auf Tablet: sofortiges Dragging; auf Phone: LongPress, um Scrollen/Reorder nicht zu stören
    final isTablet = MediaQuery.of(context).size.shortestSide >= 600;
    if (!isTablet) {
      return LongPressDraggable<_DragCard>(
        data: data,
        feedback: feedback,
        child: child,
        childWhenDragging: childWhenDragging,
        onDragUpdate: onDragUpdate,
        axis: Axis.horizontal,
      );
    }
    return Draggable<_DragCard>(
      data: data,
      feedback: feedback,
      child: child,
      childWhenDragging: childWhenDragging,
      onDragUpdate: onDragUpdate,
      axis: Axis.horizontal,
    );
  }
}

// Meta-Chips (Kommentare/Anhänge)
class _CardMetaRow extends StatefulWidget {
  final int? boardId;
  final int stackId;
  final int cardId;
  final Color textColor;
  final String? description;
  const _CardMetaRow(
      {required this.boardId,
      required this.stackId,
      required this.cardId,
      required this.textColor,
      this.description});

  @override
  State<_CardMetaRow> createState() => _CardMetaRowState();
}

class _CardMetaRowState extends State<_CardMetaRow> {
  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Do not auto-fetch per-card meta here to avoid many requests.
    // We only display counts if already available in cache/state.
    _requested = true;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cc = app.commentsCountFor(widget.cardId);
    final ac = app.attachmentsCountFor(widget.cardId);
    final hasDescription = widget.description?.isNotEmpty ?? false;
    final taskCount = _parseTaskCount(widget.description);
    if (!hasDescription &&
        taskCount == null &&
        (cc == null || cc == 0) &&
        (ac == null || ac == 0)) return const SizedBox.shrink();
    final tc = widget.textColor.withOpacity(0.95);
    const iconSize = 18.0;
    final items = <Widget>[];
    void addItem(Widget w) {
      if (items.isNotEmpty) items.add(const SizedBox(width: 8));
      items.add(w);
    }

    if (hasDescription) {
      addItem(Icon(CupertinoIcons.text_justify, size: iconSize, color: tc));
    }
    if (taskCount != null) {
      addItem(Row(
        children: [
          Icon(CupertinoIcons.checkmark_square, size: iconSize, color: tc),
          const SizedBox(width: 4),
          Text('${taskCount.done}/${taskCount.total}',
              style: TextStyle(
                  fontSize: 12, color: tc, fontWeight: FontWeight.w600)),
        ],
      ));
    }
    if (cc != null && cc > 0) {
      addItem(Row(
        children: [
          Icon(CupertinoIcons.text_bubble, size: iconSize, color: tc),
          const SizedBox(width: 4),
          Text('$cc',
              style: TextStyle(
                  fontSize: 12, color: tc, fontWeight: FontWeight.w600)),
        ],
      ));
    }
    if (ac != null && ac > 0) {
      addItem(Row(
        children: [
          Icon(CupertinoIcons.paperclip, size: iconSize, color: tc),
          const SizedBox(width: 4),
          Text('$ac',
              style: TextStyle(
                  fontSize: 12, color: tc, fontWeight: FontWeight.w600)),
        ],
      ));
    }
    return Row(children: items);
  }
}

class _TaskCount {
  final int done;
  final int total;
  const _TaskCount(this.done, this.total);
}

_TaskCount? _parseTaskCount(String? description) {
  if (description == null || description.isEmpty) return null;
  final re = RegExp(r'^\s*[-*+] \[( |x|X)\] ', multiLine: true);
  var done = 0;
  var total = 0;
  for (final m in re.allMatches(description)) {
    total += 1;
    final mark = (m.group(1) ?? '').toLowerCase();
    if (mark == 'x') done += 1;
  }
  if (total == 0) return null;
  return _TaskCount(done, total);
}

extension<T> on List<T> {
  T? elementAtOrNull(int index) =>
      (index < 0 || index >= length) ? null : this[index];
}

class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      color: CupertinoColors.separator,
    );
  }
}

class _WideColumnsView extends StatefulWidget {
  final List<deck.Column> columns;
  final ValueChanged<int> onCreateCard;
  final int boardId;
  const _WideColumnsView(
      {required this.columns,
      required this.onCreateCard,
      required this.boardId});

  @override
  State<_WideColumnsView> createState() => _WideColumnsViewState();
}

class _WideColumnsViewState extends State<_WideColumnsView> {
  final ScrollController _ctrl = ScrollController();
  bool _showLeft = false;
  bool _showRight = false;
  final Map<int, ScrollController> _listCtrls = {};
  final Map<int, bool> _hoverCol = {};

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_updateIndicators);
    // delay to allow layout, then compute indicators
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateIndicators());
  }

  void _updateIndicators() {
    if (!_ctrl.hasClients) return;
    final max = _ctrl.position.maxScrollExtent;
    final off = _ctrl.offset;
    final l = off > 8;
    final r = (max - off) > 8;
    if (l != _showLeft || r != _showRight) {
      setState(() {
        _showLeft = l;
        _showRight = r;
      });
    }
  }

  void _scrollBy(double delta) {
    if (!_ctrl.hasClients) return;
    final target =
        (_ctrl.offset + delta).clamp(0.0, _ctrl.position.maxScrollExtent);
    _ctrl.animateTo(target,
        duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  ScrollController _ctrlFor(int columnId) =>
      _listCtrls.putIfAbsent(columnId, () => ScrollController());

  @override
  void dispose() {
    for (final c in _listCtrls.values) {
      c.dispose();
    }
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    const colWidth = 360.0; // slightly narrower columns for better fit
    final showArchivedOnly = app.boardArchivedOnly;
    final archivedByStack = showArchivedOnly
        ? app.archivedCardsForBoard(widget.boardId)
        : const <int, List<CardItem>>{};
    final showArchivedLoading = showArchivedOnly &&
        app.isArchivedCardsLoading(widget.boardId) &&
        archivedByStack.isEmpty;
    return Stack(
      children: [
        SingleChildScrollView(
          controller: _ctrl,
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(width: 12),
              for (final c in widget.columns) ...[
                Builder(builder: (context) {
                  final visibleCards = showArchivedOnly
                      ? (archivedByStack[c.id] ?? const <CardItem>[])
                      : c.cards.where((card) => !card.archived).toList();
                  return SizedBox(
                    width: colWidth,
                    child: DragTarget<_DragCard>(
                      onWillAccept: (d) {
                        final ok = d != null && d.fromStackId != c.id;
                        if (ok) setState(() => _hoverCol[c.id] = true);
                        return ok;
                      },
                      onLeave: (_) => setState(() => _hoverCol[c.id] = false),
                      onAccept: (d) async {
                        setState(() => _hoverCol[c.id] = false);
                        final app = context.read<AppState>();
                        final boardId = widget.boardId;
                        app.updateLocalCard(
                            boardId: boardId,
                            stackId: d.fromStackId,
                            cardId: d.cardId,
                            moveToStackId: c.id);
                        // Build full patch with existing fields to avoid losing data
                        CardItem? current;
                        for (final col in app.columnsForActiveBoard()) {
                          final hit = col.cards
                              .where((cc) => cc.id == d.cardId)
                              .toList();
                          if (hit.isNotEmpty) {
                            current = hit.first;
                            break;
                          }
                        }
                        final patch = <String, dynamic>{
                          'stackId': c.id,
                          'title': current?.title ?? d.title,
                          if (current?.description != null)
                            'description': current!.description,
                          if (current?.due != null)
                            'duedate': current!.due!.toUtc().toIso8601String(),
                          if (current != null && current!.labels.isNotEmpty)
                            'labels': current!.labels.map((l) => l.id).toList(),
                          if (current != null && current!.assignees.isNotEmpty)
                            'assignedUsers':
                                current!.assignees.map((u) => u.id).toList(),
                        };
                        final baseUrl = app.baseUrl;
                        final user = app.username;
                        final pass = await app.storage.read(key: 'password');
                        if (baseUrl != null && user != null && pass != null) {
                          try {
                            await app.updateCardAndRefresh(
                                boardId: boardId,
                                stackId: d.fromStackId,
                                cardId: d.cardId,
                                patch: patch);
                          } catch (_) {}
                        }
                      },
                      builder: (ctx, cand, rej) => Container(
                        color: () {
                          if (!app.smartColors) {
                            return CupertinoTheme.of(context).brightness ==
                                    Brightness.dark
                                ? CupertinoColors.black
                                : CupertinoColors.systemGrey6;
                          }
                          final base = AppTheme.preferredColumnColor(
                              app, c.title, widget.columns.indexOf(c));
                          return app.isDarkMode
                              ? AppTheme.blend(
                                  base, const Color(0xFF000000), 0.75)
                              : AppTheme.blend(
                                  base, const Color(0xFFFFFFFF), 0.55);
                        }(),
                        foregroundDecoration: (_hoverCol[c.id] ?? false)
                            ? BoxDecoration(
                                border: Border.all(
                                    color: CupertinoColors.activeBlue,
                                    width: 2))
                            : null,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 16, 8, 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(c.title,
                                        style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600)),
                                  ),
                                  CupertinoButton(
                                    padding: EdgeInsets.zero,
                                    onPressed: () => widget.onCreateCard(c.id),
                                    child: const Icon(
                                        CupertinoIcons.add_circled, size: 24),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: showArchivedLoading
                                  ? const Center(
                                      child: CupertinoActivityIndicator())
                                  : CupertinoScrollbar(
                                      controller: _ctrlFor(c.id).hasClients
                                          ? _ctrlFor(c.id)
                                          : null,
                                      child: ReorderableListView.builder(
                                        key: ValueKey('reorder_${c.id}'),
                                        buildDefaultDragHandles: false,
                                        padding: const EdgeInsets.fromLTRB(
                                            16, 8, 16, 32),
                                        itemCount: visibleCards.length,
                                        onReorder: (oldIndex, newIndex) async {
                                          if (showArchivedOnly) return;
                                          final app = context.read<AppState>();
                                          final boardId = widget.boardId;
                                          if (newIndex > oldIndex)
                                            newIndex -= 1;
                                          final movedCard =
                                              visibleCards[oldIndex];
                                          final cardId = movedCard.id;
                                          app.reorderCardLocal(
                                              boardId: boardId,
                                              stackId: c.id,
                                              cardId: cardId,
                                              newIndex: newIndex);
                                          await app.syncStackOrder(
                                              boardId: boardId, stackId: c.id);
                                        },
                                        itemBuilder: (context, idx) {
                                          final card = visibleCards[idx];
                                          final base = app.smartColors
                                              ? AppTheme.preferredColumnColor(
                                                  app,
                                                  c.title,
                                                  widget.columns.indexOf(c))
                                              : (CupertinoTheme.of(context)
                                                          .brightness ==
                                                      Brightness.dark
                                                  ? CupertinoColors.systemGrey5
                                                  : CupertinoColors
                                                      .systemGrey6);
                                          final tileBg = AppTheme.cardBgFromBase(
                                              app, card.labels, base, idx);
                                          final textOn =
                                              AppTheme.textOn(tileBg);
                                          Widget buildInsertTarget(
                                              int insertIndex) {
                                            return DragTarget<_DragCard>(
                                              onWillAccept: (d) =>
                                                  d != null &&
                                                  d.fromStackId != c.id,
                                              onAccept: (d) async {
                                                final app =
                                                    context.read<AppState>();
                                                final boardId = widget.boardId;
                                                app.updateLocalCard(
                                                    boardId: boardId,
                                                    stackId: d.fromStackId,
                                                    cardId: d.cardId,
                                                    moveToStackId: c.id,
                                                    insertIndex: insertIndex);
                                                CardItem? current;
                                                for (final col in app
                                                    .columnsForActiveBoard()) {
                                                  final hit = col.cards
                                                      .where((cc) =>
                                                          cc.id == d.cardId)
                                                      .toList();
                                                  if (hit.isNotEmpty) {
                                                    current = hit.first;
                                                    break;
                                                  }
                                                }
                                                final patch = <String, dynamic>{
                                                  'stackId': c.id,
                                                  'order': insertIndex + 1,
                                                  'title':
                                                      current?.title ?? d.title,
                                                  if (current?.description !=
                                                      null)
                                                    'description':
                                                        current!.description,
                                                  if (current?.due != null)
                                                    'duedate': current!.due!
                                                        .toUtc()
                                                        .toIso8601String(),
                                                  if (current != null &&
                                                      current!.labels
                                                          .isNotEmpty)
                                                    'labels': current!.labels
                                                        .map((l) => l.id)
                                                        .toList(),
                                                  if (current != null &&
                                                      current!
                                                          .assignees.isNotEmpty)
                                                    'assignedUsers': current!
                                                        .assignees
                                                        .map((u) => u.id)
                                                        .toList(),
                                                };
                                                try {
                                                  await app.updateCardAndRefresh(
                                                      boardId: boardId,
                                                      stackId: d.fromStackId,
                                                      cardId: d.cardId,
                                                      patch: patch);
                                                  await app.syncStackOrder(
                                                      boardId: boardId,
                                                      stackId: c.id);
                                                  if (d.fromStackId != c.id) {
                                                    await app.syncStackOrder(
                                                        boardId: boardId,
                                                        stackId: d.fromStackId);
                                                  }
                                                } catch (_) {}
                                              },
                                              builder: (ctx, cand, rej) =>
                                                  Container(
                                                height: 10,
                                                margin: const EdgeInsets.only(
                                                    bottom: 6),
                                                decoration: BoxDecoration(
                                                  color: cand.isNotEmpty
                                                      ? CupertinoColors
                                                          .activeBlue
                                                          .withOpacity(0.25)
                                                      : CupertinoColors
                                                          .transparent,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                              ),
                                            );
                                          }

                                          return Padding(
                                            key: ValueKey(card.id),
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 6),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                buildInsertTarget(idx),
                                                Stack(
                                                  children: [
                                                    _CardDragWrapper(
                                                      data: _DragCard(
                                                          cardId: card.id,
                                                          fromStackId: c.id,
                                                          title: card.title),
                                                      feedback: ConstrainedBox(
                                                        constraints:
                                                            const BoxConstraints(
                                                                maxWidth: 300),
                                                        child: Opacity(
                                                          opacity: 0.95,
                                                          child: Container(
                                                            decoration:
                                                                BoxDecoration(
                                                              color: tileBg,
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          14),
                                                              boxShadow: [
                                                                BoxShadow(
                                                                    color: CupertinoColors
                                                                        .black
                                                                        .withOpacity(
                                                                            0.2),
                                                                    blurRadius:
                                                                        12,
                                                                    offset:
                                                                        const Offset(
                                                                            0, 6))
                                                              ],
                                                              border: Border.all(
                                                                  color: CupertinoColors
                                                                      .separator
                                                                      .withOpacity(
                                                                          0.6)),
                                                            ),
                                                            padding:
                                                                const EdgeInsets
                                                                    .all(12),
                                                            child: Text(
                                                                card.title,
                                                                style: TextStyle(
                                                                    fontSize: 16,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700,
                                                                    color:
                                                                        textOn)),
                                                          ),
                                                        ),
                                                      ),
                                                      child: _CardTile(
                                                        title: card.title,
                                                        subtitle:
                                                            _markdownPreviewLine(
                                                                card.description ??
                                                                    ''),
                                                        labels: card.labels,
                                                        assignees:
                                                            card.assignees,
                                                        onTap: () => Navigator
                                                                .of(context)
                                                            .push(
                                                                CupertinoPageRoute(
                                                          builder: (_) =>
                                                              CardDetailPage(
                                                                  cardId:
                                                                      card.id,
                                                                  boardId:
                                                                      widget
                                                                          .boardId,
                                                                  stackId: c.id,
                                                                  bgColor:
                                                                      tileBg),
                                                        )),
                                                        background: tileBg,
                                                        due: card.due,
                                                        done: card.done,
                                                        footer: _CardMetaRow(
                                                            boardId:
                                                                widget.boardId,
                                                            stackId: c.id,
                                                            cardId: card.id,
                                                            textColor: textOn,
                                                            description: card
                                                                .description),
                                                        onMore: () async {
                                                          final l10n =
                                                              L10n.of(context);
                                                          final rootNav =
                                                              Navigator.of(
                                                                  context,
                                                                  rootNavigator:
                                                                      true);
                                                          await showCupertinoModalPopup(
                                                            context:
                                                                rootNav.context,
                                                            builder: (ctx) =>
                                                                CupertinoActionSheet(
                                                              actions: [
                                                                if (card.done ==
                                                                    null)
                                                                  CupertinoActionSheetAction(
                                                                    onPressed:
                                                                        () async {
                                                                      Navigator.of(
                                                                              ctx)
                                                                          .pop();
                                                                      final doneAt =
                                                                          DateTime.now()
                                                                              .toUtc();
                                                                      final app =
                                                                          context.read<AppState>();
                                                                      app.updateLocalCard(
                                                                          boardId:
                                                                              widget.boardId,
                                                                          stackId: c
                                                                              .id,
                                                                          cardId: card
                                                                              .id,
                                                                          done: doneAt);
                                                                      final base =
                                                                          app.baseUrl;
                                                                      final user =
                                                                          app.username;
                                                                      final pass = await app
                                                                          .storage
                                                                          .read(
                                                                              key:
                                                                                  'password');
                                                                      if (base != null &&
                                                                          user !=
                                                                              null &&
                                                                          pass !=
                                                                              null) {
                                                                        try {
                                                                          await app.updateCardAndRefresh(
                                                                              boardId:
                                                                                  widget.boardId,
                                                                              stackId: c.id,
                                                                              cardId: card.id,
                                                                              patch: {
                                                                                'title': card.title,
                                                                                'done': doneAt,
                                                                              });
                                                                        } catch (_) {}
                                                                      }
                                                                    },
                                                                    child: Text(
                                                                        l10n.markDone),
                                                                  )
                                                                else
                                                                  CupertinoActionSheetAction(
                                                                    onPressed:
                                                                        () async {
                                                                      Navigator.of(
                                                                              ctx)
                                                                          .pop();
                                                                      final app =
                                                                          context.read<AppState>();
                                                                      app.updateLocalCard(
                                                                          boardId:
                                                                              widget.boardId,
                                                                          stackId: c
                                                                              .id,
                                                                          cardId: card
                                                                              .id,
                                                                          clearDone:
                                                                              true);
                                                                      final base =
                                                                          app.baseUrl;
                                                                      final user =
                                                                          app.username;
                                                                      final pass = await app
                                                                          .storage
                                                                          .read(
                                                                              key:
                                                                                  'password');
                                                                      if (base != null &&
                                                                          user !=
                                                                              null &&
                                                                          pass !=
                                                                              null) {
                                                                        try {
                                                                          await app.updateCardAndRefresh(
                                                                              boardId:
                                                                                  widget.boardId,
                                                                              stackId: c.id,
                                                                              cardId: card.id,
                                                                              patch: {
                                                                                'title': card.title,
                                                                                'done': null,
                                                                              });
                                                                        } catch (_) {}
                                                                      }
                                                                    },
                                                                    child: Text(
                                                                        l10n.markUndone),
                                                                  ),
                                                                CupertinoActionSheetAction(
                                                                  isDestructiveAction:
                                                                      true,
                                                                  onPressed:
                                                                      () async {
                                                                    Navigator.of(
                                                                            ctx)
                                                                        .pop();
                                                                    final confirmed =
                                                                        await showCupertinoDialog<
                                                                            bool>(
                                                                      context:
                                                                          context,
                                                                      builder:
                                                                          (dCtx) =>
                                                                              CupertinoAlertDialog(
                                                                        title: Text(
                                                                            l10n.deleteCard),
                                                                        content:
                                                                            Text(l10n.confirmDeleteCard),
                                                                        actions: [
                                                                          CupertinoDialogAction(
                                                                              onPressed: () => Navigator.of(dCtx).pop(false),
                                                                              child: Text(l10n.cancel)),
                                                                          CupertinoDialogAction(
                                                                            isDestructiveAction:
                                                                                true,
                                                                            onPressed: () =>
                                                                                Navigator.of(dCtx).pop(true),
                                                                            child:
                                                                                Text(l10n.delete, style: _destructiveActionTextStyle),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                    );
                                                                    if (confirmed ==
                                                                        true) {
                                                                      await context.read<AppState>().deleteCard(
                                                                          boardId: widget
                                                                              .boardId,
                                                                          stackId: c
                                                                              .id,
                                                                          cardId:
                                                                              card.id);
                                                                    }
                                                                  },
                                                                  child: Text(
                                                                      l10n
                                                                          .deleteCard,
                                                                      style:
                                                                          _destructiveActionTextStyle),
                                                                ),
                                                              ],
                                                              cancelButton: CupertinoActionSheetAction(
                                                                  onPressed: () =>
                                                                      Navigator.of(
                                                                              ctx)
                                                                          .pop(),
                                                                  isDefaultAction:
                                                                      true,
                                                                  child: Text(l10n
                                                                      .cancel)),
                                                            ),
                                                          );
                                                        },
                                                      ),
                                                    ),
                                                    Positioned(
                                                      right: 6,
                                                      top: 6,
                                                      child:
                                                          ReorderableDragStartListener(
                                                        index: idx,
                                                        child: const Icon(
                                                            CupertinoIcons
                                                                .arrow_up_arrow_down,
                                                            size: 18,
                                                            color: CupertinoColors
                                                                .systemGrey),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(width: 12),
              ],
            ],
          ),
        ),
        Positioned(
          top: 8,
          left: 8,
          child: GestureDetector(
            onTap: () => _scrollBy(-340),
            child: const Icon(CupertinoIcons.chevron_back,
                color: CupertinoColors.systemGrey),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: GestureDetector(
            onTap: () => _scrollBy(340),
            child: const Icon(CupertinoIcons.chevron_forward,
                color: CupertinoColors.systemGrey),
          ),
        ),
      ],
    );
  }

}

class _LabelChip extends StatelessWidget {
  final Label label;
  const _LabelChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final bg = _parseDeckColor(label.color) ?? CupertinoColors.systemGrey4;
    final tc = _bestTextColor(bg);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label.title.isEmpty ? 'Label' : label.title,
        style: TextStyle(color: tc, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ReorderableCards extends StatelessWidget {
  final List<CardItem> cards;
  final void Function(int oldIndex, int newIndex) onReorder;
  final Widget Function(BuildContext, CardItem) itemBuilder;
  const _ReorderableCards(
      {required this.cards,
      required this.onReorder,
      required this.itemBuilder});

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      itemCount: cards.length,
      onReorder: onReorder,
      itemBuilder: (ctx, index) {
        final card = cards[index];
        return Container(
            key: ValueKey(card.id),
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: itemBuilder(ctx, card));
      },
      buildDefaultDragHandles: true,
    );
  }
}

Color? _parseDeckColor(String raw) {
  if (raw.isEmpty) return null;
  var s = raw.trim();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 3) {
    // expand #abc → aabbcc
    s = s.split('').map((c) => '$c$c').join();
  }
  if (s.length == 6) {
    s = 'FF$s';
  }
  if (s.length != 8) return null;
  final val = int.tryParse(s, radix: 16);
  if (val == null) return null;
  return Color(val);
}

Color _bestTextColor(Color bg) {
  // Relative luminance threshold for contrast
  final r = bg.red / 255.0;
  final g = bg.green / 255.0;
  final b = bg.blue / 255.0;
  double lum(double c) =>
      c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  final L = 0.2126 * lum(r) + 0.7152 * lum(g) + 0.0722 * lum(b);
  return L > 0.5 ? CupertinoColors.black : CupertinoColors.white;
}

Color _dueColor(DateTime due) {
  final now = DateTime.now();
  if (due.isBefore(now)) return CupertinoColors.destructiveRed;
  if (due.difference(now).inHours <= 24) return CupertinoColors.activeOrange;
  return CupertinoColors.systemGrey;
}

String _formatDue(DateTime due) {
  final fmt = DateFormat.MMMd().add_Hm();
  return fmt.format(due.toLocal());
}

String _markdownPreviewLine(String src) {
  if (src.isEmpty) return src;
  var s = src.trim();
  // Convert task list items
  s = s.replaceAllMapped(RegExp(r"^\s*- \[( |x|X)\]\s*", multiLine: true),
      (m) => m[1]!.trim().toLowerCase() == 'x' ? '☑ ' : '☐ ');
  // Remove code spans
  s = s.replaceAllMapped(RegExp(r"`([^`]*)`"), (m) => m.group(1) ?? '');
  // Strip emphasis/bold/strike
  s = s.replaceAllMapped(RegExp(r"\*\*([^*]+)\*\*"), (m) => m.group(1) ?? '');
  s = s.replaceAllMapped(RegExp(r"\*([^*]+)\*"), (m) => m.group(1) ?? '');
  s = s.replaceAllMapped(RegExp(r"~~([^~]+)~~"), (m) => m.group(1) ?? '');
  // Convert links [text](url) -> text
  s = s.replaceAllMapped(
      RegExp(r"\[([^\]]+)\]\(([^)]+)\)"), (m) => m.group(1) ?? '');
  // Strip headings and blockquotes markers
  s = s.replaceAll(RegExp(r"^\s*#+\s*", multiLine: true), '');
  s = s.replaceAll(RegExp(r"^\s*>+\s*", multiLine: true), '');
  // Replace bullets with middle dot
  s = s.replaceAll(RegExp(r"^\s*[-*+]\s+", multiLine: true), '• ');
  // Collapse whitespace/newlines into single line for tile
  s = s.replaceAll(RegExp(r"\s+"), ' ').trim();
  return s;
}

class _EdgeIndicators extends StatelessWidget {
  final double currentPage;
  final int total;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  const _EdgeIndicators(
      {required this.currentPage,
      required this.total,
      required this.onPrev,
      required this.onNext});

  @override
  Widget build(BuildContext context) {
    final showLeft = currentPage > 0.05;
    final showRight = currentPage < total - 1 - 0.05;
    return IgnorePointer(
      ignoring: false,
      child: Stack(children: [
        if (showLeft)
          Positioned(
            left: 8,
            top: 14,
            child: _Arrow(onTap: onPrev, icon: CupertinoIcons.chevron_back),
          ),
        if (showRight)
          Positioned(
            right: 8,
            top: 14,
            child: _Arrow(onTap: onNext, icon: CupertinoIcons.chevron_forward),
          ),
      ]),
    );
  }
}

class _Arrow extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  const _Arrow({required this.onTap, required this.icon});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 26, color: CupertinoColors.systemGrey),
      ),
    );
  }
}

void _preloadNeighbors(BuildContext context, int boardId,
    List<deck.Column> columns, int currentIndex) {
  // Keine Vorab-Lade-Requests mehr; Karten kommen aus dem initialen details=true Fetch
  return;
}

// Preload memo shared across calls
final Map<int, DateTime> _preloadMemo = {};

// no-op
