import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart' show showDatePicker, showTimePicker, TimeOfDay;
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'attachment_preview_page.dart';
import 'package:file_picker/file_picker.dart';

import '../state/app_state.dart';
import '../models/card_item.dart';
import '../models/label.dart';
import '../models/column.dart' as deck;
import '../widgets/markdown_editor.dart';
import '../models/user_ref.dart';
import '../models/comment.dart';
import '../l10n/app_localizations.dart';
// import 'labels_manage_page.dart';

class CardDetailPage extends StatefulWidget {
  final int cardId;
  final int? boardId;
  final int? stackId;
  final Color? bgColor;
  const CardDetailPage({super.key, required this.cardId, this.boardId, this.stackId, this.bgColor});

  @override
  State<CardDetailPage> createState() => _CardDetailPageState();
}

class _CardDetailPageState extends State<CardDetailPage> {
  CardItem? _card;
  List<Label> _allLabels = const [];
  List<deck.Column> _columns = const [];
  bool _loading = true;
  bool _saving = false;
  bool _uploadingAttachment = false;
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  Timer? _descDebounce;
  final FocusNode _descFocus = FocusNode();
  DateTime? _due;
  int? _currentStackId;
  // Comments state
  bool _commentsLoading = true;
  bool _sendingComment = false;
  List<CommentItem> _comments = const [];
  final TextEditingController _commentCtrl = TextEditingController();
  int? _replyTo;
  // Attachments
  bool _attachmentsLoading = true;
  List<Map<String, dynamic>> _attachments = const [];
  // Dirty flags to avoid overwriting local edits by background fetches
  bool _titleDirty = false;
  bool _descDirty = false;
  bool _dueDirty = false;
  bool _labelsDirty = false;
  bool _assigneesDirty = false;
  final Set<String> _assigneesHide = <String>{};
  bool _assigneesLoading = true;
  bool _initialFetchDone = false;

  bool get _isDoneCard => _card?.done != null;

  @override
  void initState() {
    super.initState();
    _load();
    _loadComments();
    _loadAttachments();
    _titleCtrl.addListener(() {
      // Mark as dirty while editing title (committed on submit)
      _titleDirty = true;
      if (mounted) setState(() {});
    });
    _descCtrl.addListener(() {
      _descDebounce?.cancel();
      _descDirty = true;
      _descDebounce = Timer(const Duration(milliseconds: 800), () {
        if (!mounted) return;
        _savePatch({'description': _descCtrl.text}, optimistic: true);
      });
    });
    _descFocus.addListener(() {
      if (!_descFocus.hasFocus) {
        _savePatch({'description': _descCtrl.text}, optimistic: true);
      }
    });
  }

  Future<void> _loadComments() async {
    final app = context.read<AppState>();
    final base = app.baseUrl; final user = app.username; final pass = await app.storage.read(key: 'password');
    if (base == null || user == null || pass == null) { setState(() { _commentsLoading = false; }); return; }
    setState(() { _commentsLoading = true; });
    try {
      final raw = await app.api.fetchCommentsRaw(base, user, pass, widget.cardId, limit: 100, offset: 0);
      final list = raw.map((e) => CommentItem.fromJson(e)).toList();
      if (!mounted) return;
      setState(() { _comments = list; });
      // Update meta counter for board list (only if still mounted)
      if (mounted) context.read<AppState>().setCardCommentsCount(widget.cardId, list.length);
    } finally {
      if (mounted) setState(() { _commentsLoading = false; });
    }
  }

