import 'package:flutter/cupertino.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../l10n/app_localizations.dart';
import 'package:markdown/markdown.dart' as md;

class MarkdownEditor extends StatefulWidget {
  final TextEditingController controller;
  final String? placeholder;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final bool initialPreview;
  final Future<void> Function()? onSave;
  const MarkdownEditor({
    super.key,
    required this.controller,
    this.placeholder,
    this.onSubmitted,
    this.focusNode,
    this.initialPreview = true,
    this.onSave,
  });

  @override
  State<MarkdownEditor> createState() => _MarkdownEditorState();
}

class _MarkdownEditorState extends State<MarkdownEditor> {
  late bool _preview;

  @override
  void initState() {
    super.initState();
    _preview = widget.initialPreview;
  }

  @override
  Widget build(BuildContext context) {
    final theme = CupertinoTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Toolbar(
          onAction: _applyAction,
          onShowTemplates: _showTemplates,
          onShowHelp: _showHelp,
          preview: _preview,
          onEnterEdit: _enterEdit,
          onSave: _saveAndExit,
        ),
        const SizedBox(height: 8),
        if (!_preview)
          CupertinoTextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            placeholder: widget.placeholder ?? L10n.of(context).descriptionMarkdown,
            maxLines: 8,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            placeholderStyle: TextStyle(
              color: (CupertinoTheme.of(context).textTheme.textStyle.color ?? CupertinoColors.label).withOpacity(0.6),
            ),
            onSubmitted: widget.onSubmitted,
          )
        else
          GestureDetector(
            onTap: _enterEdit,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 160),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: CupertinoColors.separator.resolveFrom(context)),
                ),
                child: _PreviewWithTasks(
                  text: widget.controller.text,
                  onToggleTask: (lineIndex) => _toggleTaskAt(lineIndex),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _showTemplates() {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(L10n.of(context).formatTemplates),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () { Navigator.of(ctx).pop(); _insertTaskTemplate(); },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [const Icon(CupertinoIcons.square_list), const SizedBox(width: 8), Text(L10n.of(context).taskList)],
            ),
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

  void _showHelp() {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(L10n.of(context).markdownHelp),
        message: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(L10n.of(context).helpHeading),
            const SizedBox(height: 4),
            Text(L10n.of(context).helpBoldItalic),
            const SizedBox(height: 4),
            Text(L10n.of(context).helpStrike),
            const SizedBox(height: 4),
            Text(L10n.of(context).helpCode),
            const SizedBox(height: 4),
            Text(L10n.of(context).helpList),
            const SizedBox(height: 4),
            Text(L10n.of(context).helpTasks),
            const SizedBox(height: 4),
            Text(L10n.of(context).helpLink),
            const SizedBox(height: 4),
            Text(L10n.of(context).helpLinebreak),
          ],
        ),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(),
          isDefaultAction: true,
          child: Text(L10n.of(context).close),
        ),
      ),
    );
  }

  void _insertTaskTemplate() {
    final tpl = '- [ ] Aufgabe 1\n- [ ] Aufgabe 2\n- [x] Erledigt';
    final text = widget.controller.text;
    final sel = widget.controller.selection;
    if (sel.isValid) {
      final before = text.substring(0, sel.start);
      final after = text.substring(sel.end);
      final newText = before + tpl + after;
      final newOffset = (before + tpl).length;
      widget.controller.value = TextEditingValue(text: newText, selection: TextSelection.collapsed(offset: newOffset));
    } else {
      widget.controller.text = (text.isEmpty ? tpl : (text.trimRight() + '\n\n' + tpl));
      widget.controller.selection = TextSelection.collapsed(offset: widget.controller.text.length);
    }
    if (mounted) setState(() { _preview = false; });
  }

  void _applyAction(_MdAction a) {
    final text = widget.controller.text;
    final sel = widget.controller.selection;
    final hasSel = sel.isValid && sel.start >= 0 && sel.end >= sel.start;
    final before = hasSel ? text.substring(0, sel.start) : text;
    final selected = hasSel ? text.substring(sel.start, sel.end) : '';
    final after = hasSel ? text.substring(sel.end) : '';

    String replace;
    int cursorOffset = 0;
    switch (a) {
      case _MdAction.bold:
        replace = '**${selected.isEmpty ? L10n.of(context).mdBold : selected}**';
        cursorOffset = selected.isEmpty ? 2 : replace.length;
        break;
      case _MdAction.italic:
        replace = '*${selected.isEmpty ? L10n.of(context).mdItalic : selected}*';
        cursorOffset = selected.isEmpty ? 1 : replace.length;
        break;
      case _MdAction.strike:
        replace = '~~${selected.isEmpty ? L10n.of(context).mdStrike : selected}~~';
        cursorOffset = selected.isEmpty ? 2 : replace.length;
        break;
      case _MdAction.code:
        replace = '`${selected.isEmpty ? L10n.of(context).mdCode : selected}`';
        cursorOffset = selected.isEmpty ? 1 : replace.length;
        break;
      case _MdAction.link:
        final label = selected.isEmpty ? L10n.of(context).mdLinkText : selected;
        replace = '[$label](https://)';
        cursorOffset = replace.length - 1; // place before )
        break;
      case _MdAction.ul:
        replace = selected.isEmpty ? '- ${L10n.of(context).mdListItem}' : selected.split('\n').map((l) => l.isEmpty ? '- ' : '- $l').join('\n');
        cursorOffset = replace.length;
        break;
      case _MdAction.ol:
        int i = 1;
        replace = selected.isEmpty
            ? '1. ${L10n.of(context).mdListItem}'
            : selected
                .split('\n')
                .map((l) => l.isEmpty ? '${i++}. ' : '${i++}. $l')
                .join('\n');
        cursorOffset = replace.length;
        break;
      case _MdAction.task:
        replace = selected.isEmpty ? '- [ ] ${L10n.of(context).mdTask}' : selected.split('\n').map((l) => l.isEmpty ? '- [ ] ' : '- [ ] $l').join('\n');
        cursorOffset = replace.length;
        break;
      case _MdAction.quote:
        replace = selected.isEmpty ? '> ${L10n.of(context).mdQuote}' : selected.split('\n').map((l) => l.isEmpty ? '> ' : '> $l').join('\n');
        cursorOffset = replace.length;
        break;
    }
    final newText = hasSel ? before + replace + after : before + replace;
    final base = hasSel ? before.length : before.length;
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: base + cursorOffset),
    );
  }

  void _toggleTaskAt(int lineIndex) {
    final lines = widget.controller.text.split('\n');
    if (lineIndex < 0 || lineIndex >= lines.length) return;
    final line = lines[lineIndex];
    final re = RegExp(r'^(\s*)[-*+] \[( |x|X)\] (.*)$');
    final m = re.firstMatch(line);
    if (m == null) return;
    final indent = m.group(1) ?? '';
    final checked = (m.group(2) ?? ' ').trim().toLowerCase() == 'x';
    final rest = m.group(3) ?? '';
    final toggled = '$indent- [${checked ? ' ' : 'x'}] $rest';
    lines[lineIndex] = toggled;
    final newText = lines.join('\n');
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
    if (mounted) setState(() {});
  }

  void _enterEdit() {
    setState(() => _preview = false);
    widget.focusNode?.requestFocus();
  }

  Future<void> _saveAndExit() async {
    if (widget.onSave != null) {
      await widget.onSave!.call();
    } else {
      widget.onSubmitted?.call(widget.controller.text);
    }
    if (mounted) {
      setState(() => _preview = true);
    }
  }
}

