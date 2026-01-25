import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../models/board.dart';
import '../models/card_item.dart';
import '../models/column.dart' as deck;
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import 'board_search_page.dart';
import 'stack_reorder_page.dart';

class OverviewPage extends StatefulWidget {
  const OverviewPage({super.key});

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  bool _hiddenExpanded = false;
  bool _archivedExpanded = false;
  final ScrollController _scroll = ScrollController();
  bool _showSearch = false;
  String _query = '';
  final FocusNode _searchFocus = FocusNode();
  static const _boardColors = [
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

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return CupertinoPageScaffold(
      backgroundColor: AppTheme.appBackground(app),
      navigationBar: CupertinoNavigationBar(
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).push(CupertinoPageRoute(builder: (_) => const BoardSearchPage(initialScope: SearchScope.all))),
          child: const Icon(CupertinoIcons.search),
        ),
        middle: Text(L10n.of(context).overview),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () async {
                // Use new sync system instead of old refreshBoards/refreshColumnsFor
                await app.runWithSyncing(() async {
                  await app.refreshBoards(forceNetwork: true);
                  if (app.activeBoard != null) {
                    await app.refreshSingleBoard(app.activeBoard!.id);
                  }
                });
              },
              child: const Icon(CupertinoIcons.refresh),
            ),
          ],
        ),
      ),
      child: SafeArea(
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            // Show search on pull-down (overscroll up)
            if (!_showSearch) {
              if (n is OverscrollNotification && n.overscroll < 0) {
                setState(() => _showSearch = true);
              } else if (n.metrics.pixels < -20) {
                setState(() => _showSearch = true);
              }
            }
            // Hide only after user scrolls down a bit, no query, and not focusing the field
            if (_showSearch && _query.isEmpty && n.metrics.pixels > 60 && !_searchFocus.hasFocus) {
              setState(() => _showSearch = false);
            }
            return false;
          },
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.all(16),
            children: [
              if (_showSearch || _query.isNotEmpty) ...[
                CupertinoSearchTextField(
                  placeholder: L10n.of(context).search,
                  focusNode: _searchFocus,
                  onChanged: (v) => setState(() => _query = v.trim()),
                  onSubmitted: (v) => setState(() => _query = v.trim()),
                ),
                const SizedBox(height: 12),
              ],
              _ActionRow(
                icon: CupertinoIcons.plus_circled,
                label: L10n.of(context).newBoard,
                onTap: () => _createBoard(context),
              ),
            if (app.boards.isEmpty) ...[
              Text(L10n.of(context).noBoardsLoaded),
            ] else if (app.activeBoard != null) ...[
              const SizedBox(height: 8),
              if (_query.isEmpty || app.activeBoard!.title.toLowerCase().contains(_query.toLowerCase())) ...[
                Text(L10n.of(context).activeBoard, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                _BoardSummary(
                  index: app.boards.indexWhere((b) => b.id == app.activeBoard!.id),
                  boardId: app.activeBoard!.id,
                  title: app.activeBoard!.title,
                  isActive: true,
                ),
                const SizedBox(height: 16),
                Container(height: 1, color: CupertinoColors.separator),
                const SizedBox(height: 16),
              ],
              Text(L10n.of(context).moreBoards, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: CupertinoColors.systemGrey)),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (ctx, cns) {
                  final isTablet = MediaQuery.of(ctx).size.shortestSide >= 600;
                  final visibleBoards = app.boards
                      .where((b) => !b.archived)
                      .where((b) => b.id != app.activeBoard!.id && !app.isBoardHidden(b.id))
                      .where((b) => _query.isEmpty || b.title.toLowerCase().contains(_query.toLowerCase()))
                      .toList()
                    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
                  if (!isTablet) {
                    return Column(
                      children: visibleBoards
                          .asMap()
                          .entries
                          .map((e) => _BoardSummary(index: e.key, boardId: e.value.id, title: e.value.title, isActive: false))
                          .toList(),
                    );
                  }
                  final boards = visibleBoards;
                  final cross = cns.maxWidth >= 1000 ? 3 : 2;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cross,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 2.2,
                    ),
                    itemCount: boards.length,
                    itemBuilder: (ctx, i) => _BoardSummary(index: i, boardId: boards[i].id, title: boards[i].title, isActive: false),
                  );
                },
              ),
              ..._buildHiddenSection(context, app, excludeActive: true),
              ..._buildArchivedSection(context, app, excludeActive: true),
            ] else ...[
              Text(L10n.of(context).yourBoards, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (ctx, cns) {
                  final isTablet = MediaQuery.of(ctx).size.shortestSide >= 600;
                  final visibleBoards = app.boards
                      .where((b) => !b.archived && !app.isBoardHidden(b.id))
                      .where((b) => _query.isEmpty || b.title.toLowerCase().contains(_query.toLowerCase()))
                      .toList()
                    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
                  if (!isTablet) {
                    return Column(
                      children: visibleBoards.asMap().entries
                          .map((e) => _BoardSummary(index: e.key, boardId: e.value.id, title: e.value.title, isActive: false))
                          .toList(),
                    );
                  }
                  final cross = cns.maxWidth >= 1000 ? 3 : 2;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cross,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 2.2,
                    ),
                    itemCount: visibleBoards.length,
                    itemBuilder: (ctx, i) => _BoardSummary(index: i, boardId: visibleBoards[i].id, title: visibleBoards[i].title, isActive: false),
                  );
                },
              ),
              ..._buildHiddenSection(context, app, excludeActive: false),
              ..._buildArchivedSection(context, app, excludeActive: false),
            ],
          ],
        ),
      ),
    ),
    );
  }

  Future<void> _createBoard(BuildContext context) async {
    final l10n = L10n.of(context);
    final title = await _promptForText(
      context,
      title: l10n.newBoard,
      placeholder: l10n.boardTitlePlaceholder,
    );
    if (title == null) return;
    final color = await _pickBoardColor(context, allowSkip: true);
    if (color == null) return;
    final app = context.read<AppState>();
    final created =
        await app.createBoard(title: title, color: color.isEmpty ? null : color);
    if (created == null) {
      _showInfoDialog(context,
          title: l10n.errorMsg(l10n.boardCreateFailed));
    }
  }

  Future<void> _createColumn(BuildContext context) async {
    final app = context.read<AppState>();
    final l10n = L10n.of(context);
    final board = await _pickBoard(context, title: l10n.selectBoard);
    if (board == null) return;
    final title = await _promptForText(
      context,
      title: l10n.newColumn,
      placeholder: l10n.columnTitlePlaceholder,
    );
    if (title == null) return;
    final ok = await app.createStack(boardId: board.id, title: title);
    if (ok) {
      await app.refreshSingleBoard(board.id);
    } else {
      _showInfoDialog(context,
          title: l10n.errorMsg(l10n.columnCreateFailed));
    }
  }

  Future<void> _reorderColumns(BuildContext context) async {
    final l10n = L10n.of(context);
    final board = await _pickBoard(context, title: l10n.selectBoard);
    if (board == null) return;
    if (context.mounted) {
      Navigator.of(context).push(CupertinoPageRoute(
          builder: (_) =>
              StackReorderPage(boardId: board.id, boardTitle: board.title)));
    }
  }

  Future<void> _changeBoardColor(BuildContext context) async {
    final l10n = L10n.of(context);
    final board = await _pickBoard(context, title: l10n.selectBoard);
    if (board == null) return;
    final color = await _pickBoardColor(context, allowSkip: false);
    if (color == null) return;
    final app = context.read<AppState>();
    final ok =
        await app.updateBoardColor(boardId: board.id, color: color);
    if (!ok) {
      _showInfoDialog(context,
          title: l10n.errorMsg(l10n.boardUpdateFailed));
    }
  }

  Future<String?> _promptForText(BuildContext context,
      {required String title, String? placeholder}) async {
    final controller = TextEditingController();
    final l10n = L10n.of(context);
    return showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
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
            child: Text(l10n.create),
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

  Future<Board?> _pickBoard(BuildContext context,
      {required String title}) async {
    final app = context.read<AppState>();
    final l10n = L10n.of(context);
    final boards =
        app.boards.where((b) => !b.archived).toList(growable: false);
    if (boards.isEmpty) {
      _showInfoDialog(context,
          title: l10n.errorMsg(l10n.noBoardsLoaded));
      return null;
    }
    return showCupertinoModalPopup<Board>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(title),
        actions: boards
            .map((b) => CupertinoActionSheetAction(
                  onPressed: () => Navigator.of(ctx).pop(b),
                  child: Text(b.title),
                ))
            .toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(),
          isDefaultAction: true,
          child: Text(l10n.cancel),
        ),
      ),
    );
  }

  Future<String?> _pickBoardColor(BuildContext context,
      {required bool allowSkip}) async {
    final l10n = L10n.of(context);
    return showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(l10n.pickColor),
        actions: [
          if (allowSkip)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(ctx).pop(''),
              child: Text(l10n.boardColorDefault),
            ),
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

  List<Widget> _buildHiddenSection(BuildContext context, AppState app, {required bool excludeActive}) {
    final hiddenBoards = app.boards
        .where((b) => !b.archived)
        .where((b) => app.isBoardHidden(b.id))
        .where((b) => excludeActive ? b.id != app.activeBoard?.id : true)
        .toList();
    if (hiddenBoards.isEmpty) return const [];
    return [
      const SizedBox(height: 16),
      Container(height: 1, color: CupertinoColors.separator),
      const SizedBox(height: 12),
      GestureDetector(
        onTap: () => setState(() => _hiddenExpanded = !_hiddenExpanded),
        behavior: HitTestBehavior.opaque,
        child: Row(
          children: [
            Icon(_hiddenExpanded ? CupertinoIcons.chevron_down : CupertinoIcons.chevron_right, size: 16, color: CupertinoColors.systemGrey),
            const SizedBox(width: 6),
            Text(L10n.of(context).hiddenBoards, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: CupertinoColors.systemGrey)),
          ],
        ),
      ),
      if (_hiddenExpanded) ...[
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (ctx, cns) {
            final isTablet = MediaQuery.of(ctx).size.shortestSide >= 600;
            if (!isTablet) {
              return Column(
                children: hiddenBoards
                    .asMap()
                    .entries
                    .map((e) => _BoardSummary(index: e.key, boardId: e.value.id, title: e.value.title, isActive: false))
                    .toList(),
              );
            }
            final cross = cns.maxWidth >= 1000 ? 3 : 2;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cross,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 2.2,
              ),
              itemCount: hiddenBoards.length,
              itemBuilder: (ctx, i) => _BoardSummary(index: i, boardId: hiddenBoards[i].id, title: hiddenBoards[i].title, isActive: false),
            );
          },
        ),
      ],
    ];
  }

  List<Widget> _buildArchivedSection(BuildContext context, AppState app, {required bool excludeActive}) {
    final archivedBoards = app.boards
        .where((b) => b.archived)
        .where((b) => excludeActive ? b.id != app.activeBoard?.id : true)
        .toList();
    if (archivedBoards.isEmpty) return const [];
    return [
      const SizedBox(height: 16),
      Container(height: 1, color: CupertinoColors.separator),
      const SizedBox(height: 12),
      GestureDetector(
        onTap: () => setState(() => _archivedExpanded = !_archivedExpanded),
        behavior: HitTestBehavior.opaque,
        child: Row(
          children: [
            Icon(_archivedExpanded ? CupertinoIcons.chevron_down : CupertinoIcons.chevron_right, size: 16, color: CupertinoColors.systemGrey),
            const SizedBox(width: 6),
            Text(L10n.of(context).archivedBoards, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: CupertinoColors.systemGrey)),
          ],
        ),
      ),
      if (_archivedExpanded) ...[
        const SizedBox(height: 6),
        Text(L10n.of(context).archivedBoardsInfo, style: const TextStyle(fontSize: 12, color: CupertinoColors.systemGrey)),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (ctx, cns) {
            final isTablet = MediaQuery.of(ctx).size.shortestSide >= 600;
            if (!isTablet) {
              return Column(
                children: archivedBoards
                    .asMap()
                    .entries
                    .map((e) => Opacity(opacity: 0.6, child: AbsorbPointer(child: _BoardSummary(index: e.key, boardId: e.value.id, title: e.value.title, isActive: false))))
                    .toList(),
              );
            }
            final cross = cns.maxWidth >= 1000 ? 3 : 2;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cross,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 2.2,
              ),
              itemCount: archivedBoards.length,
              itemBuilder: (ctx, i) => Opacity(opacity: 0.6, child: AbsorbPointer(child: _BoardSummary(index: i, boardId: archivedBoards[i].id, title: archivedBoards[i].title, isActive: false))),
            );
          },
        ),
      ],
    ];
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionRow(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: CupertinoColors.systemGrey),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            const Icon(CupertinoIcons.chevron_right,
                size: 16, color: CupertinoColors.systemGrey),
          ],
        ),
      ),
    );
  }
}

