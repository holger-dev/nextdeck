import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../models/comment.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';

class CommentsPage extends StatefulWidget {
  final int cardId;
  const CommentsPage({super.key, required this.cardId});

  @override
  State<CommentsPage> createState() => _CommentsPageState();
}

class _CommentsPageState extends State<CommentsPage> {
  bool _loading = true;
  bool _sending = false;
  List<CommentItem> _comments = const [];
  final TextEditingController _input = TextEditingController();
  int? _replyTo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final base = app.baseUrl; final user = app.username; final pass = await app.storage.read(key: 'password');
    if (base == null || user == null || pass == null) { setState(() { _loading = false; }); return; }
    setState(() { _loading = true; });
    try {
      final raw = await app.api.fetchCommentsRaw(base, user, pass, widget.cardId, limit: 100, offset: 0);
      final list = raw.map((e) => CommentItem.fromJson(e)).toList();
      setState(() { _comments = list; });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final app = context.read<AppState>();
    final base = app.baseUrl; final user = app.username; final pass = await app.storage.read(key: 'password');
    if (base == null || user == null || pass == null) return;
    setState(() { _sending = true; });
    try {
      final created = await app.api.createComment(base, user, pass, widget.cardId, message: text, parentId: _replyTo);
      if (created != null) {
        final c = CommentItem.fromJson(created);
        setState(() { _comments = [..._comments, c]; _input.clear(); _replyTo = null; });
      } else {
        // fallback: reload
        await _load();
        _input.clear(); _replyTo = null;
      }
    } finally {
      if (mounted) setState(() { _sending = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final l10n = L10n.of(context);
    return CupertinoPageScaffold(
      backgroundColor: AppTheme.appBackground(app),
      navigationBar: CupertinoNavigationBar(middle: Text(l10n.comments)),
      child: SafeArea(
        child: Column(
          children: [
            if (_loading)
              const Expanded(child: Center(child: CupertinoActivityIndicator()))
            else
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    CupertinoSliverRefreshControl(onRefresh: _load),
                    SliverPadding(
                      padding: const EdgeInsets.all(12),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) => _CommentTile(
                            comment: _comments[i],
                            onReply: (id) => setState(() => _replyTo = id),
                            onDelete: (id) async {
                              final base = app.baseUrl; final user = app.username; final pass = await app.storage.read(key: 'password');
                              if (base == null || user == null || pass == null) return;
                              final ok = await app.api.deleteComment(base, user, pass, widget.cardId, id);
                              if (ok) setState(() { _comments = _comments.where((c) => c.id != id).toList(); });
                            },
                          ),
                          childCount: _comments.length,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Container(height: 1, color: CupertinoColors.separator),
            AnimatedPadding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              duration: const Duration(milliseconds: 150),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    if (_replyTo != null) ...[
                      GestureDetector(
                        onTap: () => setState(() => _replyTo = null),
                        child: const Icon(CupertinoIcons.xmark_circle_fill, size: 18, color: CupertinoColors.systemGrey),
                      ),
                      const SizedBox(width: 6),
                      Text(l10n.reply, style: const TextStyle(color: CupertinoColors.systemGrey)),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: CupertinoTextField(
                        controller: _input,
                        placeholder: l10n.writeComment,
                        maxLines: 3,
                        minLines: 1,
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CupertinoButton.filled(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      onPressed: _sending ? null : _send,
                      child: _sending ? const CupertinoActivityIndicator() : const Icon(CupertinoIcons.paperplane),
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

class _CommentTile extends StatelessWidget {
  final CommentItem comment;
  final ValueChanged<int> onReply;
  final ValueChanged<int> onDelete;
  const _CommentTile({required this.comment, required this.onReply, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final isMine = app.username == comment.actorId;
    final ts = comment.creationDateTime.toLocal().toString().substring(0, 16);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoTheme.of(context).barBackgroundColor.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CupertinoColors.separator),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(comment.actorDisplayName.isEmpty ? comment.actorId : comment.actorDisplayName, style: const TextStyle(fontWeight: FontWeight.w600))),
              Text(ts, style: const TextStyle(fontSize: 12, color: CupertinoColors.systemGrey)),
            ],
          ),
          const SizedBox(height: 6),
          if (comment.replyTo != null)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: CupertinoColors.systemGrey5.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_short(comment.replyTo!.message), style: const TextStyle(fontSize: 12, color: CupertinoColors.systemGrey)),
            ),
          Text(comment.message),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                onPressed: () => onReply(comment.id),
                child: Text(L10n.of(context).reply.replaceAll(' …',''), style: const TextStyle(fontSize: 12)),
              ),
              if (isMine)
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  onPressed: () => onDelete(comment.id),
                  child: Text(L10n.of(context).delete, style: const TextStyle(fontSize: 12, color: CupertinoColors.destructiveRed)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _short(String src) => src.length > 100 ? (src.substring(0, 100) + '…') : src;
}