  Future<void> _sendComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    final app = context.read<AppState>();
    final base = app.baseUrl; final user = app.username; final pass = await app.storage.read(key: 'password');
    if (base == null || user == null || pass == null) return;
    setState(() { _sendingComment = true; });
    try {
      final created = await app.api.createComment(base, user, pass, widget.cardId, message: text, parentId: _replyTo);
      if (created != null) {
        final c = CommentItem.fromJson(created);
        if (!mounted) return;
        setState(() { _comments = [..._comments, c]; _commentCtrl.clear(); _replyTo = null; });
        if (mounted) context.read<AppState>().setCardCommentsCount(widget.cardId, _comments.length);
      } else {
        await _loadComments();
        _commentCtrl.clear(); _replyTo = null;
      }
    } finally {
      if (mounted) setState(() { _sendingComment = false; });
    }
  }

  Future<void> _loadAttachments() async {
    final app = context.read<AppState>();
    final base = app.baseUrl; final user = app.username; final pass = await app.storage.read(key: 'password');
    if (base == null || user == null || pass == null) { setState(() { _attachmentsLoading = false; }); return; }
    final boardId = widget.boardId ?? app.activeBoard?.id;
    final stackId = _currentStackId ?? widget.stackId;
    if (boardId == null || stackId == null) { setState(() { _attachmentsLoading = false; }); return; }
    setState(() { _attachmentsLoading = true; });
    try {
      final list = await app.api.fetchCardAttachments(base, user, pass, boardId: boardId, stackId: stackId, cardId: widget.cardId);
      if (!mounted) return;
      setState(() { _attachments = list; });
      if (mounted) context.read<AppState>().setCardAttachmentsCount(widget.cardId, list.length);
    } finally {
      if (mounted) setState(() { _attachmentsLoading = false; });
    }
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final board = app.activeBoard;
    final baseUrl = app.baseUrl;
    final user = app.username;
    final pass = await app.storage.read(key: 'password');
    if (board == null || baseUrl == null || user == null || pass == null) {
      setState(() { _loading = false; _initialFetchDone = true; });
      return;
    }
    try {
      // Use cached columns/cards first for instant display
      final cols = app.columnsForActiveBoard();
      _columns = cols;
      final found = cols.expand((c) => c.cards).firstWhere((c) => c.id == widget.cardId, orElse: () => const CardItem(id: -1, title: ''));
      if (found.id != -1) {
        _card = found;
        _currentStackId = cols.firstWhere((c) => c.cards.contains(found)).id;
      }
      if (_card != null) {
        _titleCtrl.text = _card!.title;
        _descCtrl.text = _card!.description ?? '';
        _due = _card!.due;
      }
      // If we have cached data, show immediately; otherwise keep spinner until fetch completes
      if (mounted) setState(() { _loading = _card == null; _assigneesLoading = true; });
      // Background: fetch fresh single card if we have stack/board
      final stackId = widget.stackId ?? _currentStackId;
      if (widget.boardId != null && stackId != null && stackId != -1) {
        unawaited(() async {
          try {
            final cardJson = await app.api.fetchCard(baseUrl, user, pass, widget.boardId!, stackId, widget.cardId);
            if (!mounted) return;
            if (cardJson != null) {
              setState(() {
                final fetched = CardItem.fromJson(cardJson);
                _currentStackId = (cardJson['stackId'] ?? cardJson['stack']?['id']) as int? ?? _currentStackId;
                // Merge fetched with respect to dirty flags
                final next = CardItem(
                  id: fetched.id,
                  title: _titleDirty ? (_card?.title ?? fetched.title) : fetched.title,
                  description: _descDirty ? (_card?.description ?? fetched.description) : fetched.description,
                  due: _dueDirty ? (_card?.due ?? fetched.due) : fetched.due,
                  labels: _labelsDirty ? (_card?.labels ?? fetched.labels) : fetched.labels,
                  assignees: _assigneesDirty ? (_card?.assignees ?? fetched.assignees) : fetched.assignees,
                );
                _card = next;
                if (!_titleDirty) _titleCtrl.text = next.title;
                final fetchedDesc = next.description ?? '';
                if (!_descDirty) {
                  _descCtrl.text = fetchedDesc;
                }
                if (!_dueDirty) _due = next.due;
              });
            }
          } catch (_) {}
          finally {
            if (mounted) setState(() { _loading = false; _initialFetchDone = true; _assigneesLoading = false; });
          }
        }());
      } else {
        // No way to fetch a single card (missing ids); mark fetch done
        if (mounted) setState(() { _initialFetchDone = true; _assigneesLoading = false; });
      }
      // Background: prefetch board labels (detail) to speed up label sheet
      unawaited(() async {
        try {
          final detail = await app.api.fetchBoardDetail(baseUrl!, user!, pass!, board.id);
          if (detail != null && mounted) {
            final lbls = (detail['labels'] as List?)?.whereType<Map>().toList() ?? const [];
            if (lbls.isNotEmpty) {
              final map = <int, Label>{
                for (final l in _allLabels) l.id: l,
              };
              for (final e in lbls) {
                final id = (e['id'] as num?)?.toInt();
                if (id != null) {
                  map[id] = Label(id: id, title: (e['title'] ?? '').toString(), color: (e['color'] ?? '').toString());
                }
              }
              setState(() { _allLabels = map.values.toList(); });
            }
          }
        } catch (_) {}
      }());
    } catch (_) {
      // ignore for now; could show error
      if (mounted) setState(() { _loading = false; _initialFetchDone = true; });
    }
  }

  Future<void> _savePatch(Map<String, dynamic> patch, {int? useStackId, bool optimistic = false}) async {
    if (!mounted) return;
    final app = context.read<AppState>();
    // Prefer the boardId of the card when provided, else fall back to active board
    final boardId = widget.boardId ?? app.activeBoard?.id;
    final stackId = useStackId ?? _currentStackId ?? widget.stackId;
    if (boardId == null || stackId == null) return;
    // Always include key fields to avoid PUT clearing other properties
    final currentTitle = _titleCtrl.text.isNotEmpty ? _titleCtrl.text : (_card?.title ?? '');
    final currentDescText = _descCtrl.text;
    final includeDesc = !patch.containsKey('description');
    final includeDue = !patch.containsKey('duedate');
    final currentDueIso = _due?.toUtc().toIso8601String();
    final merged = <String, dynamic>{
      'title': currentTitle,
      if (includeDesc) 'description': currentDescText,
      if (includeDue && currentDueIso != null) 'duedate': currentDueIso,
      ...patch,
    };
    setState(() { _saving = true; });
    // Optimistic local update if requested
    final clearDue = merged.containsKey('duedate') && merged['duedate'] == null;
    if (optimistic) {
      app.updateLocalCard(
        boardId: boardId,
        stackId: stackId,
        cardId: widget.cardId,
        title: merged.containsKey('title') ? (_titleCtrl.text) : null,
        description: merged.containsKey('description') ? (_descCtrl.text) : null,
        due: merged.containsKey('duedate') ? _due : null,
        clearDue: clearDue,
      );
    }
    // Local Mode: keine Netz-Calls, nur lokale Aktualisierung
    final baseUrl = app.baseUrl; final user = app.username; final pass = await app.storage.read(key: 'password');
    if (app.localMode || baseUrl == null || user == null || pass == null) {
      // Hard-commit lokale Änderungen und Dirty-Flags zurücksetzen
      app.updateLocalCard(
        boardId: boardId,
        stackId: stackId,
        cardId: widget.cardId,
        title: merged.containsKey('title') ? (_titleCtrl.text) : null,
        description: merged.containsKey('description') ? (_descCtrl.text) : null,
        due: merged.containsKey('duedate') ? _due : null,
        clearDue: clearDue,
      );
      if (merged.containsKey('title')) _titleDirty = false;
      if (merged.containsKey('description')) _descDirty = false;
      if (merged.containsKey('duedate')) _dueDirty = false;
      if (mounted) setState(() { _saving = false; });
      return;
    }
    try {
      await app.updateCardAndRefresh(boardId: boardId, stackId: stackId, cardId: widget.cardId, patch: merged);
      if (merged.containsKey('title')) _titleDirty = false;
      if (merged.containsKey('description')) _descDirty = false;
      if (merged.containsKey('duedate')) _dueDirty = false;
    } finally {
      if (mounted) setState(() { _saving = false; });
    }
  }

  Color _panelColor(BuildContext context, AppState app) {
    final base = CupertinoColors.systemBackground.resolveFrom(context);
    return base.withOpacity(app.isDarkMode ? 0.9 : 0.96);
  }

  Future<void> _toggleDone(bool done) async {
    final doneAt = done ? DateTime.now().toUtc() : null;
    if (_card != null) {
      _card = CardItem(
        id: _card!.id,
        title: _card!.title,
        description: _card!.description,
        due: _card!.due,
        done: doneAt,
        labels: _card!.labels,
        assignees: _card!.assignees,
        order: _card!.order,
      );
    }
    if (mounted) setState(() {});
    await _savePatch({'done': doneAt}, optimistic: true);
  }

  Future<void> _clearDueDate() async {
    setState(() {
      _due = null;
      _dueDirty = true;
    });
    await _savePatch({'duedate': null}, optimistic: true);
  }

  Future<void> _saveDescriptionNow() async {
    await _savePatch({'description': _descCtrl.text}, optimistic: true);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return CupertinoPageScaffold(
      backgroundColor: widget.bgColor,
      navigationBar: CupertinoNavigationBar(
        middle: Text(_titleCtrl.text.isEmpty ? L10n.of(context).card : _titleCtrl.text, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _showShare,
              child: const Icon(CupertinoIcons.share),
            ),
            if (_saving) const CupertinoActivityIndicator(),
          ],
        ),
      ),
      child: _loading
          ? const Center(child: CupertinoActivityIndicator())
          : (_card == null && _initialFetchDone)
              ? Center(child: Text(L10n.of(context).cardLoadFailed))
              : SafeArea(
              child: LayoutBuilder(
                builder: (context, cns) {
                  final isWide = cns.maxWidth >= 900;
                  final panelColor = _panelColor(context, app);
                  final panelDecoration = BoxDecoration(
                    color: panelColor,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: CupertinoColors.black.withOpacity(app.isDarkMode ? 0.25 : 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  );
                  const panelPadding = EdgeInsets.all(12);
                  if (!isWide) {
                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Container(
                          decoration: panelDecoration,
                          padding: panelPadding,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              CupertinoTextField(
                                controller: _titleCtrl,
                                placeholder: L10n.of(context).title,
                                onSubmitted: (v) => _savePatch({'title': v}, optimistic: true),
                              ),
                              const SizedBox(height: 10),
                              _StatusRow(
                                label: L10n.of(context).status,
                                isDone: _isDoneCard,
                                onChanged: (v) => _toggleDone(v),
                                markDoneLabel: L10n.of(context).markDone,
                                markUndoneLabel: L10n.of(context).markUndone,
                              ),
                              const SizedBox(height: 12),
                              _SectionHeader(
                                title: L10n.of(context).descriptionLabel,
                                trailing: _SavingIndicator(visible: _saving),
                              ),
                              const SizedBox(height: 8),
                              MarkdownEditor(
                                controller: _descCtrl,
                                focusNode: _descFocus,
                                initialPreview: true,
                                placeholder: L10n.of(context).descriptionPlaceholder,
                                onSubmitted: (v) => _savePatch({'description': v}, optimistic: true),
                                onSave: _saveDescriptionNow,
                              ),
                              const SizedBox(height: 12),
                              _FieldRow(
                                label: L10n.of(context).dueDate,
                                value: _due == null ? '—' : _due!.toLocal().toString().substring(0, 16),
                                onTap: () => _pickDueDate(context),
                                trailing: _due == null
                                    ? null
                                    : CupertinoButton(
                                        padding: EdgeInsets.zero,
                                        onPressed: _clearDueDate,
                                        child: Semantics(
                                          label: L10n.of(context).removeDate,
                                          child: const Icon(CupertinoIcons.clear_circled, size: 20),
                                        ),
                                      ),
                              ),
                              _FieldRow(
                                label: L10n.of(context).column,
                                value: _columns.firstWhere((c) => c.id == _currentStackId, orElse: () => deck.Column(id: -1, title: '—', cards: const [])).title,
                                onTap: () => _pickStack(context),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(child: Text(L10n.of(context).labelsCaption, style: const TextStyle(fontWeight: FontWeight.w600))),
                                  CupertinoButton(
                                    padding: EdgeInsets.zero,
                                    onPressed: () => _editLabels(context),
                                    child: const Icon(CupertinoIcons.pencil_circle_fill, size: 22),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: (_card?.labels ?? const <Label>[]) 
                                    .map<Widget>((l) => _LabelPill(label: l, onRemove: () => _toggleLabel(l, remove: true)))
                                    .toList(),
                              ),
                              const SizedBox(height: 12),
                              Container(height: 1, color: CupertinoColors.separator),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(child: Text(L10n.of(context).assigned, style: const TextStyle(fontWeight: FontWeight.w600))),
                                  CupertinoButton(
                                    padding: EdgeInsets.zero,
                                    onPressed: () => _assignUser(context),
                                    child: const Icon(CupertinoIcons.pencil_circle_fill, size: 22),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              _assigneesLoading
                                  ? const CupertinoActivityIndicator()
                                  : Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: ((_card?.assignees ?? const <UserRef>[]) 
                                              .where((u) => !_assigneesHide.contains(u.id.toLowerCase()))
                                              .toList())
                                          .map<Widget>((u) => _AssigneePill(user: u, onRemove: () => _toggleAssignee(u, remove: true)))
                                          .toList(),
                                    ),
                              const SizedBox(height: 10),
                              Container(height: 1, color: CupertinoColors.separator),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(child: Text(L10n.of(context).attachments, style: const TextStyle(fontWeight: FontWeight.w600))),
                                  CupertinoButton(
                                    padding: EdgeInsets.zero,
                                    onPressed: _uploadingAttachment ? null : () async {
                          try {
                            final app = context.read<AppState>();
                            final base = app.baseUrl; final user = app.username; final pass = await app.storage.read(key: 'password');
                            if (base == null || user == null || pass == null) return;
                            setState(() { _uploadingAttachment = true; });
                            final picker = await Future.sync(() async => await _pickFile());
                            if (picker == null) { if (mounted) setState(() { _uploadingAttachment = false; }); return; }
                            final fileName = picker.name;
                            final bytes = picker.bytes;
                            if (bytes == null) {
                              if (mounted) {
                                setState(() { _uploadingAttachment = false; });
                                await showCupertinoDialog(
                                  context: context,
                                  builder: (ctx) => CupertinoAlertDialog(
                                    title: Text(L10n.of(context).uploadFailed),
                                    content: Text(L10n.of(context).fileReadFailed),
                                    actions: [
                                      CupertinoDialogAction(onPressed: () => Navigator.of(ctx).pop(), child: Text(L10n.of(context).ok)),
                                    ],
                                  ),
                                );
                              }
                              return;
                            }
                            final boardId = widget.boardId ?? app.activeBoard?.id;
                            final stackId = _currentStackId ?? widget.stackId;
                            if (boardId == null || stackId == null) {
                              if (mounted) {
                                await showCupertinoDialog(
                                  context: context,
                                  builder: (ctx) => CupertinoAlertDialog(
                                    title: Text(L10n.of(context).uploadNotPossible),
                                    content: Text(L10n.of(context).missingIds),
                                    actions: [CupertinoDialogAction(onPressed: () => Navigator.of(ctx).pop(), child: Text(L10n.of(context).ok))],
                                  ),
                                );
                              }
                              return;
                            }
                            // Preferred: direct Deck upload (multipart) per API docs
                            final okUp = await app.api.uploadCardAttachment(base, user!, pass, boardId: boardId, stackId: stackId, cardId: widget.cardId, bytes: bytes, filename: fileName);
                            if (okUp) {
                              await _loadAttachments();
                            } else {
                              if (mounted) {
                                await showCupertinoDialog(
                                  context: context,
                                  builder: (ctx) => CupertinoAlertDialog(
                                    title: Text(L10n.of(context).uploadFailed),
                                    content: Text(L10n.of(context).fileAttachFailed),
                                    actions: [CupertinoDialogAction(onPressed: () => Navigator.of(ctx).pop(), child: Text(L10n.of(context).ok))],
                                  ),
                                );
                              }
                            }
                            // done
                          } catch (_) {
                            // swallow, feedback already shown where possible
                          } finally {
                            if (mounted) setState(() { _uploadingAttachment = false; });
                          }
                        },
                        child: _uploadingAttachment
                            ? const CupertinoActivityIndicator()
                            : const Icon(CupertinoIcons.plus_circle, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_attachmentsLoading)
                    const Center(child: CupertinoActivityIndicator())
                  else if (_attachments.isEmpty)
                    Text(L10n.of(context).noAttachments, style: const TextStyle(color: CupertinoColors.systemGrey))
                  else
                    Column(
                      children: _attachments.map((a) {
                        final ext = (a['extendedData'] as Map?)?.cast<String, dynamic>();
                        final info = (ext?['info'] as Map?)?.cast<String, dynamic>();
                        final filenameOnly = (info?['filename'])?.toString();
                        final extensionOnly = (info?['extension'])?.toString();
                        final basename = (info?['basename'])?.toString();
                        String name = (a['title'] ?? a['fileName'] ?? a['data'] ?? L10n.of(context).attachmentFallback).toString();
                        if (basename != null && basename.isNotEmpty) {
                          name = basename;
                        } else if (filenameOnly != null && filenameOnly.isNotEmpty) {
                          name = extensionOnly != null && extensionOnly.isNotEmpty ? '$filenameOnly.$extensionOnly' : filenameOnly;
                        }
                        // Robust: ID aus mehreren Feldern und auch Strings akzeptieren
                        int? id;
                        final rawId = a['id'] ?? a['attachmentId'] ?? a['attachment_id'];
                        if (rawId is num) {
                          id = rawId.toInt();
                        } else if (rawId is String) {
                          id = int.tryParse(rawId);
                        }
                        final size = ((ext?['filesize'] ?? a['size']) as num?)?.toInt();
                        return Row(
                          children: [
                            Expanded(
                              child: CupertinoButton(
                                padding: EdgeInsets.zero,
                                onPressed: () async {
                                  final app = context.read<AppState>();
                                  final base = app.baseUrl; final user = app.username; final pass = await app.storage.read(key: 'password');
                                  final boardId = widget.boardId ?? app.activeBoard?.id;
                                  final stackId = _currentStackId ?? widget.stackId;
                                  if (base == null || user == null || pass == null) return;

                                  // Try to open web links directly (absolute or server-relative)
                                  final dataStr = (a['data'] ?? '').toString();
                                  if (dataStr.startsWith('http://') || dataStr.startsWith('https://') || dataStr.startsWith('/')) {
                                    try {
                                      final String b = (base ?? '').trim();
                                      final Uri uri = dataStr.startsWith('/')
                                          ? ((b.isEmpty || b == '/') ? Uri.parse(dataStr) : Uri.parse(b + dataStr))
                                          : Uri.parse(dataStr);
                                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                                    } catch (_) {}
                                    return;
                                  }

                                  // Prefer WebDAV path when present
                                  final ext = (a['extendedData'] as Map?)?.cast<String, dynamic>();
                                  final info = (ext?['info'] as Map?)?.cast<String, dynamic>();
                                  String? remotePath = (ext?['path'] ?? info?['path'] ?? info?['pathRelative'] ?? a['relativePath'] ?? a['path'] ?? a['data'])?.toString();
                                  if (remotePath != null && remotePath.isNotEmpty && !remotePath.startsWith('/')) {
                                    remotePath = '/$remotePath';
                                  }
                                  if (remotePath != null) {
                                    // normalize accidental double slashes except the initial one
                                    remotePath = remotePath.replaceAll(RegExp(r'/{2,}'), '/');
                                  }

                                  http.Response? res;
                                  if (remotePath != null && remotePath.isNotEmpty && user != null) {
                                    res = await app.api.webdavDownload(base, user, pass, user, remotePath);
                                  }
                                  // Fallback to Deck content endpoint
                                  if (res == null && boardId != null && stackId != null && id != null) {
                                    res = await app.api.fetchAttachmentContent(base, user!, pass, boardId: boardId, stackId: stackId, cardId: widget.cardId, attachmentId: id);
                                  }
                                  if (res == null) return;
                                  final mime = res.headers['content-type'];
                                  final bytes = res.bodyBytes;
                                  final isImage = (mime ?? '').startsWith('image/');
                                  if (isImage) {
                                    if (!mounted) return;
                                    Navigator.of(context).push(CupertinoPageRoute(builder: (_) => AttachmentPreviewPage(name: name, bytes: bytes, mime: mime)));
                                  } else {
                                    // Try to open file locally via url_launcher; fallback to Share sheet
                                    final tempDir = (await getTemporaryDirectory()).path;
                                    final path = '$tempDir/$name';
                                    final file = File(path);
                                    await file.writeAsBytes(bytes);
                                    try {
                                      final uri = Uri.file(path);
                                      final ok = await launchUrl(uri, mode: LaunchMode.platformDefault);
                                      if (!ok) {
                                        await Share.shareXFiles([XFile(path)], subject: name);
                                      }
                                    } catch (_) {
                                      await Share.shareXFiles([XFile(path)], subject: name);
                                    }
                                  }
                                },
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Row(
                                    children: [
                                      const Icon(CupertinoIcons.paperclip),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(size == null ? name : '$name (${(size/1024).toStringAsFixed(1)} KB)')),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (id != null)
                              CupertinoButton(
                                padding: EdgeInsets.zero,
                                onPressed: () async {
                                  final app = context.read<AppState>();
                                  final base = app.baseUrl; final user = app.username; final pass = await app.storage.read(key: 'password');
                                  if (base == null || user == null || pass == null) return;
                                  final boardId2 = widget.boardId ?? app.activeBoard?.id;
                                  final stackId2 = _currentStackId ?? widget.stackId;
                                  if (boardId2 == null || stackId2 == null) return;
                                  // Best-effort type detection for API (helps some servers): default file, link if URL
                                  final dataStr = (a['data'] ?? '').toString();
                                  // Treat absolute and server-relative links as URL-type attachments
                                  final isUrl = dataStr.startsWith('http://') || dataStr.startsWith('https://') || dataStr.startsWith('/');
                                  final delType = isUrl ? 'link' : 'file';
                                  final ok = await app.api.deleteCardAttachmentEnsureStack(base, user, pass, boardId: boardId2, stackId: stackId2, cardId: widget.cardId, attachmentId: id!, type: delType);
                                  if (ok) {
                                    setState(() {
                                      _attachments = _attachments.where((e) {
                                        final raw = e['id'] ?? e['attachmentId'] ?? e['attachment_id'];
                                        int? eId;
                                        if (raw is num) eId = raw.toInt();
                                        if (raw is String) eId = int.tryParse(raw);
                                        return eId != id;
                                      }).toList();
                                    });
                                    context.read<AppState>().setCardAttachmentsCount(widget.cardId, _attachments.length);
                                  }
                                  else {
                                    if (!mounted) return;
                                    await showCupertinoDialog(
                                      context: context,
                                      builder: (ctx) => CupertinoAlertDialog(
                                        title: Text(L10n.of(context).deleteFailed),
                                        content: Text(L10n.of(context).serverDeniedDeleteAttachment),
                                        actions: [
                                          CupertinoDialogAction(onPressed: () => Navigator.of(ctx).pop(), child: Text(L10n.of(context).ok)),
                                        ],
                                      ),
                                    );
                                  }
                                },
                                child: const Icon(CupertinoIcons.delete_simple, color: CupertinoColors.destructiveRed, size: 18),
                              ),
                          ],
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 8),
                  Container(height: 1, color: CupertinoColors.separator),
                  const SizedBox(height: 16),
                  Text(L10n.of(context).comments, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  if (_commentsLoading)
                    const Center(child: CupertinoActivityIndicator())
                  else if (_comments.isEmpty)
                    Text(L10n.of(context).noComments, style: const TextStyle(color: CupertinoColors.systemGrey))
                  else
                    Column(
                      children: _comments
                          .map((c) => _CommentTileInline(
                                comment: c,
                                isMine: (context.read<AppState>().username ?? '') == c.actorId,
                                onReply: (id) => setState(() => _replyTo = id),
                                onDelete: (id) async {
                                  final app = context.read<AppState>();
                                  final base = app.baseUrl; final user = app.username; final pass = await app.storage.read(key: 'password');
                                  if (base == null || user == null || pass == null) return;
                                  final ok = await app.api.deleteComment(base, user, pass, widget.cardId, id);
                                  if (ok) {
                                    setState(() { _comments = _comments.where((x) => x.id != id).toList(); });
                                    context.read<AppState>().setCardCommentsCount(widget.cardId, _comments.length);
                                  }
                                },
                              ))
                          .toList(),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (_replyTo != null) ...[
                        GestureDetector(
                          onTap: () => setState(() => _replyTo = null),
                          child: const Icon(CupertinoIcons.xmark_circle_fill, size: 18, color: CupertinoColors.systemGrey),
                        ),
                        const SizedBox(width: 6),
                        Text(L10n.of(context).reply, style: const TextStyle(color: CupertinoColors.systemGrey)),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: CupertinoTextField(
                          controller: _commentCtrl,
                          placeholder: L10n.of(context).writeComment,
                          maxLines: 3,
                          minLines: 1,
                          onSubmitted: (_) => _sendComment(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      CupertinoButton.filled(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        onPressed: _sendingComment ? null : _sendComment,
                        child: _sendingComment ? const CupertinoActivityIndicator() : const Icon(CupertinoIcons.paperplane),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      }
                  // Wide layout: left = description; right = all other fields stacked
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left: Title + Status + Description
                        Expanded(
                          flex: 2,
                          child: Container(
                            decoration: panelDecoration,
                            padding: panelPadding,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                CupertinoTextField(
                                  controller: _titleCtrl,
                                  placeholder: L10n.of(context).title,
                                  onSubmitted: (v) => _savePatch({'title': v}, optimistic: true),
                                ),
                                const SizedBox(height: 10),
                                _StatusRow(
                                  label: L10n.of(context).status,
                                  isDone: _isDoneCard,
                                  onChanged: (v) => _toggleDone(v),
                                  markDoneLabel: L10n.of(context).markDone,
                                  markUndoneLabel: L10n.of(context).markUndone,
                                ),
                                const SizedBox(height: 12),
                                _SectionHeader(
                                  title: L10n.of(context).descriptionLabel,
                                  trailing: _SavingIndicator(visible: _saving),
                                ),
                                const SizedBox(height: 6),
                                Expanded(
                                  child: CupertinoScrollbar(
                                    child: SingleChildScrollView(
                                      primary: false,
                                      child: MarkdownEditor(
                                        controller: _descCtrl,
                                        focusNode: _descFocus,
                                        initialPreview: true,
                                        placeholder: L10n.of(context).descriptionPlaceholder,
                                        onSubmitted: (v) => _savePatch({'description': v}, optimistic: true),
                                        onSave: _saveDescriptionNow,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),
                        // Right: other fields stacked
                        Expanded(
                          flex: 1,
                          child: Container(
                            decoration: panelDecoration,
                            padding: panelPadding,
                            child: SingleChildScrollView(
                              primary: false,
                              child: Column(
                                children: [
                                  _FieldRow(
                                    label: L10n.of(context).dueDate,
                                    value: _due == null ? '—' : _due!.toLocal().toString().substring(0, 16),
                                    onTap: () => _pickDueDate(context),
                                    trailing: _due == null
                                        ? null
                                        : CupertinoButton(
                                            padding: EdgeInsets.zero,
                                            onPressed: _clearDueDate,
                                            child: Semantics(
                                              label: L10n.of(context).removeDate,
                                              child: const Icon(CupertinoIcons.clear_circled, size: 20),
                                            ),
                                          ),
                                  ),
                                  _FieldRow(
                                    label: L10n.of(context).column,
                                    value: _columns.firstWhere((c) => c.id == _currentStackId, orElse: () => deck.Column(id: -1, title: '—', cards: const [])).title,
                                    onTap: () => _pickStack(context),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(child: Text(L10n.of(context).labelsCaption, style: const TextStyle(fontWeight: FontWeight.w600))),
                                      CupertinoButton(
                                        padding: EdgeInsets.zero,
                                        onPressed: () => _editLabels(context),
                                        child: const Icon(CupertinoIcons.pencil_circle_fill, size: 22),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: (_card?.labels ?? const <Label>[]) 
                                        .map<Widget>((l) => _LabelPill(label: l, onRemove: () => _toggleLabel(l, remove: true)))
                                        .toList(),
                                  ),
                                  const SizedBox(height: 12),
                                  Container(height: 1, color: CupertinoColors.separator),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(child: Text(L10n.of(context).assigned, style: const TextStyle(fontWeight: FontWeight.w600))),
                                      CupertinoButton(
                                        padding: EdgeInsets.zero,
                                        onPressed: () => _assignUser(context),
                                        child: const Icon(CupertinoIcons.pencil_circle_fill, size: 22),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  _assigneesLoading
                                      ? const CupertinoActivityIndicator()
                                      : Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: ((_card?.assignees ?? const <UserRef>[]) 
                                                  .where((u) => !_assigneesHide.contains(u.id.toLowerCase()))
                                                  .toList())
                                              .map<Widget>((u) => _AssigneePill(user: u, onRemove: () => _toggleAssignee(u, remove: true)))
                                              .toList(),
                                        ),
                                  const SizedBox(height: 8),
                                  Container(height: 1, color: CupertinoColors.separator),
                                  const SizedBox(height: 16),
                                  // Attachments (wide layout)
                                  Row(
                                    children: [
                                      Expanded(child: Text(L10n.of(context).attachments, style: const TextStyle(fontWeight: FontWeight.w600))),
                                      CupertinoButton(
                                        padding: EdgeInsets.zero,
                                        onPressed: _uploadingAttachment ? null : () async {
                                          try {
                                            final app = context.read<AppState>();
                                            final base = app.baseUrl; final user = app.username; final pass = await app.storage.read(key: 'password');
                                            if (base == null || user == null || pass == null) return;
                                            setState(() { _uploadingAttachment = true; });
                                            final picker = await Future.sync(() async => await _pickFile());
                                            if (picker == null) { if (mounted) setState(() { _uploadingAttachment = false; }); return; }
                                            final fileName = picker.name;
                                            final bytes = picker.bytes;
                                            if (bytes == null) {
                                              if (mounted) {
                                                setState(() { _uploadingAttachment = false; });
                                                await showCupertinoDialog(
                                                  context: context,
                                                  builder: (ctx) => CupertinoAlertDialog(
                                                    title: Text(L10n.of(context).uploadFailed),
                                                    content: const Text('Datei konnte nicht gelesen werden.'),
                                                    actions: [
                                                      CupertinoDialogAction(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
                                                    ],
                                                  ),
                                                );
                                              }
                                              return;
                                            }
                                            final boardId = widget.boardId ?? app.activeBoard?.id;
                                            final stackId = _currentStackId ?? widget.stackId;
                                            if (boardId == null || stackId == null) { if (mounted) setState(() { _uploadingAttachment = false; }); return; }
                                            // Deck multipart upload only (no WebDAV fallback)
                                            final okUp = await app.api.uploadCardAttachment(base, user, pass, boardId: boardId, stackId: stackId, cardId: widget.cardId, bytes: bytes, filename: fileName);
                                            if (okUp) {
                                              await _loadAttachments();
                                            } else {
                                              if (mounted) {
                                                await showCupertinoDialog(
                                                  context: context,
                                                    builder: (ctx) => CupertinoAlertDialog(
                                                      title: Text(L10n.of(context).uploadFailed),
                                                      content: Text(L10n.of(context).fileAttachFailed),
                                                      actions: [CupertinoDialogAction(onPressed: () => Navigator.of(ctx).pop(), child: Text(L10n.of(context).ok))],
                                                    ),
                                                );
                                              }
                                            }
                                            // done
                                          } catch (_) {
                                            // swallow
                                          } finally {
                                            if (mounted) setState(() { _uploadingAttachment = false; });
                                          }
                                        },
                                        child: _uploadingAttachment
                                            ? const CupertinoActivityIndicator()
                                            : const Icon(CupertinoIcons.plus_circle, size: 20),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (_attachmentsLoading)
                                    const Center(child: CupertinoActivityIndicator())
                                  else if (_attachments.isEmpty)
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(L10n.of(context).noAttachments, style: const TextStyle(color: CupertinoColors.systemGrey)),
                                    )
                                  else
                                    Column(
                                      children: _attachments.map((a) {
                                        final ext = (a['extendedData'] as Map?)?.cast<String, dynamic>();
                                        final info = (ext?['info'] as Map?)?.cast<String, dynamic>();
                                        final filenameOnly = (info?['filename'])?.toString();
                                        final extensionOnly = (info?['extension'])?.toString();
                                        final basename = (info?['basename'])?.toString();
                                        String name = (a['title'] ?? a['fileName'] ?? a['data'] ?? L10n.of(context).attachmentFallback).toString();
                                        if (basename != null && basename.isNotEmpty) {
                                          name = basename;
                                        } else if (filenameOnly != null && filenameOnly.isNotEmpty) {
                                          name = extensionOnly != null && extensionOnly.isNotEmpty ? '$filenameOnly.$extensionOnly' : filenameOnly;
                                        }
                                        // Robust: ID aus mehreren Feldern und auch Strings akzeptieren
                                        int? id;
                                        final rawId = a['id'] ?? a['attachmentId'] ?? a['attachment_id'];
                                        if (rawId is num) {
                                          id = rawId.toInt();
                                        } else if (rawId is String) {
                                          id = int.tryParse(rawId);
                                        }
                                        final size = ((ext?['filesize'] ?? a['size']) as num?)?.toInt();
                                        return Row(
                                          children: [
                                            // Open attachment on tap (wide layout)
                                            Expanded(
                                              child: CupertinoButton(
                                                padding: EdgeInsets.zero,
                                                onPressed: () async {
                                                  final app = context.read<AppState>();
                                                  final base = app.baseUrl; final user = app.username; final pass = await app.storage.read(key: 'password');
                                                  if (base == null || user == null || pass == null) return;

                                                  // Open web links directly
                                                  final dataStr = (a['data'] ?? '').toString();
                                                  if (dataStr.startsWith('http://') || dataStr.startsWith('https://') || dataStr.startsWith('/')) {
                                                    try {
                                                      final String b = (base ?? '').trim();
                                                      final Uri uri = dataStr.startsWith('/')
                                                          ? ((b.isEmpty || b == '/') ? Uri.parse(dataStr) : Uri.parse(b + dataStr))
                                                          : Uri.parse(dataStr);
                                                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                                                    } catch (_) {}
                                                    return;
                                                  }

                                                  // Prefer WebDAV path
                                                  final ext = (a['extendedData'] as Map?)?.cast<String, dynamic>();
                                                  final info = (ext?['info'] as Map?)?.cast<String, dynamic>();
                                                  String? remotePath = (ext?['path'] ?? info?['path'] ?? info?['pathRelative'] ?? a['relativePath'] ?? a['path'] ?? a['data'])?.toString();
                                                  if (remotePath != null && remotePath.isNotEmpty && !remotePath.startsWith('/')) {
                                                    remotePath = '/$remotePath';
                                                  }
                                                  if (remotePath != null) {
                                                    remotePath = remotePath.replaceAll(RegExp(r'/{2,}'), '/');
                                                  }

                                                  http.Response? res;
                                                  if (remotePath != null && remotePath.isNotEmpty && user != null) {
                                                    res = await app.api.webdavDownload(base, user, pass, user, remotePath);
                                                  }
                                                  // Fallback to Deck endpoint
                                                  if (res == null) {
                                                    final boardId = widget.boardId ?? app.activeBoard?.id;
                                                    final stackId = _currentStackId ?? widget.stackId;
                                                    if (boardId == null || stackId == null || id == null) return;
                                                    res = await app.api.fetchAttachmentContent(base, user!, pass, boardId: boardId, stackId: stackId, cardId: widget.cardId, attachmentId: id);
                                                    if (res == null) return;
                                                  }
                                                  final mime = res.headers['content-type'];
                                                  final bytes = res.bodyBytes;
                                                  final isImage = (mime ?? '').startsWith('image/');
                                                  if (isImage) {
                                                    if (!mounted) return;
                                                    Navigator.of(context).push(CupertinoPageRoute(builder: (_) => AttachmentPreviewPage(name: name, bytes: bytes, mime: mime)));
                                                  } else {
                                                    // Save to temp and open with system; fallback share
                                                    final tempDir = (await getTemporaryDirectory()).path;
                                                    final path = '$tempDir/$name';
                                                    final file = File(path);
                                                    await file.writeAsBytes(bytes);
                                                    try {
                                                      final uri = Uri.file(path);
                                                      final ok = await launchUrl(uri, mode: LaunchMode.platformDefault);
                                                      if (!ok) {
                                                        await Share.shareXFiles([XFile(path)], subject: name);
                                                      }
                                                    } catch (_) {
                                                      await Share.shareXFiles([XFile(path)], subject: name);
                                                    }
                                                  }
                                                },
                                                child: Align(
                                                  alignment: Alignment.centerLeft,
                                                  child: Row(
                                                    children: [
                                                      const Icon(CupertinoIcons.paperclip),
                                                      const SizedBox(width: 8),
                                                      Expanded(child: Text(size == null ? name : '$name (${(size/1024).toStringAsFixed(1)} KB)')),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                            if (id != null)
                                              CupertinoButton(
                                                padding: EdgeInsets.zero,
                                                onPressed: () async {
                                                  final app = context.read<AppState>();
                                                  final base = app.baseUrl; final user = app.username; final pass = await app.storage.read(key: 'password');
                                                  if (base == null || user == null || pass == null) return;
                                                  final boardId2 = widget.boardId ?? app.activeBoard?.id;
                                                  final stackId2 = _currentStackId ?? widget.stackId;
                                                  if (boardId2 == null || stackId2 == null) return;
                                                  final dataStr = (a['data'] ?? '').toString();
                                                  final isUrl = dataStr.startsWith('http://') || dataStr.startsWith('https://') || dataStr.startsWith('/');
                                                  final delType = isUrl ? 'link' : 'file';
                                                  final ok = await app.api.deleteCardAttachmentEnsureStack(base, user, pass, boardId: boardId2, stackId: stackId2, cardId: widget.cardId, attachmentId: id!, type: delType);
                                                  if (ok) setState(() {
                                                    _attachments = _attachments.where((e) {
                                                      final raw = e['id'] ?? e['attachmentId'] ?? e['attachment_id'];
                                                      int? eId;
                                                      if (raw is num) eId = raw.toInt();
                                                      if (raw is String) eId = int.tryParse(raw);
                                                      return eId != id;
                                                    }).toList();
                                                  });
                                                  else {
                                                    if (!mounted) return;
                                                    await showCupertinoDialog(
                                                      context: context,
                                                      builder: (ctx) => CupertinoAlertDialog(
                                                        title: Text(L10n.of(context).deleteFailed),
                                                        content: Text(L10n.of(context).serverDeniedDeleteAttachment),
                                                        actions: [
                                                          CupertinoDialogAction(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
                                                        ],
                                                      ),
                                                    );
                                                  }
                                                },
                                                child: const Icon(CupertinoIcons.delete_simple, color: CupertinoColors.destructiveRed, size: 18),
                                              ),
                                          ],
                                        );
                                      }).toList(),
                                    ),
                                  const SizedBox(height: 12),
                                  Container(height: 1, color: CupertinoColors.separator),
                                  const SizedBox(height: 16),
                                  // Comments (wide layout)
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(L10n.of(context).comments, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  ),
                                  const SizedBox(height: 8),
                                  if (_commentsLoading)
                                    const Center(child: CupertinoActivityIndicator())
                                  else if (_comments.isEmpty)
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(L10n.of(context).noComments, style: const TextStyle(color: CupertinoColors.systemGrey)),
                                    )
                                  else
                                    Column(
                                      children: _comments
                                          .map<Widget>((c) => _CommentTileInline(
                                                comment: c,
                                                isMine: (context.read<AppState>().username ?? '') == c.actorId,
                                                onReply: (id) => setState(() => _replyTo = id),
                                                onDelete: (id) async {
                                                  final app = context.read<AppState>();
                                                  final base = app.baseUrl; final user = app.username; final pass = await app.storage.read(key: 'password');
                                                  if (base == null || user == null || pass == null) return;
                                                  final ok = await app.api.deleteComment(base, user, pass, widget.cardId, id);
                                                  if (ok) setState(() { _comments = _comments.where((x) => x.id != id).toList(); });
                                                },
                                              ))
                                          .toList(),
                                    ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      if (_replyTo != null) ...[
                                        GestureDetector(
                                          onTap: () => setState(() => _replyTo = null),
                                          child: const Icon(CupertinoIcons.xmark_circle_fill, size: 18, color: CupertinoColors.systemGrey),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(L10n.of(context).reply, style: const TextStyle(color: CupertinoColors.systemGrey)),
                                        const SizedBox(width: 8),
                                      ],
                                      Expanded(
                                        child: CupertinoTextField(
                                          controller: _commentCtrl,
                                          placeholder: L10n.of(context).writeComment,
                                          maxLines: 3,
                                          minLines: 1,
                                          onSubmitted: (_) => _sendComment(),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      CupertinoButton.filled(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        onPressed: _sendingComment ? null : _sendComment,
                                        child: _sendingComment ? const CupertinoActivityIndicator() : const Icon(CupertinoIcons.paperplane),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Container(height: 1, color: CupertinoColors.separator),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }

  Future<void> _showShare() async {
    final app = context.read<AppState>();
    final boardId = widget.boardId ?? app.activeBoard?.id;
    final stackId = _currentStackId ?? widget.stackId;
    final baseUrl = app.baseUrl;
    final title = _titleCtrl.text.isEmpty ? (_card?.title ?? L10n.of(context).card) : _titleCtrl.text;
    final desc = _descCtrl.text.trim();
    String? webUrl;
    if (baseUrl != null && boardId != null && stackId != null) {
      final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
      webUrl = '$base/apps/deck/#/board/$boardId/stack/$stackId/card/${widget.cardId}';
    }
    await showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(L10n.of(context).share),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(ctx).pop();
              final content = [
                title,
                if (webUrl != null) webUrl,
                if (desc.isNotEmpty) '\n$desc',
              ].join('\n');
              Share.share(content, subject: title);
            },
            child: Text(L10n.of(context).systemShare),
          ),
          if (webUrl != null)
            CupertinoActionSheetAction(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await Clipboard.setData(ClipboardData(text: webUrl!));
              },
              child: Text(L10n.of(context).copyLink),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(),
          isDefaultAction: true,
          child: Text(L10n.of(context).cancel),
        ),
      ),
    );
  }

  Future<void> _pickDueDate(BuildContext context) async {
    final now = DateTime.now();
    final initial = _due ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
      helpText: L10n.of(context).dueDate,
    );
    if (date == null) return;
    final timeOfDay = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: L10n.of(context).timeLabel,
    );
    final selected = DateTime(
      date.year,
      date.month,
      date.day,
      timeOfDay?.hour ?? initial.hour,
      timeOfDay?.minute ?? initial.minute,
    );
    setState(() { _due = selected; _dueDirty = true; });
    await _savePatch({'duedate': selected.toUtc().toIso8601String()}, optimistic: true);
  }

  Future<void> _pickStack(BuildContext context) async {
    if (_columns.isEmpty) return;
    final idxCurrent = _columns.indexWhere((c) => c.id == _currentStackId);
    int sel = idxCurrent >= 0 ? idxCurrent : 0;
    await showCupertinoModalPopup(
      context: context,
      builder: (sheetContext) => Container(
        height: 260,
        color: CupertinoColors.systemBackground.resolveFrom(sheetContext),
        child: Column(
          children: [
            Expanded(
              child: CupertinoPicker(
                itemExtent: 36,
                scrollController: FixedExtentScrollController(initialItem: sel),
                onSelectedItemChanged: (v) => sel = v,
                children: _columns
                    .map((c) => Center(
                          child: Text(
                            c.title,
                            style: TextStyle(color: CupertinoColors.label.resolveFrom(sheetContext)),
                          ),
                        ))
                    .toList(),
              ),
            ),
            CupertinoButton(
              child: Text(L10n.of(context).move),
              onPressed: () => Navigator.of(sheetContext).pop(),
            )
          ],
        ),
      ),
    );
    final prevStack = _currentStackId;
    final newStack = _columns[sel].id;
    setState(() { _currentStackId = newStack; });
    // Optimistic local move
    final app = context.read<AppState>();
    final boardId = widget.boardId ?? app.activeBoard?.id;
    if (boardId != null) {
      app.updateLocalCard(boardId: boardId, stackId: prevStack!, cardId: widget.cardId, moveToStackId: newStack);
    }
    // Direkt per Update-API mit priorisiertem Zielpfad verschieben (schneller, weniger Requests)
    await _savePatch({'stackId': newStack}, useStackId: prevStack);
  }

  Future<void> _editLabels(BuildContext context) async {
    // Build label list: aggregate from cards + complement with board detail/boards list if available
    final app = context.read<AppState>();
    final cols = app.columnsForActiveBoard();
    final map = <int, Label>{};
    for (final c in cols.expand((c) => c.cards)) {
      for (final l in c.labels) { map[l.id] = l; }
    }
    try {
      final baseUrl = app.baseUrl; final user = app.username; final pass = await app.storage.read(key: 'password');
      final boardId = app.activeBoard?.id ?? widget.boardId;
      if (baseUrl != null && user != null && pass != null && boardId != null) {
        // Prefer board detail (tends to include labels)
        final detail = await app.api.fetchBoardDetail(baseUrl, user, pass, boardId);
        List? lbls;
        if (detail != null) {
          lbls = detail['labels'] as List?;
        }
        if (lbls == null) {
          // Fallback: boards list entry
          final boards = await app.api.fetchBoardsRaw(baseUrl, user, pass);
          final current = boards.firstWhere((b) => (b['id'] as num?)?.toInt() == boardId, orElse: () => const {});
          lbls = current['labels'] as List?;
        }
        if (lbls != null) {
          for (final e in lbls.whereType<Map>()) {
            final id = (e['id'] as num?)?.toInt();
            final title = (e['title'] ?? e['name'] ?? '').toString();
            final color = (e['color'] ?? '').toString();
            if (id != null) map[id] = Label(id: id, title: title, color: color);
          }
        }
      }
    } catch (_) {}
    _allLabels = map.values.toList();
    final selected = Set<int>.from((_card?.labels ?? const []).map((l) => l.id));
    await showCupertinoModalPopup(
      context: context,
      builder: (sheetContext) {
        final app = context.read<AppState>();
        return CupertinoActionSheet(
          title: Text(L10n.of(context).labels),
          message: SizedBox(
            height: 260,
            child: ListView(
              children: [
                ..._allLabels.map((l) => CupertinoActionSheetAction(
                      onPressed: () async {
                        Navigator.of(sheetContext).pop();
                        await _toggleLabel(l, remove: selected.contains(l.id));
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(l.title.isEmpty ? 'Label ${l.id}' : l.title),
                          if (selected.contains(l.id)) const Icon(CupertinoIcons.check_mark)
                        ],
                      ),
                    )),
                if (app.localMode)
                  CupertinoActionSheetAction(
                    onPressed: () async {
                      Navigator.of(sheetContext).pop();
                      final ctrl = TextEditingController();
                      await showCupertinoDialog(
                        context: context,
                        builder: (ctx) => CupertinoAlertDialog(
                          title: Text(L10n.of(context).newLabel),
                          content: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: CupertinoTextField(
                              controller: ctrl,
                              placeholder: L10n.of(context).title,
                              autofocus: true,
                            ),
                          ),
                          actions: [
                            CupertinoDialogAction(onPressed: () => Navigator.of(ctx).pop(), child: Text(L10n.of(context).cancel)),
                            CupertinoDialogAction(
                              isDefaultAction: true,
                              onPressed: () {
                                Navigator.of(ctx).pop();
                              },
                              child: Text(L10n.of(context).create),
                            ),
                          ],
                        ),
                      );
                      final t = ctrl.text.trim();
                      if (t.isNotEmpty) {
                        final newLabel = Label(id: -DateTime.now().millisecondsSinceEpoch, title: t, color: '#AAAAAA');
                        await _toggleLabel(newLabel, remove: false);
                      }
                    },
                    child: Text(L10n.of(context).addNewLabel),
                  ),
              ],
            ),
          ),
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop(),
            isDefaultAction: true,
            child: Text(L10n.of(context).cancel),
          ),
        );
      },
    );
  }

  Future<void> _toggleLabel(Label label, {required bool remove}) async {
    if (_card == null) return;
    final current = List<Label>.from(_card!.labels);
    final next = remove
        ? current.where((l) => l.id != label.id).toList()
        : (current..removeWhere((l) => l.id == label.id))..add(label);
    // Optimistic local update
    setState(() {
      _saving = true;
      _labelsDirty = true;
      _card = CardItem(
        id: _card!.id,
        title: _card!.title,
        description: _card!.description,
        due: _card!.due,
        labels: next,
        assignees: _card!.assignees,
      );
    });
    // push to app state immediately for board list consistency
    final app = context.read<AppState>();
    final bIdInit = app.activeBoard?.id ?? widget.boardId;
    final sIdInit = _currentStackId ?? widget.stackId;
    if (bIdInit != null && sIdInit != null) {
      app.updateLocalCard(boardId: bIdInit, stackId: sIdInit, cardId: widget.cardId, setLabels: next);
    }
    // Persist: try API v1.1 assign/remove first, then updateCard; else rollback
    final baseUrl = app.baseUrl; final user = app.username; final pass = await app.storage.read(key: 'password');
    final bId = app.activeBoard?.id ?? widget.boardId;
    final sId = _currentStackId ?? widget.stackId;
    bool ok = false;
    if (baseUrl != null && user != null && pass != null && bId != null && sId != null) {
      try {
        if (remove) {
          await app.api.removeLabelFromCard(baseUrl, user, pass, widget.cardId, label.id, boardId: bId, stackId: sId);
        } else {
          await app.api.addLabelToCard(baseUrl, user, pass, widget.cardId, label.id, boardId: bId, stackId: sId);
        }
        ok = true;
        if (app.activeBoard != null) unawaited(app.refreshColumnsFor(app.activeBoard!));
      } catch (_) {}
    }
    if (!ok) {
      // Fallback via updateCard labels field
      final labelIds = next.map((e) => e.id).toList();
      try {
        await _savePatch({'labels': labelIds}, optimistic: true);
        ok = true;
      } catch (_) {}
    }
    if (!ok) {
      // Revert on failure
      setState(() {
        _card = CardItem(
          id: _card!.id,
          title: _card!.title,
          description: _card!.description,
          due: _card!.due,
          labels: current,
          assignees: _card!.assignees,
        );
        _labelsDirty = false;
      });
    }
    // sync app state columns immediately
    final boardId = app.activeBoard?.id ?? widget.boardId;
    final stackId = _currentStackId ?? widget.stackId;
    if (boardId != null && stackId != null) {
      app.updateLocalCard(boardId: boardId, stackId: stackId, cardId: widget.cardId, setLabels: ok ? next : current);
    }
    // after success, fetch fresh card to ensure final state matches server
    if (ok && boardId != null && stackId != null && app.baseUrl != null && app.username != null) {
      unawaited(() async {
        try {
          final pass2 = await app.storage.read(key: 'password');
          final fresh = await app.api.fetchCard(app.baseUrl!, app.username!, pass2 ?? '', boardId, stackId, widget.cardId);
          if (fresh != null && mounted) {
            final c = CardItem.fromJson(fresh);
            setState(() { _card = c; _labelsDirty = false; });
            app.updateLocalCard(boardId: boardId, stackId: stackId, cardId: widget.cardId, setLabels: c.labels);
          }
        } catch (_) {}
      }());
    }
    // Do not trigger full board refresh here to keep UI snappy; autosync/next actions will refresh
    if (mounted) setState(() { _saving = false; });
  }

  Future<void> _assignUser(BuildContext context) async {
    final app = context.read<AppState>();
    final baseUrl = app.baseUrl; final user = app.username; final pass = await app.storage.read(key: 'password');
    if (baseUrl == null || user == null || pass == null) return;
    final queryCtrl = TextEditingController();
    List<UserRef> results = const [];
    Timer? debounce;
    bool searching = false;
    // Persist current user and board owner across StatefulBuilder rebuilds
    UserRef? meRef;
    UserRef? ownerRef;
    // Restrict to board members when available
    Set<String> members = {};
    final boardId = widget.boardId ?? app.activeBoard?.id;
    if (boardId != null) {
      try { members = await app.api.fetchBoardMemberUids(baseUrl, user, pass, boardId); } catch (_) {}
      // Normalize to lowercase to avoid case-mismatch between sharees.id and board member uids
      members = members.map((e) => e.toLowerCase()).toSet();
    }
    // Preload current user and board owner once to avoid per-keystroke requests
    try { meRef = await app.api.fetchCurrentUser(baseUrl, user, pass); } catch (_) {}
    if (boardId != null) {
      try {
        final detail = await app.api.fetchBoardDetail(baseUrl, user, pass, boardId);
        if (detail != null) {
          final owner = detail['owner'];
          if (owner is Map) {
            final uid = (owner['uid'] ?? owner['id'] ?? '').toString();
            final dnRaw = (owner['displayname'] ?? owner['displayName'] ?? owner['name'] ?? owner['label'] ?? '').toString();
            if (uid.isNotEmpty) {
              final dn = dnRaw.isEmpty ? uid : dnRaw;
              ownerRef = UserRef(id: uid, displayName: dn, shareType: 0);
            }
          }
        }
      } catch (_) {}
    }
    // Start with a visible spinner and trigger initial search once the sheet is shown
    searching = true;
    bool _initialSearchTriggered = false;
    await showCupertinoModalPopup(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
    Future<void> Function()? runSearch;
    runSearch = () async {
      setS(() { searching = true; });
      try {
        results = await app.api.searchSharees(baseUrl, user, pass, queryCtrl.text.trim());
      } finally {
        setS(() { searching = false; });
      }
    };
    if (!_initialSearchTriggered) {
      _initialSearchTriggered = true;
      // run once after build
      Future.microtask(() => runSearch?.call());
    }
        final q = queryCtrl.text.trim().toLowerCase();
        var filtered = results
            .where((r) => (r.shareType ?? 0) == 0)
            // Client-side name matching: ONLY display name or account id (case-insensitive)
            .where((r) {
              if (q.isEmpty) return true;
              final dn = r.displayName.toLowerCase();
              final id = r.id.toLowerCase();
              return dn.contains(q) || id.contains(q);
            })
            .toList();
        // Restrict to board members when we have the set
        if (members.isNotEmpty) {
          filtered = filtered.where((r) => members.contains(r.id.toLowerCase())).toList();
        }
        // Ensure current user is visible when query matches own name/id
        if (meRef != null) {
          final meId = meRef!.id.toLowerCase();
          final meDn = meRef!.displayName.toLowerCase();
          final match = q.isEmpty || meId.contains(q) || meDn.contains(q);
          final already = filtered.any((r) => r.id.toLowerCase() == meId);
          final allowed = members.isEmpty || members.contains(meId);
          if (match && !already && allowed) {
            filtered = [meRef!, ...filtered];
          }
        }
        // Ensure board owner is also visible if matches and not present
        if (ownerRef != null) {
          final oid = ownerRef!.id.toLowerCase();
          final odn = ownerRef!.displayName.toLowerCase();
          final match = q.isEmpty || oid.contains(q) || odn.contains(q);
          final already = filtered.any((r) => r.id.toLowerCase() == oid);
          final allowed = members.isEmpty || members.contains(oid);
          if (match && !already && allowed) {
            filtered = [ownerRef!, ...filtered];
          }
        }
        return CupertinoActionSheet(
          title: Text(L10n.of(context).assignTo),
          message: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CupertinoTextField(
                controller: queryCtrl,
                placeholder: L10n.of(context).userOrGroupSearch,
                onChanged: (v) {
                  debounce?.cancel();
                  debounce = Timer(const Duration(milliseconds: 500), () => runSearch?.call());
                },
                onSubmitted: (_) => runSearch?.call(),
              ),
              const SizedBox(height: 8),
              if (searching) const CupertinoActivityIndicator() else ...[
                SizedBox(
                  height: 260,
                  child: ListView(
                    children: filtered
                        .map((u) => CupertinoActionSheetAction(
                              onPressed: () async {
                                Navigator.of(ctx).pop();
                                await _toggleAssignee(u, remove: false);
                              },
                              child: Text(
                                (() {
                                  final dn = u.displayName.trim();
                                  final id = u.id.trim();
                                  if (dn.isEmpty) return id;
                                  if (dn.toLowerCase() == id.toLowerCase()) return dn;
                                  return '$dn ($id)';
                                })(),
                                style: TextStyle(color: CupertinoColors.label.resolveFrom(ctx)),
                              ),
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
            child: Text(L10n.of(context).cancel),
          ),
        );
      }),
    );
  }

  Future<void> _toggleAssignee(UserRef userRef, {required bool remove}) async {
    final app = context.read<AppState>();
    final baseUrl = app.baseUrl; final user = app.username; final pass = await app.storage.read(key: 'password');
    if (baseUrl == null || user == null || pass == null) return;
    if (_card == null) return;
    setState(() { _saving = true; _assigneesDirty = true; });
    // Immediate visual feedback: hide pill optimistically on remove; unhide on add
    final idLower = userRef.id.toLowerCase();
    if (remove) {
      setState(() { _assigneesHide.add(idLower); });
    } else {
      setState(() { _assigneesHide.remove(idLower); });
    }
    // optimistic local update
    final current = List<UserRef>.from(_card!.assignees);
    final next = remove ? current.where((u) => u.id != userRef.id).toList() : (current..removeWhere((u) => u.id == userRef.id))..add(userRef);
    setState(() {
      _card = CardItem(
        id: _card!.id,
        title: _card!.title,
        description: _card!.description,
        due: _card!.due,
        labels: _card!.labels,
        assignees: next,
      );
    });
    final bId2 = app.activeBoard?.id ?? widget.boardId;
    final sId2 = _currentStackId ?? widget.stackId;
    if (bId2 != null && sId2 != null) {
      app.updateLocalCard(boardId: bId2, stackId: sId2, cardId: widget.cardId, setAssignees: next);
    }
    bool ok = false;
    String? err;
    try {
      if (bId2 != null && sId2 != null) {
        if (remove) {
          await app.api.unassignUserFromCard(baseUrl, user, pass, boardId: bId2, stackId: sId2, cardId: widget.cardId, userId: userRef.id);
        } else {
          await app.api.assignUserToCard(baseUrl, user, pass, boardId: bId2, stackId: sId2, cardId: widget.cardId, userId: userRef.id);
        }
        ok = true;
      }
      if (!ok) {
        // Try updateCard with assignedUsers list
        final ids = next.map((u) => u.id).toList();
        try {
          await _savePatch({'assignedUsers': ids}, optimistic: true);
          ok = true;
        } catch (e) {
          err = e.toString();
        }
      }
      if (!ok) {
        // fallback old endpoints
        try {
          if (remove) {
            await app.api.removeAssigneeFromCard(baseUrl, user, pass, widget.cardId, userRef.id);
          } else {
            await app.api.addAssigneeToCard(baseUrl, user, pass, widget.cardId, userRef.id);
          }
          ok = true;
        } catch (e) {
          err = e.toString();
        }
      }
      if (ok) {
        // fetch fresh card to ensure UI and board state exactly match server
        final boardId = app.activeBoard?.id ?? widget.boardId;
        final stackId = _currentStackId ?? widget.stackId;
        if (boardId != null && stackId != null) {
          unawaited(() async {
            try {
              final fresh = await app.api.fetchCard(baseUrl, user, pass, boardId, stackId, widget.cardId);
              if (fresh != null && mounted) {
                final c = CardItem.fromJson(fresh);
                setState(() { _card = c; _assigneesDirty = false; });
                app.updateLocalCard(boardId: boardId, stackId: stackId, cardId: widget.cardId, setAssignees: c.assignees);
              }
            } catch (_) {}
          }());
        }
      }
    } finally {
      if (!ok) {
        // revert
        setState(() {
          _assigneesHide.remove(idLower); // show back if operation failed
          _card = CardItem(
            id: _card!.id,
            title: _card!.title,
            description: _card!.description,
            due: _card!.due,
            labels: _card!.labels,
            assignees: current,
          );
        });
        if (bId2 != null && sId2 != null) {
          app.updateLocalCard(boardId: bId2, stackId: sId2, cardId: widget.cardId, setAssignees: current);
        }
        // show friendly error if user not part of board
        final msg = (err != null && err!.toLowerCase().contains('not part of the board'))
            ? 'Benutzer ist kein Mitglied dieses Boards.'
            : 'Zuweisung fehlgeschlagen.';
        // non-blocking info dialog
        // ignore if context is not mounted
        if (mounted) {
          // Use a lightweight CupertinoAlertDialog
          // Delay slightly to avoid setState conflicts
          Future.microtask(() {
            showCupertinoDialog(
              context: context,
              builder: (ctx) => CupertinoAlertDialog(
                title: Text(L10n.of(context).hint),
                content: Text(msg),
                actions: [
                  CupertinoDialogAction(onPressed: () => Navigator.of(ctx).pop(), child: Text(L10n.of(context).ok)),
                ],
              ),
            );
          });
        }
      }
      if (mounted) setState(() { _saving = false; });
    }
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _descDebounce?.cancel();
    _descFocus.dispose();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }
}

class _PickedFile {
  final String name;
  final List<int>? bytes;
  _PickedFile({required this.name, required this.bytes});
}

Future<_PickedFile?> _pickFile() async {
  try {
    final res = await FilePicker.platform.pickFiles(
      withData: false, // prefer stream/path on iOS for reliability
      allowMultiple: false,
      type: FileType.any,
      allowCompression: false,
    );
    if (res == null || res.files.isEmpty) return null;
    final f = res.files.first;
    List<int>? data = f.bytes;
    // Try readStream first (best for iOS security-scoped URLs)
    if (data == null && f.readStream != null) {
      try {
        final chunks = <int>[];
        await for (final chunk in f.readStream!) { chunks.addAll(chunk); }
        data = chunks;
      } catch (_) {}
    }
    // Fallback to file path
    if (data == null && f.path != null && !kIsWeb) {
      try { data = await File(f.path!).readAsBytes(); } catch (_) {}
    }
    return _PickedFile(name: f.name, bytes: data);
  } catch (_) {
    return null;
  }
}

class _CommentTileInline extends StatelessWidget {
  final CommentItem comment;
  final bool isMine;
  final ValueChanged<int> onReply;
  final ValueChanged<int> onDelete;
  const _CommentTileInline({required this.comment, required this.isMine, required this.onReply, required this.onDelete});

  @override
  Widget build(BuildContext context) {
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

class _LabelPill extends StatelessWidget {
  final Label label;
  final VoidCallback onRemove;
  const _LabelPill({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    Color bg = CupertinoColors.systemGrey4;
    // best-effort parse
    String s = label.color.trim();
    if (s.isNotEmpty) {
      if (s.startsWith('#')) s = s.substring(1);
      if (s.length == 3) s = s.split('').map((c) => '$c$c').join();
      if (s.length == 6) s = 'FF$s';
      final val = int.tryParse(s, radix: 16);
      if (val != null) bg = Color(val);
    }
    final textColor = _bestTextColor(bg);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.title.isEmpty ? 'Label' : label.title,
              style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: Icon(CupertinoIcons.clear_circled_solid, size: 16, color: textColor.withOpacity(0.8)),
          ),
        ],
      ),
    );
  }
}

Color _bestTextColor(Color bg) {
  final r = bg.red / 255.0;
  final g = bg.green / 255.0;
  final b = bg.blue / 255.0;
  double lum(double c) => c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  final L = 0.2126 * lum(r) + 0.7152 * lum(g) + 0.0722 * lum(b);
  return L > 0.5 ? CupertinoColors.black : CupertinoColors.white;
}

class _FieldRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;
  final Widget? trailing;
  const _FieldRow({required this.label, required this.value, this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: CupertinoColors.separator)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: CupertinoColors.secondaryLabel.resolveFrom(context)),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 6),
              trailing!,
            ],
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(color: CupertinoColors.label.resolveFrom(context)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const _SectionHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _SavingIndicator extends StatelessWidget {
  final bool visible;
  const _SavingIndicator({required this.visible});

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return const CupertinoActivityIndicator(radius: 8);
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final bool isDone;
  final ValueChanged<bool> onChanged;
  final String markDoneLabel;
  final String markUndoneLabel;
  const _StatusRow({
    required this.label,
    required this.isDone,
    required this.onChanged,
    required this.markDoneLabel,
    required this.markUndoneLabel,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = CupertinoColors.label.resolveFrom(context);
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
        Text(isDone ? markUndoneLabel : markDoneLabel, style: TextStyle(color: textColor)),
        const SizedBox(width: 8),
        CupertinoSwitch(value: isDone, onChanged: onChanged),
      ],
    );
  }
}

class _AssigneePill extends StatelessWidget {
  final UserRef user;
  final VoidCallback onRemove;
  const _AssigneePill({required this.user, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final bg = CupertinoColors.tertiarySystemFill.resolveFrom(context);
    final fg = CupertinoColors.label.resolveFrom(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            user.displayName.isEmpty ? user.id : user.displayName,
            style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: Icon(CupertinoIcons.clear_circled_solid, size: 16, color: fg),
          ),
        ],
      ),
    );
  }
}
