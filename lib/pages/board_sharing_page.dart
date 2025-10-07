import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../models/user_ref.dart';
import '../l10n/app_localizations.dart';

class BoardSharingPage extends StatefulWidget {
  const BoardSharingPage({super.key});

  @override
  State<BoardSharingPage> createState() => _BoardSharingPageState();
}

class _BoardSharingPageState extends State<BoardSharingPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _shares = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final baseUrl = app.baseUrl; final user = app.username; final pass = await app.storage.read(key: 'password');
    final board = app.activeBoard;
    if (baseUrl == null || user == null || pass == null || board == null) {
      setState(() { _loading = false; });
      return;
    }
    try {
      final list = await app.api.fetchBoardShares(baseUrl, user, pass, board.id);
      setState(() { _shares = list; });
    } finally {
      setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final l10n = L10n.of(context);
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: Text(l10n.shareBoard)),
      child: SafeArea(
        child: _loading
            ? const Center(child: CupertinoActivityIndicator())
            : Column(
                children: [
                  Expanded(
                    child: ListView.separated(
                      itemCount: _shares.length,
                      separatorBuilder: (_, __) => Container(height: 1, color: CupertinoColors.separator),
                      itemBuilder: (context, i) {
                        final s = _shares[i];
                        final id = (s['id'] ?? s['shareId'] ?? 0).toString();
                        final withId = (s['shareWith'] ?? s['uid'] ?? '').toString();
                        final disp = (s['displayname'] ?? s['displayName'] ?? withId).toString();
                        return Dismissible(
                          key: ValueKey('share_$id'),
                          direction: DismissDirection.endToStart,
                          background: Container(color: CupertinoColors.destructiveRed),
                          onDismissed: (_) => _removeShare(s),
                          child: ListTile(
                            title: Text(disp),
                            subtitle: Text(withId),
                          ),
                        );
                      },
                    ),
                  ),
                  Container(height: 1, color: CupertinoColors.separator),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: CupertinoButton.filled(
                      onPressed: () => _addShare(context),
                      child: Text(l10n.addEllipsis),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _addShare(BuildContext context) async {
    final app = context.read<AppState>();
    final baseUrl = app.baseUrl; final user = app.username; final pass = await app.storage.read(key: 'password');
    final board = app.activeBoard;
    if (baseUrl == null || user == null || pass == null || board == null) return;
    final queryCtrl = TextEditingController();
    List<UserRef> results = const [];
    bool searching = false;
    await showCupertinoModalPopup(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        Future<void> doSearch() async {
          setS(() { searching = true; });
          try {
            results = await app.api.searchSharees(baseUrl, user, pass, queryCtrl.text.trim());
          } finally {
            setS(() { searching = false; });
          }
        }
        return CupertinoActionSheet(
          title: Text(L10n.of(ctx).shareWith),
          message: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CupertinoTextField(
                controller: queryCtrl,
                placeholder: L10n.of(ctx).userOrGroupSearch,
                onSubmitted: (_) => doSearch(),
              ),
              const SizedBox(height: 8),
              if (searching) const CupertinoActivityIndicator() else ...[
                SizedBox(
                  height: 260,
                  child: ListView(
                    children: results
                        .map((u) => CupertinoActionSheetAction(
                              onPressed: () async {
                                Navigator.of(ctx).pop();
                                final st = u.shareType ?? 0;
                                await app.api.addBoardShare(baseUrl, user, pass, board.id, shareType: st, shareWith: u.id);
                                await _load();
                              },
                              child: Text(u.displayName.isEmpty ? u.id : u.displayName),
                            ))
                        .toList(),
                  ),
                ),
              ],
            ],
          ),
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(ctx).pop(),
            isDefaultAction: true,
            child: Text(L10n.of(ctx).cancel),
          ),
        );
      }),
    );
  }

  Future<void> _removeShare(Map<String, dynamic> s) async {
    final app = context.read<AppState>();
    final baseUrl = app.baseUrl; final user = app.username; final pass = await app.storage.read(key: 'password');
    final board = app.activeBoard;
    if (baseUrl == null || user == null || pass == null || board == null) return;
    final id = (s['id'] ?? s['shareId']);
    if (id is int) {
      await app.api.removeBoardShare(baseUrl, user, pass, board.id, id);
      await _load();
    }
  }
}

class ListTile extends StatelessWidget {
  final Widget title;
  final Widget? subtitle;
  const ListTile({super.key, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DefaultTextStyle(style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500), child: title),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            DefaultTextStyle(style: const TextStyle(fontSize: 12, color: CupertinoColors.systemGrey), child: subtitle!),
          ]
        ],
      ),
    );
  }
}
