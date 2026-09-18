import 'package:flutter/cupertino.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart'
    show ReorderableListView, ReorderableDelayedDragStartListener;
import 'dart:async';
import 'dart:math' as math;

import '../state/app_state.dart';
import '../models/board.dart';
import '../models/column.dart' as deck;
import 'card_detail_page.dart';
import '../models/label.dart';
import '../models/card_item.dart';
import '../models/user_ref.dart';
import 'board_search_page.dart';
import 'stack_reorder_page.dart';
import '../theme/app_theme.dart';
import '../theme/design_tokens.dart';
import '../widgets/skeleton.dart';
import '../l10n/app_localizations.dart';
import '../navigation/nav_keys.dart';

const TextStyle _destructiveActionTextStyle =
    TextStyle(color: CupertinoColors.destructiveRed);
const List<String> _boardColors = [
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

class BoardPage extends StatefulWidget {
  const BoardPage({super.key});

  @override
  State<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends State<BoardPage> with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  double _page = 0;
  int? _lastBoardId;
  bool _quickAddInFlight = false;
  bool _openCardInFlight = false;
  AppState? _appRef;
  late final AnimationController _spinCtrl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Kein Netz-Refresh hier: Daten kommen aus dem einmaligen Global-Fetch (details=true)
    final app = context.read<AppState>();
    if (_appRef == null) {
      _appRef = app;
      app.addListener(_handleAppChange);
    }
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
    _appRef?.removeListener(_handleAppChange);
    _spinCtrl.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _showVisibleBoards(BuildContext context) async {
    final app = context.read<AppState>();
    final visibleBoards = app.boards
        .where((b) => !b.archived && !app.isBoardHidden(b.id))
        .toList();
    if (visibleBoards.isEmpty) return;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(L10n.of(context).selectBoard),
        actions: visibleBoards
            .map((b) => CupertinoActionSheetAction(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    await _openBoard(context, b);
                  },
                  child: Text(b.title),
                ))
            .toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(),
          isDefaultAction: true,
          child: Text(L10n.of(context).cancel),
        ),
      ),
    );
  }

  Future<void> _openBoard(BuildContext context, Board board) async {
    final app = context.read<AppState>();
    final rootNav = Navigator.of(context, rootNavigator: true);
    showCupertinoDialog(
      context: rootNav.context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color:
                CupertinoTheme.of(context).barBackgroundColor.withOpacity(0.9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CupertinoActivityIndicator(),
              const SizedBox(height: 8),
              Text(L10n.of(context).loadingBoard(board.title),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
    try {
      await app.setActiveBoard(board);
      if (app.columnsForBoard(board.id).isEmpty) {
        await app.refreshColumnsFor(board);
      }
    } finally {
      if (rootNav.canPop()) rootNav.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final board = app.activeBoard;
    final columns = app.columnsForActiveBoard();
    if (!_quickAddInFlight &&
        board != null &&
        columns.isNotEmpty &&
        app.hasPendingQuickAddFor(board.id)) {
      _quickAddInFlight = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        app.clearPendingQuickAdd();
        final columnId = columns.first.id;
        await _showCreateCard(context, board.id, columnId);
        if (!mounted) return;
        setState(() => _quickAddInFlight = false);
      });
    }
    if (!_openCardInFlight &&
        board != null &&
        columns.isNotEmpty &&
        app.hasPendingOpenCardFor(board.id)) {
      _tryOpenPendingCard(app, board, columns);
    }
    final boardIndex =
        board == null ? -1 : app.boards.indexWhere((b) => b.id == board.id);
    final boardNcColor = (boardIndex >= 0 && boardIndex < app.boards.length)
        ? app.boards[boardIndex].color
        : null;
    final boardBaseColor = board == null
        ? null
        : (AppTheme.boardColorFrom(boardNcColor) ??
            AppTheme.boardStrongColor(boardIndex < 0 ? 0 : boardIndex));
    final showBoardBand = board != null && app.boardBandMode == 'nextcloud';
    final boardBackground = showBoardBand
        ? AppTheme.boardBandBackground(app, boardBaseColor!)
        : AppTheme.appBackground(app);
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
      backgroundColor: boardBackground,
      child: SafeArea(
        top: true,
        // NC 2.0: bottom bewusst OHNE SafeArea — die Spalten-Fläche läuft
        // bis zur Geräteunterkante durch und liegt HINTER der Glass-Tab-Bar.
        // Vorher endete die farbige Fläche am Home-Indicator und darunter
        // blitzte der helle Scaffold-Hintergrund auf, was den Liquid-Effekt
        // zerstört hat (Glas braucht Inhalt, den es brechen kann).
        bottom: false,
        child: Column(
          children: [
            if (board != null)
              _buildBoardHeader(
                  context, app, board, boardBaseColor!, showBoardBand),
            Expanded(
              child: Stack(
                children: [
                  if (board == null)
                    Center(child: Text(L10n.of(context).pleaseSelectBoard))
                  else if ((app.bootSyncing && columns.isEmpty) ||
                      (columns.isEmpty && (app.lastError == null)))
                    // Skeleton-Loader: zeigt schon das Card-Layout an,
                    // bevor echte Karten geladen sind. Wirkt schneller
                    // als ein einsamer Spinner.
                    const SafeArea(child: CardListSkeleton())
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
                        final isTablet = mq.size.shortestSide >=
                            600; // iPad/tablet heuristic
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
                                    duration: DT.durationMedium,
                                    curve: Curves.easeOut);
                              }
                            },
                            requestNextPage: () {
                              final target =
                                  (_pageController.page ?? 0).ceil() + 1;
                              if (target < columns.length) {
                                _pageController.animateToPage(target,
                                    duration: DT.durationMedium,
                                    curve: Curves.easeOut);
                              }
                            },
                            onTapCard: (cardId) {
                              final app = context.read<AppState>();
                              final stack = columns[index];
                              final archived = app.archivedCardsForBoard(
                                      board.id)[stack.id] ??
                                  const <CardItem>[];
                              final list = app.boardArchivedOnly
                                  ? archived
                                  : stack.cards;
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
                  // NC 2.0: Spalten-Navigation als fixes Overlay oben
                  // rechts — bildschirm-rechtsbündig, unabhängig von
                  // Titellänge und Spalten-Geometrie.
                  if (board != null &&
                      columns.length > 1 &&
                      !(MediaQuery.of(context).size.width >= 900 || isTablet))
                    Positioned(
                      top: 12,
                      right: 16,
                      child: _PagerPill(
                        current: _page.round().clamp(0, columns.length - 1),
                        total: columns.length,
                        onPrev: () {
                          final target =
                              (_pageController.page ?? 0).round() - 1;
                          if (target >= 0) {
                            _pageController.animateToPage(target,
                                duration: DT.durationMedium,
                                curve: Curves.easeOut);
                          }
                        },
                        onNext: () {
                          final target =
                              (_pageController.page ?? 0).round() + 1;
                          if (target < columns.length) {
                            _pageController.animateToPage(target,
                                duration: DT.durationMedium,
                                curve: Curves.easeOut);
                          }
                        },
                      ),
                    ),
                  if (!isTablet)
                    Positioned(
                      right: 16,
                      // NC 2.0 Feedback-Fix: direkt über der Tab-Bar-Pill
                      // (statt weit oben im leeren Raum zu schweben).
                      bottom: MediaQuery.of(context).padding.bottom + 92,
                      child: GlassButton(
                        // Feedback-Fix: opaker Farbkern in kräftiger
                        // Board-Farbe — reines Glas war auf gleichfarbigem
                        // Board-Hintergrund fast unsichtbar.
                        icon: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: boardBaseColor ??
                                CupertinoColors.activeBlue,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: (boardBaseColor ??
                                        CupertinoColors.activeBlue)
                                    .withOpacity(0.5),
                                blurRadius: 14,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Icon(
                            CupertinoIcons.add,
                            size: 24,
                            color: AppTheme.textOn(
                                boardBaseColor ?? CupertinoColors.activeBlue),
                          ),
                        ),
                        width: 60,
                        height: 60,
                        iconSize: 44,
                        glowColor: boardBaseColor,
                        onTap: () async {
                          if (board == null || columns.isEmpty) return;
                          HapticFeedback.lightImpact();
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
      ),
    );
  }

  Widget _buildBoardHeader(BuildContext context, AppState app, Board board,
      Color baseColor, bool showBoardBand) {
    final topColor = app.isDarkMode
        ? AppTheme.blend(baseColor, const Color(0xFF000000), 0.25)
        : AppTheme.blend(baseColor, const Color(0xFF000000), 0.15);
    // NC 2.0 Fix: Kontrastfarbe IMMER aus der tatsächlichen Header-Farbe
    // ableiten — das alte harte Schwarz im Light-Mode war auf dunklen
    // Board-Farben (z. B. Dunkellila) unlesbar.
    final txtColor = AppTheme.textOn(topColor);
    final l10n = L10n.of(context);
    // NC 2.0: Header mit Titel-Pill (Tap = Board-Wechsel), Glass-Buttons
    // und Board-Menü als Popover direkt am Button statt Vollbild-Sheet —
    // ein Tap weniger, kein Kontextverlust.
    return Container(
      width: double.infinity,
      decoration: showBoardBand
          ? BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [topColor, baseColor],
              ),
            )
          : null,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Row(
        children: [
          // Suche immer oben links erreichbar — hier im Scope des
          // aktuellen Boards (umschaltbar auf alle Boards in der Suche).
          GlassIconButton(
            size: 38,
            icon: Icon(CupertinoIcons.search, size: 19, color: txtColor),
            onPressed: () {
              Navigator.of(context).push(
                  CupertinoPageRoute(builder: (_) => const BoardSearchPage()));
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              alignment: Alignment.centerLeft,
              onPressed: () => _showVisibleBoards(context),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: txtColor.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(DT.radiusFull),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: baseColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: txtColor.withOpacity(0.35), width: 1),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        board.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                            letterSpacing: -0.3,
                            color: txtColor),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(CupertinoIcons.chevron_up_chevron_down,
                        size: 14, color: txtColor.withOpacity(0.7)),
                  ],
                ),
              ),
            ),
          ),
          GlassIconButton(
            size: 38,
            icon: Icon(
                app.upcomingAssignedOnly
                    ? CupertinoIcons.person_fill
                    : CupertinoIcons.person,
                size: 19,
                color: txtColor),
            onPressed: () {
              app.setUpcomingAssignedOnly(!app.upcomingAssignedOnly);
            },
          ),
          const SizedBox(width: 8),
          _buildBoardMenuButton(context, app, board, txtColor, l10n),
        ],
      ),
    );
  }

  /// NC 2.0: Board-Menü als Glass-Popover am Button. Ersetzt das alte
  /// Vollbild-CupertinoActionSheet (_showBoardMenu) — gleiche Aktionen,
  /// aber mit Icons, direkt am Auslöser und ohne Kontextwechsel.
  Widget _buildBoardMenuButton(BuildContext context, AppState app,
      Board board, Color txtColor, L10n l10n) {
    final columns = app.columnsForActiveBoard();
    return GlassPullDownButton(
      buttonWidth: 38,
      buttonHeight: 38,
      menuWidth: 260,
      icon: Icon(CupertinoIcons.ellipsis_circle, size: 20, color: txtColor),
      items: [
        GlassMenuItem(
          title: l10n.refresh,
          icon: const Icon(CupertinoIcons.arrow_2_circlepath),
          onTap: () {
            if (app.isSyncing) return;
            app.runWithSyncing(() async {
              await app.refreshBoards(forceNetwork: true);
              await app.refreshSingleBoard(board.id);
            });
          },
        ),
        GlassMenuItem(
          title: l10n.search,
          icon: const Icon(CupertinoIcons.search),
          onTap: () {
            Navigator.of(context).push(
                CupertinoPageRoute(builder: (_) => const BoardSearchPage()));
          },
        ),
        if (columns.isNotEmpty)
          GlassMenuItem(
            title: l10n.selectColumn,
            icon: const Icon(CupertinoIcons.list_bullet),
            onTap: () => _showColumnJumpSheet(context, columns, l10n),
          ),
        GlassMenuItem(
          title: app.boardArchivedOnly
              ? l10n.showActiveCards
              : l10n.showArchivedCards,
          icon: const Icon(CupertinoIcons.archivebox),
          onTap: () {
            final next = !app.boardArchivedOnly;
            app.setBoardArchivedOnly(next);
            if (next) {
              app.refreshArchivedCardsForBoard(board.id);
            }
          },
        ),
        const GlassMenuDivider(),
        GlassMenuItem(
          title: l10n.newColumn,
          icon: const Icon(CupertinoIcons.plus_rectangle),
          onTap: () => _createColumnForBoard(context, board),
        ),
        if (columns.isNotEmpty)
          GlassMenuItem(
            title: l10n.renameColumn,
            icon: const Icon(CupertinoIcons.pencil),
            onTap: () => _renameColumnForBoard(context, board, columns),
          ),
        GlassMenuItem(
          title: l10n.reorderColumns,
          icon: const Icon(CupertinoIcons.arrow_up_arrow_down),
          onTap: () => _reorderColumnsForBoard(context, board),
        ),
        GlassMenuItem(
          title: l10n.changeBoardColor,
          icon: const Icon(CupertinoIcons.paintbrush),
          onTap: () => _changeBoardColorForBoard(context, board),
        ),
        const GlassMenuDivider(),
        GlassMenuItem(
          title: l10n.deleteBoard,
          icon: const Icon(CupertinoIcons.trash),
          isDestructive: true,
          onTap: () => _deleteBoard(context, board),
        ),
      ],
    );
  }

  /// Spalten-Schnellsprung (aus dem Board-Menü heraus).
  Future<void> _showColumnJumpSheet(
      BuildContext context, List<deck.Column> columns, L10n l10n) async {
    await showCupertinoModalPopup(
      context: context,
      builder: (sheetCtx) => CupertinoActionSheet(
        title: Text(l10n.selectColumn),
        actions: columns
            .asMap()
            .entries
            .map((e) => CupertinoActionSheetAction(
                  onPressed: () {
                    Navigator.of(sheetCtx).pop();
                    final target = e.key;
                    if (_pageController.hasClients) {
                      _pageController.animateToPage(target,
                          duration: DT.durationMedium, curve: Curves.easeOut);
                    }
                  },
                  child: Text(e.value.title),
                ))
            .toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetCtx).pop(),
          isDefaultAction: true,
          child: Text(l10n.cancel),
        ),
      ),
    );
  }

  Future<void> _createColumnForBoard(BuildContext context, Board board) async {
    final l10n = L10n.of(context);
    final title = await _promptForText(
      context,
      title: l10n.newColumn,
      placeholder: l10n.columnTitlePlaceholder,
    );
    if (title == null) return;
    final app = context.read<AppState>();
    final ok = await app.createStack(boardId: board.id, title: title);
    if (ok) {
      await app.refreshSingleBoard(board.id);
    } else {
      _showInfoDialog(context, title: l10n.errorMsg(l10n.columnCreateFailed));
    }
  }

  void _reorderColumnsForBoard(BuildContext context, Board board) {
    Navigator.of(context).push(CupertinoPageRoute(
        builder: (_) =>
            StackReorderPage(boardId: board.id, boardTitle: board.title)));
  }

  Future<void> _renameColumnForBoard(
      BuildContext context, Board board, List<deck.Column> columns) async {
    final l10n = L10n.of(context);
    final selected = await showCupertinoModalPopup<deck.Column>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(l10n.renameColumn),
        actions: columns
            .map((c) => CupertinoActionSheetAction(
                  onPressed: () => Navigator.of(ctx).pop(c),
                  child: Text(c.title),
                ))
            .toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(),
          isDefaultAction: true,
          child: Text(l10n.cancel),
        ),
      ),
    );
    if (selected == null) return;
    if (!context.mounted) return;
    final title = await _promptForText(
      context,
      title: l10n.renameColumn,
      placeholder: l10n.columnTitlePlaceholder,
      initialValue: selected.title,
      actionLabel: l10n.save,
    );
    if (title == null || title.trim() == selected.title) return;
    if (!context.mounted) return;
    final ok = await context
        .read<AppState>()
        .renameStack(boardId: board.id, stackId: selected.id, title: title);
    if (!ok && context.mounted) {
      _showInfoDialog(context, title: l10n.errorMsg(l10n.columnRenameFailed));
    }
  }

  Future<void> _changeBoardColorForBoard(
      BuildContext context, Board board) async {
    final l10n = L10n.of(context);
    final color = await _pickBoardColor(context);
    if (color == null) return;
    final app = context.read<AppState>();
    final ok = await app.updateBoardColor(boardId: board.id, color: color);
    if (!ok) {
      _showInfoDialog(context, title: l10n.errorMsg(l10n.boardUpdateFailed));
    }
  }

  Future<String?> _promptForText(BuildContext context,
      {required String title,
      String? placeholder,
      String? initialValue,
      String? actionLabel}) async {
    final controller = TextEditingController(text: initialValue ?? '');
    final l10n = L10n.of(context);
    return showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => AnimatedPadding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: SafeArea(
          child: CupertinoActionSheet(
            title: Text(title),
            message: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: CupertinoTextField(
                controller: controller,
                placeholder: placeholder ?? l10n.title,
                autofocus: true,
              ),
            ),
            actions: [
              CupertinoActionSheetAction(
                onPressed: () {
                  final text = controller.text.trim();
                  if (text.isEmpty) return;
                  Navigator.of(ctx).pop(text);
                },
                child: Text(actionLabel ?? l10n.create),
              ),
            ],
            cancelButton: CupertinoActionSheetAction(
              onPressed: () => Navigator.of(ctx).pop(),
              isDefaultAction: true,
              child: Text(l10n.cancel),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteBoard(BuildContext context, Board board) async {
    final l10n = L10n.of(context);
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(l10n.deleteBoard),
        content: Text(l10n.deleteBoardQuestion(board.title)),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final ok = await context.read<AppState>().deleteBoard(boardId: board.id);
    if (!ok && context.mounted) {
      _showInfoDialog(context, title: l10n.errorMsg(l10n.boardDeleteFailed));
    }
  }

  Future<String?> _pickBoardColor(BuildContext context) async {
    final l10n = L10n.of(context);
    return showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(l10n.pickColor),
        actions: [
          for (final hex in _boardColors)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(ctx).pop(hex),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Color(int.parse('FF$hex', radix: 16)),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: CupertinoColors.separator),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('#$hex'),
                ],
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(),
          isDefaultAction: true,
          child: Text(l10n.cancel),
        ),
      ),
    );
  }

  void _showInfoDialog(BuildContext context, {required String title}) {
    final l10n = L10n.of(context);
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
  }

  void _handleAppChange() {
    if (!mounted) return;
    final app = _appRef;
    if (app == null) return;
    final board = app.activeBoard;
    final columns =
        board == null ? <deck.Column>[] : app.columnsForBoard(board.id);
    if (board == null || columns.isEmpty) return;
    if (app.hasPendingOpenCardFor(board.id) && !_openCardInFlight) {
      _tryOpenPendingCard(app, board, columns);
    }
  }

  void _tryOpenPendingCard(
      AppState app, Board board, List<deck.Column> columns) {
    _openCardInFlight = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final pending = app.consumePendingOpenCard(board.id);
      if (pending == null) {
        if (mounted) setState(() => _openCardInFlight = false);
        return;
      }
      final stack = _resolveStackForCard(columns, pending);
      if (stack == null) {
        if (mounted) setState(() => _openCardInFlight = false);
        return;
      }
      final list = app.boardArchivedOnly
          ? (app.archivedCardsForBoard(board.id)[stack.id] ??
              const <CardItem>[])
          : stack.cards;
      if (list.isEmpty) {
        if (mounted) setState(() => _openCardInFlight = false);
        return;
      }
      final card = list.firstWhere(
        (c) => c.id == pending.cardId,
        orElse: () => list.first,
      );
      final colIdx = columns.indexOf(stack);
      final cardIdx = list.indexOf(card);
      final bg = AppTheme.cardBg(
          app, card.labels, colIdx < 0 ? 0 : colIdx, cardIdx < 0 ? 0 : cardIdx);
      final nav = AppNavKeys.boardNavKey.currentState ?? Navigator.of(context);
      nav.popUntil((route) => route.isFirst);
      await nav.push(
        CupertinoPageRoute(
          builder: (_) => CardDetailPage(
            cardId: pending.cardId,
            boardId: board.id,
            stackId: stack.id,
            bgColor: bg,
            startEditing: pending.edit,
          ),
        ),
      );
      if (mounted) setState(() => _openCardInFlight = false);
    });
  }

  deck.Column? _resolveStackForCard(
      List<deck.Column> columns, PendingCardOpen pending) {
    if (pending.stackId != null) {
      return columns.firstWhere(
        (c) => c.id == pending.stackId,
        orElse: () => columns.isNotEmpty
            ? columns.first
            : deck.Column(id: -1, title: '—', cards: const []),
      );
    }
    for (final col in columns) {
      if (col.cards.any((c) => c.id == pending.cardId)) return col;
    }
    return columns.isNotEmpty ? columns.first : null;
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
        final neutralBase = AppTheme.neutralCardBase(app);
        final baseForCards = app.cardColorsFromLabels
            ? (app.smartColors && colIdx >= 0
                ? AppTheme.preferredColumnColor(app, cols[colIdx].title, colIdx)
                : neutralBase)
            : neutralBase;
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
    // Leak-Fix: Sheet-Controller nach Schließen freigeben (Text wurde
    // vor dem Pop bereits ausgelesen).
    titleCtrl.dispose();
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
    final neutralBase = AppTheme.neutralCardBase(app);
    final baseForCards = app.cardColorsFromLabels
        ? (app.smartColors
            ? AppTheme.preferredColumnColor(app, col.title, widget.columnIndex)
            : neutralBase)
        : neutralBase;
    final filterAssigned = app.upcomingAssignedOnly;
    final sourceCards = showArchivedOnly ? archivedCards : col.cards;
    final cards = sourceCards
        .where((c) => showArchivedOnly ? true : !c.archived)
        .where((c) => !filterAssigned || app.shouldIncludeAssignedCard(c))
        .toList();
    final showArchivedLoading =
        showArchivedOnly && isArchivedLoading && archivedByStack.isEmpty;

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

    // NC 2.0: Spalten-Header links ausgerichtet, große Typo, Karten-Zähler
    // als Pill. Die Spalten-Navigation ist ein FIXES Overlay am rechten
    // Bildschirmrand (siehe _PagerPill im Board-Stack) — im Header wäre
    // ihre Position von Spalten-Geometrie und Titellänge abhängig.
    Widget header = Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 120, 10),
      child: Row(
        children: [
          Flexible(
            child: Text(col.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5)),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: CupertinoColors.systemGrey.withOpacity(0.18),
              borderRadius: BorderRadius.circular(DT.radiusFull),
            ),
            child: Text('${cards.length}',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: CupertinoColors.systemGrey)),
          ),
        ],
      ),
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
                        ? const CardListSkeleton()
                        : CupertinoScrollbar(
                            controller: _listCtrl.hasClients ? _listCtrl : null,
                            child: ListView.builder(
                              controller: _listCtrl,
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 140),
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
              // NC 2.0: Drop-Hover glüht in der Board-Farbe statt System-Blau
              border: _hover
                  ? Border.all(
                      color: AppTheme.boardColorFrom(
                              app.activeBoard?.color) ??
                          CupertinoColors.activeBlue,
                      width: 2.5)
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
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 140),
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
                                                BorderRadius.circular(DT.radiusL),
                                            // Drag-Feedback: stärkere Schatten,
                                            // damit die Karte sichtbar
                                            // "schwebt" — konsistent mit dem
                                            // Card-Look ohne harten Border.
                                            boxShadow: DT.shadowL(
                                                CupertinoTheme.brightnessOf(
                                                        context) ==
                                                    Brightness.dark),
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
                                                final isArchived =
                                                    card.archived;
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
                                                                  cardId:
                                                                      card.id,
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
                                                                  cardId:
                                                                      card.id,
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
                                                items.add(
                                                    CupertinoActionSheetAction(
                                                  onPressed: () async {
                                                    Navigator.of(ctx).pop();
                                                    if (boardId == null) return;
                                                    final nextArchived =
                                                        !isArchived;
                                                    app.updateLocalCard(
                                                        boardId: boardId,
                                                        stackId:
                                                            widget.column.id,
                                                        cardId: card.id,
                                                        archived: nextArchived);
                                                    final base = app.baseUrl;
                                                    final user = app.username;
                                                    final pass = await app
                                                        .storage
                                                        .read(key: 'password');
                                                    if (base != null &&
                                                        user != null &&
                                                        pass != null) {
                                                      try {
                                                        await app
                                                            .updateCardAndRefresh(
                                                                boardId:
                                                                    boardId,
                                                                stackId: widget
                                                                    .column.id,
                                                                cardId: card.id,
                                                                patch: {
                                                              'title':
                                                                  card.title,
                                                              'archived':
                                                                  nextArchived,
                                                            });
                                                      } catch (_) {}
                                                    }
                                                    if (app.boardArchivedOnly) {
                                                      await app
                                                          .refreshArchivedCardsForBoard(
                                                              boardId);
                                                    }
                                                  },
                                                  child: Text(isArchived
                                                      ? l10n.unarchiveCard
                                                      : l10n.archiveCard),
                                                ));
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
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 140),
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
            // NC 2.0: Drop-Hover glüht in der Board-Farbe statt System-Blau
            border: _hover
                ? Border.all(
                    color: AppTheme.boardColorFrom(app.activeBoard?.color) ??
                        CupertinoColors.activeBlue,
                    width: 2.5)
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
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 140),
                            itemCount: cards.length,
                            onReorderStart: (_) =>
                                HapticFeedback.selectionClick(),
                            onReorder: (oldIndex, newIndex) async {
                              if (showArchivedOnly) return;
                              final app = context.read<AppState>();
                              final boardId = app.activeBoard?.id;
                              if (boardId == null) return;
                              if (newIndex > oldIndex) newIndex -= 1;
                              final movedCard = cards[oldIndex];
                              final cardId = movedCard.id;
                              HapticFeedback.mediumImpact();
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
                                    for (final x
                                        in app.columnsForActiveBoard()) {
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
                                padding:
                                    const EdgeInsets.symmetric(vertical: 6),
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
                                              fromStackId: widget.column.id,
                                              title: card.title),
                                          feedback: ConstrainedBox(
                                            constraints: const BoxConstraints(
                                                maxWidth: 300),
                                            child: Opacity(
                                              opacity: 0.95,
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  color: bg,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          DT.radiusL),
                                                  boxShadow: DT.shadowL(
                                                      CupertinoTheme
                                                                  .brightnessOf(
                                                                      context) ==
                                                          Brightness.dark),
                                                ),
                                                padding:
                                                    const EdgeInsets.all(12),
                                                child: Text(card.title,
                                                    style: TextStyle(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: AppTheme.textOn(
                                                            bg))),
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
                                                  textColor:
                                                      AppTheme.textOn(bg),
                                                  description:
                                                      card.description),
                                            ),
                                          ),
                                          onDragUpdate: (details) {
                                            final now = DateTime.now();
                                            if (_edgeLastNav != null &&
                                                now
                                                        .difference(
                                                            _edgeLastNav!)
                                                        .inMilliseconds <
                                                    350) return;
                                            final w = MediaQuery.of(context)
                                                .size
                                                .width;
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
                                                : () =>
                                                    widget.onTapCard!(card.id),
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
                                              final rootNav = Navigator.of(
                                                  context,
                                                  rootNavigator: true);
                                              await showCupertinoModalPopup(
                                                context: rootNav.context,
                                                builder: (ctx) =>
                                                    CupertinoActionSheet(
                                                  actions: [
                                                    ...() {
                                                      final app = context
                                                          .read<AppState>();
                                                      final isDone =
                                                          card.done != null;
                                                      final isArchived =
                                                          card.archived;
                                                      if (!isDone) {
                                                        return [
                                                          CupertinoActionSheetAction(
                                                            onPressed:
                                                                () async {
                                                              Navigator.of(ctx)
                                                                  .pop();
                                                              final boardId = app
                                                                  .activeBoard
                                                                  ?.id;
                                                              if (boardId ==
                                                                  null) return;
                                                              final doneAt =
                                                                  DateTime.now()
                                                                      .toUtc();
                                                              app.updateLocalCard(
                                                                  boardId:
                                                                      boardId,
                                                                  stackId: widget
                                                                      .column
                                                                      .id,
                                                                  cardId:
                                                                      card.id,
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
                                                                          boardId,
                                                                      stackId: widget
                                                                          .column
                                                                          .id,
                                                                      cardId:
                                                                          card.id,
                                                                      patch: {
                                                                        'title':
                                                                            card.title,
                                                                        'done':
                                                                            doneAt,
                                                                      });
                                                                } catch (_) {}
                                                              }
                                                            },
                                                            child: Text(
                                                                l10n.markDone),
                                                          ),
                                                          CupertinoActionSheetAction(
                                                            onPressed:
                                                                () async {
                                                              Navigator.of(ctx)
                                                                  .pop();
                                                              final boardId = app
                                                                  .activeBoard
                                                                  ?.id;
                                                              if (boardId ==
                                                                  null) return;
                                                              final nextArchived =
                                                                  !isArchived;
                                                              app.updateLocalCard(
                                                                  boardId:
                                                                      boardId,
                                                                  stackId: widget
                                                                      .column
                                                                      .id,
                                                                  cardId:
                                                                      card.id,
                                                                  archived:
                                                                      nextArchived);
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
                                                                          boardId,
                                                                      stackId: widget
                                                                          .column
                                                                          .id,
                                                                      cardId:
                                                                          card.id,
                                                                      patch: {
                                                                        'title':
                                                                            card.title,
                                                                        'archived':
                                                                            nextArchived,
                                                                      });
                                                                } catch (_) {}
                                                              }
                                                              if (app
                                                                  .boardArchivedOnly) {
                                                                await app
                                                                    .refreshArchivedCardsForBoard(
                                                                        boardId);
                                                              }
                                                            },
                                                            child: Text(isArchived
                                                                ? l10n
                                                                    .unarchiveCard
                                                                : l10n
                                                                    .archiveCard),
                                                          ),
                                                        ];
                                                      } else {
                                                        return [
                                                          CupertinoActionSheetAction(
                                                            onPressed:
                                                                () async {
                                                              Navigator.of(ctx)
                                                                  .pop();
                                                              final boardId = app
                                                                  .activeBoard
                                                                  ?.id;
                                                              if (boardId ==
                                                                  null) return;
                                                              app.updateLocalCard(
                                                                  boardId:
                                                                      boardId,
                                                                  stackId: widget
                                                                      .column
                                                                      .id,
                                                                  cardId:
                                                                      card.id,
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
                                                                          boardId,
                                                                      stackId: widget
                                                                          .column
                                                                          .id,
                                                                      cardId:
                                                                          card.id,
                                                                      patch: {
                                                                        'title':
                                                                            card.title,
                                                                        'done':
                                                                            null,
                                                                      });
                                                                } catch (_) {}
                                                              }
                                                            },
                                                            child: Text(l10n
                                                                .markUndone),
                                                          ),
                                                          CupertinoActionSheetAction(
                                                            onPressed:
                                                                () async {
                                                              Navigator.of(ctx)
                                                                  .pop();
                                                              final boardId = app
                                                                  .activeBoard
                                                                  ?.id;
                                                              if (boardId ==
                                                                  null) return;
                                                              final nextArchived =
                                                                  !isArchived;
                                                              app.updateLocalCard(
                                                                  boardId:
                                                                      boardId,
                                                                  stackId: widget
                                                                      .column
                                                                      .id,
                                                                  cardId:
                                                                      card.id,
                                                                  archived:
                                                                      nextArchived);
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
                                                                          boardId,
                                                                      stackId: widget
                                                                          .column
                                                                          .id,
                                                                      cardId:
                                                                          card.id,
                                                                      patch: {
                                                                        'title':
                                                                            card.title,
                                                                        'archived':
                                                                            nextArchived,
                                                                      });
                                                                } catch (_) {}
                                                              }
                                                              if (app
                                                                  .boardArchivedOnly) {
                                                                await app
                                                                    .refreshArchivedCardsForBoard(
                                                                        boardId);
                                                              }
                                                            },
                                                            child: Text(isArchived
                                                                ? l10n
                                                                    .unarchiveCard
                                                                : l10n
                                                                    .archiveCard),
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
                                                          context:
                                                              rootNav.context,
                                                          builder: (dCtx) =>
                                                              CupertinoAlertDialog(
                                                            title: Text(l10n
                                                                .deleteCard),
                                                            content: Text(l10n
                                                                .confirmDeleteCard),
                                                            actions: [
                                                              CupertinoDialogAction(
                                                                  onPressed: () =>
                                                                      Navigator.of(
                                                                              dCtx)
                                                                          .pop(
                                                                              false),
                                                                  child: Text(l10n
                                                                      .cancel)),
                                                              CupertinoDialogAction(
                                                                isDestructiveAction:
                                                                    true,
                                                                onPressed: () =>
                                                                    Navigator.of(
                                                                            dCtx)
                                                                        .pop(
                                                                            true),
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
                                                                      .column
                                                                      .id,
                                                                  cardId:
                                                                      card.id);
                                                        }
                                                      },
                                                      child: Text(
                                                          l10n.deleteCard,
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
                                                          child: Text(
                                                              l10n.cancel)),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                        Positioned(
                                          right: 6,
                                          top: 6,
                                          // Issue #85: verzögerter Drag-Start
                                          // (Long-Press). Der sofort startende
                                          // Listener lag genau in der Daumen-
                                          // Scroll-Zone — Scrollen auf dem
                                          // Handle sortierte ungewollt um.
                                          child:
                                              ReorderableDelayedDragStartListener(
                                            index: idx,
                                            child: const Icon(
                                                CupertinoIcons
                                                    .arrow_up_arrow_down,
                                                size: 18,
                                                color:
                                                    CupertinoColors.systemGrey),
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

  @override
  Widget build(BuildContext context) {
    final textColor = AppTheme.textOn(background);
    final isDark =
        CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(DT.radiusL),
          // NC 2.0: weiche Elevation + hauchdünne helle Oberkante
          // („Licht von oben") — gibt den Karten einen Hauch Glas-Tiefe,
          // ohne echten Shader-Aufwand pro Karte.
          border: Border(
            top: BorderSide(
                color: CupertinoColors.white
                    .withOpacity(isDark ? 0.10 : 0.55),
                width: 1),
          ),
          boxShadow: DT.shadowM(isDark),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
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
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        height: 1.25,
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
                  return Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      subtitle!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: textColor.withOpacity(0.72),
                          fontSize: 13.5,
                          height: 1.35),
                    ),
                  );
                } else {
                  return const SizedBox.shrink();
                }
              }),
            // NC 2.0: Due-Badge + Assignee-Avatare in EINER Footer-Zeile
            // statt loser Text-Zeilen — kompakter und deutlich moderner.
            if (due != null || assignees.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    if (due != null)
                      Builder(builder: (context) {
                        // Issue #75: erledigte Karten sind nie „überfällig".
                        final isDone = done != null;
                        final now = DateTime.now();
                        final isOverdue = !isDone && due!.isBefore(now);
                        final hoursTo = due!.difference(now).inHours;
                        final Color dueColor = isDone
                            ? CupertinoColors.activeGreen
                            : isOverdue
                                ? CupertinoColors.systemRed
                                : (hoursTo <= 24
                                    ? CupertinoColors.activeOrange
                                    : textColor.withOpacity(0.9));
                        final bool tinted =
                            isDone || isOverdue || hoursTo <= 24;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: tinted
                                ? dueColor.withOpacity(0.16)
                                : textColor.withOpacity(0.08),
                            borderRadius:
                                BorderRadius.circular(DT.radiusFull),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                  isDone
                                      ? CupertinoIcons.checkmark_circle_fill
                                      : CupertinoIcons.time,
                                  size: 13,
                                  color: dueColor),
                              const SizedBox(width: 4),
                              Text(
                                _formatDue(due!),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: dueColor,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    const Spacer(),
                    if (assignees.isNotEmpty)
                      _AssigneeAvatars(
                          assignees: assignees, textColor: textColor),
                  ],
                ),
              ),
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
    // Issue #70: Auch auf Tablets LongPress statt Sofort-Drag. Das alte
    // sofortige `Draggable` hat auf dem iPad beim Scrollen durch Spalten
    // ständig versehentliche Karten-Verschiebungen ausgelöst — jede
    // Touch-Bewegung auf einer Karte wurde als Drag interpretiert.
    // Auf Tablets ist der Delay kürzer (250ms statt 500ms), damit sich
    // bewusstes Draggen weiterhin flott anfühlt.
    final isTablet = MediaQuery.of(context).size.shortestSide >= 600;
    return LongPressDraggable<_DragCard>(
      data: data,
      feedback: feedback,
      child: child,
      childWhenDragging: childWhenDragging,
      onDragUpdate: onDragUpdate,
      axis: Axis.horizontal,
      // Issue #85: 350ms statt 250ms — beim kurzen Verharren während des
      // Scrollens feuerte der Drag auf Tablets zu schnell.
      delay: isTablet
          ? const Duration(milliseconds: 350)
          : kLongPressTimeout,
      hapticFeedbackOnStart: true,
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
        duration: DT.durationMedium, curve: Curves.easeOut);
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
                  // Issue #87: Personen-Filter griff im breiten
                  // iPad-Layout nie — hier fehlte die
                  // shouldIncludeAssignedCard-Bedingung komplett.
                  final visibleCards = (showArchivedOnly
                          ? (archivedByStack[c.id] ?? const <CardItem>[])
                          : c.cards
                              .where((card) => !card.archived)
                              .toList())
                      .where((card) =>
                          !app.upcomingAssignedOnly ||
                          app.shouldIncludeAssignedCard(card))
                      .toList();
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
                              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
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
                                        CupertinoIcons.add_circled,
                                        size: 24),
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
                                        onReorderStart: (_) =>
                                            HapticFeedback.selectionClick(),
                                        onReorder: (oldIndex, newIndex) async {
                                          if (showArchivedOnly) return;
                                          final app = context.read<AppState>();
                                          final boardId = widget.boardId;
                                          if (newIndex > oldIndex)
                                            newIndex -= 1;
                                          final movedCard =
                                              visibleCards[oldIndex];
                                          final cardId = movedCard.id;
                                          HapticFeedback.mediumImpact();
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
                                          final tileBg =
                                              AppTheme.cardBgFromBase(
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
                                                      current!
                                                          .labels.isNotEmpty)
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
                                                  await app
                                                      .updateCardAndRefresh(
                                                          boardId: boardId,
                                                          stackId:
                                                              d.fromStackId,
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
                                                                          DT.radiusL),
                                                              boxShadow: DT.shadowL(
                                                                  CupertinoTheme.brightnessOf(
                                                                              context) ==
                                                                      Brightness.dark),
                                                            ),
                                                            padding:
                                                                const EdgeInsets
                                                                    .all(12),
                                                            child: Text(
                                                                card.title,
                                                                style: TextStyle(
                                                                    fontSize:
                                                                        16,
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
                                                                  boardId: widget
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
                                                                          context
                                                                              .read<AppState>();
                                                                      app.updateLocalCard(
                                                                          boardId: widget
                                                                              .boardId,
                                                                          stackId: c
                                                                              .id,
                                                                          cardId: card
                                                                              .id,
                                                                          done:
                                                                              doneAt);
                                                                      final base =
                                                                          app.baseUrl;
                                                                      final user =
                                                                          app.username;
                                                                      final pass = await app
                                                                          .storage
                                                                          .read(
                                                                              key: 'password');
                                                                      if (base != null &&
                                                                          user !=
                                                                              null &&
                                                                          pass !=
                                                                              null) {
                                                                        try {
                                                                          await app.updateCardAndRefresh(
                                                                              boardId: widget.boardId,
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
                                                                          context
                                                                              .read<AppState>();
                                                                      app.updateLocalCard(
                                                                          boardId: widget
                                                                              .boardId,
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
                                                                              key: 'password');
                                                                      if (base != null &&
                                                                          user !=
                                                                              null &&
                                                                          pass !=
                                                                              null) {
                                                                        try {
                                                                          await app.updateCardAndRefresh(
                                                                              boardId: widget.boardId,
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
                                                                  onPressed:
                                                                      () async {
                                                                    Navigator.of(
                                                                            ctx)
                                                                        .pop();
                                                                    final app =
                                                                        context.read<
                                                                            AppState>();
                                                                    final nextArchived =
                                                                        !card
                                                                            .archived;
                                                                    app.updateLocalCard(
                                                                        boardId:
                                                                            widget
                                                                                .boardId,
                                                                        stackId: c
                                                                            .id,
                                                                        cardId: card
                                                                            .id,
                                                                        archived:
                                                                            nextArchived);
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
                                                                              'archived': nextArchived,
                                                                            });
                                                                      } catch (_) {}
                                                                    }
                                                                    if (app
                                                                        .boardArchivedOnly) {
                                                                      await app.refreshArchivedCardsForBoard(
                                                                          widget
                                                                              .boardId);
                                                                    }
                                                                  },
                                                                  child: Text(card
                                                                          .archived
                                                                      ? l10n
                                                                          .unarchiveCard
                                                                      : l10n
                                                                          .archiveCard),
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
                                                      // Issue #85: siehe oben —
                                                      // Long-Press statt Sofort-Drag
                                                      child:
                                                          ReorderableDelayedDragStartListener(
                                                        index: idx,
                                                        child: const Icon(
                                                            CupertinoIcons
                                                                .arrow_up_arrow_down,
                                                            size: 18,
                                                            color:
                                                                CupertinoColors
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
    // NC 2.0: vollrunde Pills mit etwas Luft — weicher als die alten
    // 8-px-Ecken.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(DT.radiusFull),
      ),
      child: Text(
        label.title.isEmpty ? 'Label' : label.title,
        style: TextStyle(
            color: tc,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1),
      ),
    );
  }
}

/// NC 2.0: kompakte Initialen-Avatare für Karten-Assignees.
/// Zeigt bis zu drei überlappende Kreise, danach einen +N-Zähler.
class _AssigneeAvatars extends StatelessWidget {
  final List<UserRef> assignees;
  final Color textColor;
  const _AssigneeAvatars(
      {required this.assignees, required this.textColor});

  String _initials(UserRef u) {
    final src = u.displayName.isNotEmpty ? u.displayName : u.id;
    final parts =
        src.split(RegExp(r'[\s._-]+')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    const size = 24.0;
    const overlap = 7.0;
    final shown = assignees.take(3).toList();
    final extra = assignees.length - shown.length;
    final width =
        size + (shown.length - 1) * (size - overlap) + (extra > 0 ? 22 : 0);
    return SizedBox(
      height: size,
      width: width,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * (size - overlap),
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: textColor.withOpacity(0.16),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: textColor.withOpacity(0.25), width: 1),
                ),
                child: Text(
                  _initials(shown[i]),
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: textColor.withOpacity(0.95)),
                ),
              ),
            ),
          if (extra > 0)
            Positioned(
              left: shown.length * (size - overlap) + 2,
              top: 4,
              child: Text('+$extra',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: textColor.withOpacity(0.8))),
            ),
        ],
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 140),
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