class _PreviewWithTasks extends StatelessWidget {
  final String text;
  final ValueChanged<int> onToggleTask;
  const _PreviewWithTasks({required this.text, required this.onToggleTask});

  @override
  Widget build(BuildContext context) {
    final theme = CupertinoTheme.of(context);
    final lines = text.split('\n');
    final taskLineIndices = <int>[];
    final taskRe = RegExp(r'^(\s*)[-*+] \[( |x|X)\] (.*)$');
    for (int i = 0; i < lines.length; i++) {
      if (taskRe.hasMatch(lines[i])) taskLineIndices.add(i);
    }
    // Build markdown data with checkboxes stripped to avoid duplicate boxes
    String mdData = _withSoftBreaks(
      text
          .replaceAllMapped(taskRe, (m) => '${m.group(1) ?? ''}- ${m.group(3) ?? ''}')
          .trimRight(),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (taskLineIndices.isNotEmpty) ...[
          Column(
            children: [
              for (final idx in taskLineIndices)
                _TaskRow(line: lines[idx], onTap: () => onToggleTask(idx)),
              const SizedBox(height: 8),
              Container(height: 1, color: CupertinoColors.separator),
              const SizedBox(height: 8),
            ],
          ),
        ],
        MarkdownBody(
          data: mdData,
          extensionSet: md.ExtensionSet.gitHubFlavored,
          styleSheet: MarkdownStyleSheet(
            p: theme.textTheme.textStyle,
            code: theme.textTheme.textStyle.copyWith(
              fontFamily: 'monospace',
              backgroundColor: const Color(0x11000000),
            ),
          ),
        ),
      ],
    );
  }
  
  String _withSoftBreaks(String input) {
    final lines = input.split('\n');
    final out = <String>[];
    bool inCode = false;
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trimRight();
      if (trimmed.startsWith('```')) {
        inCode = !inCode;
        out.add(line);
        continue;
      }
      final isPara = line.isNotEmpty && !RegExp(r'^\s*([#>]|[-*+]\s|\d+\.\s)').hasMatch(line);
      final nextExists = i < lines.length - 1 && lines[i + 1].isNotEmpty;
      out.add((!inCode && isPara && nextExists) ? (line + '  ') : line);
    }
    return out.join('\n');
  }
}

