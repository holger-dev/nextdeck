import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show ReorderableListView, ReorderableDragStartListener;
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';

class StackReorderPage extends StatefulWidget {
  final int boardId;
  final String boardTitle;
  const StackReorderPage(
      {super.key, required this.boardId, required this.boardTitle});

  @override
  State<StackReorderPage> createState() => _StackReorderPageState();
}

class _StackReorderPageState extends State<StackReorderPage> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final app = context.read<AppState>();
      if (app.columnsForBoard(widget.boardId).isEmpty && !app.localMode) {
        setState(() => _loading = true);
        await app.refreshSingleBoard(widget.boardId);
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final l10n = L10n.of(context);
    final cols = app.columnsForBoard(widget.boardId);

    return CupertinoPageScaffold(
      backgroundColor: AppTheme.appBackground(app),
      navigationBar: CupertinoNavigationBar(
        middle: Text(l10n.reorderColumnsFor(widget.boardTitle)),
      ),
      child: SafeArea(
        child: _loading
            ? const Center(child: CupertinoActivityIndicator())
            : cols.isEmpty
                ? Center(child: Text(l10n.noColumnsLoaded))
                : ReorderableListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: cols.length,
                    onReorder: (oldIndex, newIndex) async {
                      await app.reorderStack(
                          boardId: widget.boardId,
                          oldIndex: oldIndex,
                          newIndex: newIndex);
                    },
                    itemBuilder: (context, index) {
                      final c = cols[index];
                      return Container(
                        key: ValueKey('stack_${c.id}'),
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: CupertinoTheme.of(context)
                              .barBackgroundColor
                              .withOpacity(app.isDarkMode ? 0.3 : 0.8),
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: CupertinoColors.separator),
                        ),
                        child: Row(
                          children: [
                            ReorderableDragStartListener(
                              index: index,
                              child: const Icon(CupertinoIcons.bars,
                                  color: CupertinoColors.systemGrey),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(c.title,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600)),
                            ),
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: () =>
                                  _confirmDeleteStack(context, c.id, c.title),
                              child: const Icon(CupertinoIcons.trash,
                                  color: CupertinoColors.systemRed),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }

  Future<void> _confirmDeleteStack(
      BuildContext context, int stackId, String title) async {
    final l10n = L10n.of(context);
    final result = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(l10n.deleteColumn),
        content: Text(l10n.deleteColumnQuestion(title)),
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
    if (result != true) return;
    final app = context.read<AppState>();
    final ok =
        await app.deleteStack(boardId: widget.boardId, stackId: stackId);
    if (!ok && mounted) {
      showCupertinoDialog<void>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: Text(l10n.errorMsg(l10n.columnDeleteFailed)),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.ok),
            ),
          ],
        ),
      );
    }
  }
}