// Perf: DateFormat-Konstruktion ist nicht billig — einmal cachen statt
// pro Karten-Render neu bauen (Boards mit vielen Karten rendern spürbar
// flüssiger beim Scrollen).
final DateFormat _dueFormat = DateFormat.MMMd().add_Hm();

String _formatDue(DateTime due) => _dueFormat.format(due.toLocal());

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

/// NC 2.0: kompakte Pager-Pill (‹ n/m ›) — fixes Overlay oben rechts.
/// Wird in Board- und Anstehend-Ansicht identisch verwendet.
class _PagerPill extends StatelessWidget {
  final int current;
  final int total;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  const _PagerPill(
      {required this.current,
      required this.total,
      required this.onPrev,
      required this.onNext});

  @override
  Widget build(BuildContext context) {
    final labelColor = CupertinoColors.label.resolveFrom(context);
    Widget chip(IconData icon, bool enabled, VoidCallback onTap) {
      return GestureDetector(
        onTap: enabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Icon(icon,
              size: 16,
              color: enabled
                  ? labelColor
                  : CupertinoColors.systemGrey.withOpacity(0.45)),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: CupertinoTheme.of(context)
            .scaffoldBackgroundColor
            .withOpacity(0.55),
        borderRadius: BorderRadius.circular(DT.radiusFull),
        border: Border.all(
            color: CupertinoColors.systemGrey.withOpacity(0.25), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          chip(CupertinoIcons.chevron_back, current > 0, onPrev),
          Text('${current + 1}/$total',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: labelColor.withOpacity(0.75))),
          chip(CupertinoIcons.chevron_forward, current < total - 1, onNext),
        ],
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