class _TaskRow extends StatelessWidget {
  final String line;
  final VoidCallback onTap;
  const _TaskRow({required this.line, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final m = RegExp(r'^(\s*)[-*+] \[( |x|X)\] (.*)$').firstMatch(line);
    final checked = (m?.group(2) ?? ' ').trim().toLowerCase() == 'x';
    final text = m?.group(3) ?? line;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(
              checked ? CupertinoIcons.check_mark_circled_solid : CupertinoIcons.circle,
              size: 20,
              color: checked ? CupertinoColors.activeGreen : CupertinoColors.inactiveGray,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  decoration: checked ? TextDecoration.lineThrough : TextDecoration.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _MdAction { bold, italic, strike, code, link, ul, ol, task, quote }

class _Toolbar extends StatelessWidget {
  final void Function(_MdAction) onAction;
  final VoidCallback onShowTemplates;
  final VoidCallback? onShowHelp;
  final bool preview;
  final VoidCallback onEnterEdit;
  final VoidCallback onSave;
  const _Toolbar({required this.onAction, required this.onShowTemplates, this.onShowHelp, required this.preview, required this.onEnterEdit, required this.onSave});

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      _icon(CupertinoIcons.bold, () => onAction(_MdAction.bold)),
      _icon(CupertinoIcons.italic, () => onAction(_MdAction.italic)),
      _txt('S', () => onAction(_MdAction.strike)),
      _txt('`', () => onAction(_MdAction.code)),
      _icon(CupertinoIcons.link, () => onAction(_MdAction.link)),
      if (onShowHelp != null) _icon(CupertinoIcons.question, onShowHelp!),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: CupertinoColors.separator)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: items),
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            onPressed: preview ? onEnterEdit : onSave,
            child: Icon(
              preview ? CupertinoIcons.pencil_circle_fill : CupertinoIcons.check_mark_circled_solid,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _txt(String label, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }

  Widget _icon(IconData icon, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        onPressed: onPressed,
        child: Icon(icon, size: 20),
      ),
    );
  }
}