class _ActionDivider extends StatelessWidget {
  const _ActionDivider();

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: CupertinoColors.separator);
  }
}

class _BoardSummary extends StatelessWidget {
  final int index;
  final int boardId;
  final String title;
  final bool isActive;
  const _BoardSummary({required this.index, required this.boardId, required this.title, required this.isActive});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (app.boardMemberCount(boardId) == null) {
      if (app.overviewShowBoardInfo) {
        WidgetsBinding.instance.addPostFrameCallback((_) => app.ensureBoardMemberCount(boardId));
      }
    }
    final showInfo = app.overviewShowBoardInfo;
    final List<deck.Column> cols = showInfo
        ? (app.activeBoard?.id == boardId && app.columnsForActiveBoard().isNotEmpty
            ? app.columnsForActiveBoard()
            : app.columnsForBoard(boardId))
        : const <deck.Column>[];

    int stacks = 0;
    int cards = 0;
    int dueSoon = 0;
    int overdue = 0;
    bool hasStacks = false;
    bool hasAnyCards = false;
    if (showInfo) {
      stacks = cols.length;
      final now = DateTime.now();
      for (final c in cols) {
        cards += c.cards.length;
        for (final k in c.cards) {
          if (k.due != null) {
            if (k.due!.isBefore(now)) overdue++;
            else if (k.due!.difference(now).inHours <= 24) dueSoon++;
          }
        }
      }
      // Cache indicator: stacks/cards loaded
      hasStacks = cols.isNotEmpty;
      hasAnyCards = hasStacks && cols.any((c) => c.cards.isNotEmpty);
    }

