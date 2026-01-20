import 'package:flutter/cupertino.dart';
import 'dart:async';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../models/comment.dart';
import '../models/user_ref.dart';
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
  Timer? _mentionDebounce;
  bool _mentionSearching = false;
  List<UserRef> _mentionResults = const [];
  String _mentionQuery = '';
  int? _mentionAtIndex;
  int? _mentionCursor;
  Set<String> _mentionMembers = const {};
  bool _mentionMembersLoaded = false;
  bool _mentionBoardScoped = false;

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
        setState(() {
          _comments = [..._comments, c];
          _input.clear();
          _replyTo = null;
          _mentionResults = const [];
          _mentionQuery = '';
          _mentionAtIndex = null;
          _mentionCursor = null;
        });
      } else {
        // fallback: reload
        await _load();
        _input.clear(); _replyTo = null;
        if (mounted) {
          setState(() {
            _mentionResults = const [];
            _mentionQuery = '';
            _mentionAtIndex = null;
            _mentionCursor = null;
          });
        }
      }
    } finally {
      if (mounted) setState(() { _sending = false; });
    }
  }

  _MentionQuery? _extractMentionQuery(TextEditingController ctrl) {
    final sel = ctrl.selection;
    if (!sel.isValid) return null;
    final cursor = sel.baseOffset;
    if (cursor < 0 || cursor > ctrl.text.length) return null;
    final text = ctrl.text;
    final before = text.substring(0, cursor);
    final at = before.lastIndexOf('@');
    if (at < 0) return null;
    if (at > 0) {
      final prev = before.substring(at - 1, at);
      if (RegExp(r'[A-Za-z0-9_]').hasMatch(prev)) return null;
    }
    final token = before.substring(at + 1);
    if (token.isEmpty) return null;
    if (token.contains(RegExp(r'\s'))) return null;
    return _MentionQuery(query: token, atIndex: at, cursor: cursor);
  }

  Future<void> _onCommentChanged() async {
    final q = _extractMentionQuery(_input);
    if (q == null) {
      if (_mentionResults.isNotEmpty || _mentionSearching || _mentionQuery.isNotEmpty) {
        setState(() {
          _mentionResults = const [];
          _mentionQuery = '';
          _mentionAtIndex = null;
          _mentionCursor = null;
          _mentionSearching = false;
        });
      }
      return;
    }
    _mentionAtIndex = q.atIndex;
    _mentionCursor = q.cursor;
    if (q.query == _mentionQuery && _mentionResults.isNotEmpty) return;
    _mentionQuery = q.query;
    _mentionDebounce?.cancel();
    _mentionDebounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      final app = context.read<AppState>();
      final base = app.baseUrl; final user = app.username; final pass = await app.storage.read(key: 'password');
      if (base == null || user == null || pass == null) return;
      if (!_mentionMembersLoaded) {
        final boardId = app.activeBoard?.id;
        if (boardId != null) {
          _mentionBoardScoped = true;
          try {
            final members = await app.api.fetchBoardMemberUids(base, user, pass, boardId);
            if (mounted) {
              setState(() {
                _mentionMembers = members.map((e) => e.toLowerCase()).toSet();
                _mentionMembersLoaded = true;
              });
            }
          } catch (_) {}
        } else {
          _mentionMembersLoaded = true;
        }
      }
      setState(() { _mentionSearching = true; });
      try {
        final res = await app.api.searchSharees(base, user, pass, _mentionQuery);
        var users = res.where((u) => (u.shareType ?? 0) == 0).toList();
        if (_mentionMembers.isNotEmpty) {
          users = users.where((u) => _mentionMembers.contains(u.id.toLowerCase())).toList();
        } else if (_mentionBoardScoped && _mentionMembersLoaded) {
          users = const [];
        }
        if (!mounted) return;
        setState(() { _mentionResults = users; });
      } finally {
        if (mounted) setState(() { _mentionSearching = false; });
      }
    });
  }

  void _applyMention(UserRef userRef) {
    final q = _extractMentionQuery(_input);
    final atIndex = q?.atIndex ?? _mentionAtIndex;
    final cursor = q?.cursor ?? _mentionCursor;
    if (atIndex == null || cursor == null) return;
    final text = _input.text;
    final before = text.substring(0, atIndex);
    final after = text.substring(cursor);
    final id = userRef.id.trim();
    if (id.isEmpty) return;
    final needsQuotes = RegExp(r'[^A-Za-z0-9_.-]').hasMatch(id);
    final token = needsQuotes ? '@"$id"' : '@$id';
    final newText = before + token + ' ' + after;
    final newCursor = (before + token + ' ').length;
    _input.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursor),
    );
    setState(() {
      _mentionResults = const [];
      _mentionQuery = '';
      _mentionAtIndex = null;
      _mentionCursor = null;
    });
  }

  Widget _buildMentionSuggestions(BuildContext context) {
    if (!_mentionSearching && _mentionResults.isEmpty) return const SizedBox.shrink();
    final theme = CupertinoTheme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      constraints: const BoxConstraints(maxHeight: 160),
      decoration: BoxDecoration(
        color: theme.barBackgroundColor.withOpacity(0.95),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CupertinoColors.separator),
      ),
      child: _mentionSearching
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CupertinoActivityIndicator()),
            )
          : ListView(
              shrinkWrap: true,
              children: _mentionResults.map((u) {
                final dn = u.displayName.trim();
                final id = u.id.trim();
                final label = dn.isEmpty || dn.toLowerCase() == id.toLowerCase() ? id : '$dn ($id)';
                return CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  onPressed: () => _applyMention(u),
                  alignment: Alignment.centerLeft,
                  child: Text(label, style: TextStyle(color: CupertinoColors.label.resolveFrom(context))),
                );
              }).toList(),
            ),
    );
  }

  @override
  void dispose() {
    _input.dispose();
    _mentionDebounce?.cancel();
    super.dispose();
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
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: _buildMentionSuggestions(context),
            ),
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
                        onChanged: (_) => _onCommentChanged(),
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
          RichText(
            text: TextSpan(
              style: CupertinoTheme.of(context).textTheme.textStyle,
              children: _buildCommentSpans(
                comment,
                CupertinoTheme.of(context).textTheme.textStyle,
                CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                  color: CupertinoColors.activeBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
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

class _MentionQuery {
  final String query;
  final int atIndex;
  final int cursor;
  const _MentionQuery({required this.query, required this.atIndex, required this.cursor});
}

class _MentionMatch {
  final int start;
  final int end;
  final CommentMention mention;
  _MentionMatch({required this.start, required this.end, required this.mention});
}

List<InlineSpan> _buildCommentSpans(CommentItem comment, TextStyle baseStyle, TextStyle mentionStyle) {
  final message = comment.message;
  if (comment.mentions.isEmpty || message.isEmpty) {
    return [TextSpan(text: message, style: baseStyle)];
  }
  final matches = <_MentionMatch>[];
  for (final m in comment.mentions) {
    final id = m.mentionId;
    if (id.isEmpty) continue;
    final tokens = ['@"$id"', '@$id'];
    for (final t in tokens) {
      var idx = message.indexOf(t);
      while (idx >= 0) {
        matches.add(_MentionMatch(start: idx, end: idx + t.length, mention: m));
        idx = message.indexOf(t, idx + t.length);
      }
    }
  }
  if (matches.isEmpty) return [TextSpan(text: message, style: baseStyle)];
  matches.sort((a, b) => a.start.compareTo(b.start));
  final spans = <InlineSpan>[];
  var pos = 0;
  for (final m in matches) {
    if (m.start < pos) continue;
    if (m.start > pos) {
      spans.add(TextSpan(text: message.substring(pos, m.start), style: baseStyle));
    }
    final dn = m.mention.mentionDisplayName.isNotEmpty ? m.mention.mentionDisplayName : m.mention.mentionId;
    spans.add(TextSpan(text: '@$dn', style: mentionStyle));
    pos = m.end;
  }
  if (pos < message.length) {
    spans.add(TextSpan(text: message.substring(pos), style: baseStyle));
  }
  return spans;
}