    // Use Nextcloud board color when available; fallback to app palette
    final b = app.boards.firstWhere((x) => x.id == boardId, orElse: () => Board(id: boardId, title: title));
    final strong = AppTheme.boardColorFrom(b.color) ?? AppTheme.boardStrongColor(index);
    // Much softer background colors for overview cards
    final bg = app.isDarkMode
        ? AppTheme.blend(strong, const Color(0xFF000000), 0.8)
        : AppTheme.blend(strong, const Color(0xFFFFFFFF), 0.7);

    return GestureDetector(
      onTap: () async {
        final board = app.boards.firstWhere((b) => b.id == boardId, orElse: () => app.boards.first);
        // Use root navigator context to avoid using a disposed context after tab switch
        final rootNav = Navigator.of(context, rootNavigator: true);
        showCupertinoDialog(
          context: rootNav.context,
          barrierDismissible: false,
          builder: (_) => Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: CupertinoTheme.of(context).barBackgroundColor.withOpacity(0.9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CupertinoActivityIndicator(),
                  const SizedBox(height: 8),
                  Text(L10n.of(context).loadingBoard(title), textAlign: TextAlign.center),
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
          app.selectTab(1);
        } finally {
          // Close using the captured navigator to avoid deactivated context issues
          if (rootNav.canPop()) rootNav.pop();
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isActive ? CupertinoColors.activeGreen : CupertinoColors.separator, width: isActive ? 2 : 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Subtle header accent (half strength)
                    Container(height: 6, decoration: BoxDecoration(color: strong.withOpacity(0.25), borderRadius: BorderRadius.circular(6))),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textOn(bg))),
                        ),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => app.toggleBoardHidden(boardId),
                          child: Icon(
                            app.isBoardHidden(boardId) ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
                            size: 18,
                            color: AppTheme.textOn(bg).withOpacity(0.9),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (showInfo) Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _StatChip(icon: CupertinoIcons.rectangle_grid_2x2, label: L10n.of(context).columnsLabel, value: stacks.toString()),
                        _StatChip(icon: CupertinoIcons.list_bullet, label: L10n.of(context).cardsLabel, value: cards.toString()),
                        _StatChip(icon: CupertinoIcons.time, label: L10n.of(context).dueSoonLabel, value: dueSoon.toString(), color: CupertinoColors.activeOrange, emphasize: true),
                        _StatChip(icon: CupertinoIcons.exclamationmark_triangle, label: L10n.of(context).overdueLabel, value: overdue.toString(), color: CupertinoColors.destructiveRed),
                        _StatChip(
                          icon: CupertinoIcons.cloud_download,
                          label: L10n.of(context).cacheLabel,
                          value: hasAnyCards ? L10n.of(context).cardsLabel : (hasStacks ? L10n.of(context).columnsLabel : '—'),
                          color: hasAnyCards ? CupertinoColors.activeGreen : (hasStacks ? CupertinoColors.activeBlue : CupertinoColors.systemGrey),
                        ),
                        if (app.boardMemberCount(boardId) != null)
                          _StatChip(icon: CupertinoIcons.person_2, label: L10n.of(context).membersLabel, value: app.boardMemberCount(boardId)!.toString(), color: CupertinoColors.activeGreen),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? color;
  final bool emphasize;
  const _StatChip({required this.icon, required this.label, required this.value, this.color, this.emphasize = false});

  @override
  Widget build(BuildContext context) {
    final bg = (color ?? CupertinoColors.systemGrey).withOpacity(emphasize ? 0.2 : 0.12);
    final fg = color ?? CupertinoColors.systemGrey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text('$label: $value', style: TextStyle(color: fg, fontSize: 12, fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600)),
        ],
      ),
    );
  }
}
