import 'package:flutter/cupertino.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
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
  // Letzter bekannter Text — für die Enter-Erkennung in _handleTextChanged.
  // Wird nur über onChanged aktuell gehalten; programmatische Änderungen
  // (Templates, Toolbar) verpassen höchstens ein Event und heilen sich
  // beim nächsten Tastendruck selbst.
  String _lastText = '';

  @override
  void initState() {
    super.initState();
    _preview = widget.initialPreview;
    _lastText = widget.controller.text;
  }

  /// Issue #82: Enter in einer Task-/Bullet-Zeile führt die Liste fort.
  /// - `- [ ] Foo` + Enter  → neue Zeile beginnt mit `- [ ] `
  /// - `- Foo` + Enter      → neue Zeile beginnt mit `- `
  /// - leere Listenzeile + Enter → Marker wird entfernt (Liste beendet),
  ///   wie man es aus üblichen Markdown-Editoren kennt.
  void _handleTextChanged(String newText) {
    final old = _lastText;
    _lastText = newText;
    // Nur reagieren, wenn genau EIN Zeichen dazukam und das ein \n ist —
    // schließt Paste-Operationen und Löschungen aus.
    if (newText.length != old.length + 1) return;
    final sel = widget.controller.selection;
    if (!sel.isValid || !sel.isCollapsed) return;
    final pos = sel.start;
    if (pos < 1 || newText[pos - 1] != '\n') return;

    // Zeile VOR dem frisch eingefügten \n bestimmen
    final beforeNewline = newText.substring(0, pos - 1);
    final lineStart = beforeNewline.lastIndexOf('\n') + 1;
    final prevLine = beforeNewline.substring(lineStart);

    final taskMatch =
        RegExp(r'^(\s*)- \[( |x|X)\] (.*)$').firstMatch(prevLine);
    final bulletMatch = RegExp(r'^(\s*)- (.*)$').firstMatch(prevLine);

    String? continuationPrefix;
    bool emptyItem = false;
    if (taskMatch != null) {
      emptyItem = taskMatch.group(3)!.trim().isEmpty;
      continuationPrefix = '${taskMatch.group(1)!}- [ ] ';
    } else if (bulletMatch != null) {
      emptyItem = bulletMatch.group(2)!.trim().isEmpty;
      continuationPrefix = '${bulletMatch.group(1)!}- ';
    }
    if (continuationPrefix == null) return;

    if (emptyItem) {
      // Leeres Listenelement + Enter → Marker UND das neue \n entfernen;
      // Cursor bleibt auf der (jetzt leeren) Zeile.
      final cleaned = newText.replaceRange(lineStart, pos, '');
      _lastText = cleaned;
      widget.controller.value = TextEditingValue(
        text: cleaned,
        selection: TextSelection.collapsed(offset: lineStart),
      );
    } else {
      final continued = newText.replaceRange(pos, pos, continuationPrefix);
      _lastText = continued;
      widget.controller.value = TextEditingValue(
        text: continued,
        selection:
            TextSelection.collapsed(offset: pos + continuationPrefix.length),
      );
    }
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
            placeholder:
                widget.placeholder ?? L10n.of(context).descriptionMarkdown,
            maxLines: 8,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            placeholderStyle: TextStyle(
              color: (CupertinoTheme.of(context).textTheme.textStyle.color ??
                      CupertinoColors.label)
                  .withOpacity(0.6),
            ),
            onChanged: _handleTextChanged,
            onSubmitted: widget.onSubmitted,
          )
        else
          GestureDetector(
            onTap: _enterEdit,
            child: ConstrainedBox(
              // Begrenzt die Höhe der Beschreibung. Längere Texte werden
              // intern scrollbar — Anhänge und Kommentare bleiben damit
              // ohne langes Scrollen erreichbar.
              constraints: const BoxConstraints(
                minHeight: 160,
                maxHeight: 480,
              ),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: CupertinoColors.separator.resolveFrom(context)),
                ),
                child: CupertinoScrollbar(
                  thumbVisibility: false,
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: _PreviewWithTasks(
                      text: widget.controller.text,
                      onToggleTask: (lineIndex) => _toggleTaskAt(lineIndex),
                    ),
                  ),
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
            onPressed: () {
              Navigator.of(ctx).pop();
              _insertTaskTemplate();
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(CupertinoIcons.square_list),
                const SizedBox(width: 8),
                Text(L10n.of(context).taskList)
              ],
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
            const SizedBox(height: 4),
            Text(L10n.of(context).helpDetails),
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
      widget.controller.value = TextEditingValue(
          text: newText, selection: TextSelection.collapsed(offset: newOffset));
    } else {
      widget.controller.text =
          (text.isEmpty ? tpl : (text.trimRight() + '\n\n' + tpl));
      widget.controller.selection =
          TextSelection.collapsed(offset: widget.controller.text.length);
    }
    if (mounted)
      setState(() {
        _preview = false;
      });
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
    // Wenn ein Placeholder-Text eingefügt wurde, geben wir hier den
    // [start, end]-Range INNERHALB von `replace` zurück, sodass er
    // automatisch markiert wird und der User einfach drüber-tippt
    // (statt erst selektieren oder löschen zu müssen).
    int? placeholderStart;
    int? placeholderEnd;

    switch (a) {
      case _MdAction.bold:
        final ph = L10n.of(context).mdBold;
        replace = '**${selected.isEmpty ? ph : selected}**';
        if (selected.isEmpty) {
          placeholderStart = 2;
          placeholderEnd = 2 + ph.length;
        }
        cursorOffset = replace.length;
        break;
      case _MdAction.italic:
        final ph = L10n.of(context).mdItalic;
        replace = '*${selected.isEmpty ? ph : selected}*';
        if (selected.isEmpty) {
          placeholderStart = 1;
          placeholderEnd = 1 + ph.length;
        }
        cursorOffset = replace.length;
        break;
      case _MdAction.strike:
        final ph = L10n.of(context).mdStrike;
        replace = '~~${selected.isEmpty ? ph : selected}~~';
        if (selected.isEmpty) {
          placeholderStart = 2;
          placeholderEnd = 2 + ph.length;
        }
        cursorOffset = replace.length;
        break;
      case _MdAction.code:
        final ph = L10n.of(context).mdCode;
        replace = '`${selected.isEmpty ? ph : selected}`';
        if (selected.isEmpty) {
          placeholderStart = 1;
          placeholderEnd = 1 + ph.length;
        }
        cursorOffset = replace.length;
        break;
      case _MdAction.link:
        final label = selected.isEmpty ? L10n.of(context).mdLinkText : selected;
        replace = '[$label](https://)';
        // Cursor zwischen den runden Klammern parken, damit der User
        // direkt die URL eintippen kann.
        cursorOffset = replace.length - 1;
        break;
      case _MdAction.ul:
        final ph = L10n.of(context).mdListItem;
        replace = selected.isEmpty
            ? '- $ph'
            : selected
                .split('\n')
                .map((l) => l.isEmpty ? '- ' : '- $l')
                .join('\n');
        if (selected.isEmpty) {
          placeholderStart = 2; // nach "- "
          placeholderEnd = 2 + ph.length;
        }
        cursorOffset = replace.length;
        break;
      case _MdAction.ol:
        int i = 1;
        final ph = L10n.of(context).mdListItem;
        replace = selected.isEmpty
            ? '1. $ph'
            : selected
                .split('\n')
                .map((l) => l.isEmpty ? '${i++}. ' : '${i++}. $l')
                .join('\n');
        if (selected.isEmpty) {
          placeholderStart = 3; // nach "1. "
          placeholderEnd = 3 + ph.length;
        }
        cursorOffset = replace.length;
        break;
      case _MdAction.task:
        final ph = L10n.of(context).mdTask;
        replace = selected.isEmpty
            ? '- [ ] $ph'
            : selected
                .split('\n')
                .map((l) => l.isEmpty ? '- [ ] ' : '- [ ] $l')
                .join('\n');
        if (selected.isEmpty) {
          placeholderStart = 6; // nach "- [ ] "
          placeholderEnd = 6 + ph.length;
        }
        cursorOffset = replace.length;
        break;
      case _MdAction.quote:
        final ph = L10n.of(context).mdQuote;
        replace = selected.isEmpty
            ? '> $ph'
            : selected
                .split('\n')
                .map((l) => l.isEmpty ? '> ' : '> $l')
                .join('\n');
        if (selected.isEmpty) {
          placeholderStart = 2; // nach "> "
          placeholderEnd = 2 + ph.length;
        }
        cursorOffset = replace.length;
        break;
      case _MdAction.details:
        // Aufklappbereich (<details>/<summary>) — wird von Nextcloud Deck
        // unterstützt und in unserer Vorschau als aufklappbares Panel
        // gerendert. Selektierter Text wird zum Titel.
        final phTitle = L10n.of(context).mdDetailsSummary;
        final phContent = L10n.of(context).mdDetailsContent;
        final title = selected.isEmpty ? phTitle : selected;
        // Block auf eigener Zeile beginnen lassen
        final prefix =
            (before.isNotEmpty && !before.endsWith('\n')) ? '\n' : '';
        replace =
            '$prefix<details><summary>$title</summary>\n\n$phContent\n\n</details>\n';
        if (selected.isEmpty) {
          placeholderStart = prefix.length + '<details><summary>'.length;
          placeholderEnd = placeholderStart + phTitle.length;
        } else {
          // Titel stand schon fest → direkt den Inhalts-Platzhalter markieren
          placeholderStart =
              '$prefix<details><summary>$title</summary>\n\n'.length;
          placeholderEnd = placeholderStart + phContent.length;
        }
        cursorOffset = replace.length;
        break;
    }
    final newText = hasSel ? before + replace + after : before + replace;
    final base = before.length;
    final TextSelection newSelection;
    if (placeholderStart != null && placeholderEnd != null) {
      // Placeholder-Bereich markieren — beim Tippen wird er ersetzt.
      newSelection = TextSelection(
        baseOffset: base + placeholderStart,
        extentOffset: base + placeholderEnd,
      );
    } else {
      newSelection = TextSelection.collapsed(offset: base + cursorOffset);
    }
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: newSelection,
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
    final lines = text.split('\n');
    final taskLineIndices = <int>[];
    final taskRe = RegExp(r'^(\s*)[-*+] \[( |x|X)\] (.*)$');
    for (int i = 0; i < lines.length; i++) {
      if (taskRe.hasMatch(lines[i])) taskLineIndices.add(i);
    }
    // Build markdown data with checkboxes stripped to avoid duplicate boxes
    String mdData = _withSoftBreaks(
      text
          .replaceAllMapped(
              taskRe, (m) => '${m.group(1) ?? ''}- ${m.group(3) ?? ''}')
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
        ..._buildSegments(context, mdData),
      ],
    );
  }

  // Nextcloud Deck unterstützt <details>/<summary> in Beschreibungen.
  // flutter_markdown rendert kein HTML — ohne Sonderbehandlung stünden die
  // Tags als Rohtext in der Vorschau. Wir zerlegen den Text deshalb in
  // normale Markdown-Segmente und Details-Blöcke, die als aufklappbare
  // Panels gerendert werden (Standard: zugeklappt, außer <details open> —
  // wie im Web). Verschachtelte Blöcke werden rekursiv gerendert; bei
  // kaputtem Markup (fehlendes </details>) greift der Fallback: Tags
  // ausblenden, Summary fett, Inhalt normal sichtbar.
  // Bekannte Einschränkung: <details> innerhalb von ```-Codeblöcken wird
  // ebenfalls erkannt — in Kartenbeschreibungen praktisch nicht relevant.
  static final _detailsOpenRe =
      RegExp(r'<details\b([^>]*)>', caseSensitive: false);
  static final _detailsCloseRe = RegExp(r'</details\s*>', caseSensitive: false);
  static final _summaryRe = RegExp(r'<summary\b[^>]*>(.*?)</summary\s*>',
      caseSensitive: false, dotAll: true);

  List<Widget> _buildSegments(BuildContext context, String data) {
    final widgets = <Widget>[];
    int pos = 0;
    while (pos < data.length) {
      final m = _detailsOpenRe.firstMatch(data.substring(pos));
      if (m == null) {
        final tail = data.substring(pos).trim();
        if (tail.isNotEmpty) widgets.add(_mdBody(context, tail));
        break;
      }
      final head = data.substring(pos, pos + m.start).trim();
      if (head.isNotEmpty) widgets.add(_mdBody(context, head));
      final initiallyOpen = (m.group(1) ?? '').toLowerCase().contains('open');
      // Zugehöriges </details> suchen — verschachtelte Blöcke mitzählen.
      int depth = 1;
      int cursor = pos + m.end;
      int contentEnd = -1;
      int afterClose = -1;
      while (cursor < data.length) {
        final rest = data.substring(cursor);
        final o = _detailsOpenRe.firstMatch(rest);
        final c = _detailsCloseRe.firstMatch(rest);
        if (c == null) break;
        if (o != null && o.start < c.start) {
          depth++;
          cursor += o.end;
        } else {
          depth--;
          if (depth == 0) {
            contentEnd = cursor + c.start;
            afterClose = cursor + c.end;
            break;
          }
          cursor += c.end;
        }
      }
      if (contentEnd < 0) {
        // Fallback bei kaputtem Markup
        var rest = data.substring(pos + m.end);
        String summary = '';
        final sm = _summaryRe.firstMatch(rest);
        if (sm != null) {
          summary = _stripTags(sm.group(1)!);
          rest = rest.replaceRange(sm.start, sm.end, '');
        }
        final fallback =
            (summary.isEmpty ? '' : '**$summary**\n\n') + rest.trim();
        if (fallback.trim().isNotEmpty) {
          widgets.add(_mdBody(context, fallback));
        }
        break;
      }
      var inner = data.substring(pos + m.end, contentEnd);
      String summary = '';
      final sm = _summaryRe.firstMatch(inner);
      if (sm != null) {
        summary = _stripTags(sm.group(1)!);
        inner = inner.replaceRange(sm.start, sm.end, '');
      }
      final innerTrimmed = inner.trim();
      widgets.add(_DetailsBlock(
        summary: summary.isEmpty ? L10n.of(context).detailsLabel : summary,
        initiallyOpen: initiallyOpen,
        contentBuilder: (ctx) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _buildSegments(ctx, innerTrimmed),
        ),
      ));
      pos = afterClose;
    }
    return widgets;
  }

  String _stripTags(String s) =>
      s.replaceAll(RegExp(r'<[^>]+>'), '').trim();

  Widget _mdBody(BuildContext context, String data) {
    final theme = CupertinoTheme.of(context);
    return MarkdownBody(
      data: data,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      onTapLink: (text, href, title) => _openMarkdownLink(href),
      styleSheet: MarkdownStyleSheet(
        p: theme.textTheme.textStyle,
        code: theme.textTheme.textStyle.copyWith(
          fontFamily: 'monospace',
          backgroundColor: const Color(0x11000000),
        ),
      ),
    );
  }

  Future<void> _openMarkdownLink(String? href) async {
    final raw = href?.trim();
    if (raw == null || raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https' && scheme != 'mailto') return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
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
      final isPara = line.isNotEmpty &&
          !RegExp(r'^\s*([#>]|[-*+]\s|\d+\.\s)').hasMatch(line);
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
              checked
                  ? CupertinoIcons.check_mark_circled_solid
                  : CupertinoIcons.circle,
              size: 20,
              color: checked
                  ? CupertinoColors.activeGreen
                  : CupertinoColors.inactiveGray,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  decoration: checked
                      ? TextDecoration.lineThrough
                      : TextDecoration.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _MdAction { bold, italic, strike, code, link, ul, ol, task, quote, details }

class _Toolbar extends StatelessWidget {
  final void Function(_MdAction) onAction;
  final VoidCallback onShowTemplates;
  final VoidCallback? onShowHelp;
  final bool preview;
  final VoidCallback onEnterEdit;
  final VoidCallback onSave;
  const _Toolbar(
      {required this.onAction,
      required this.onShowTemplates,
      this.onShowHelp,
      required this.preview,
      required this.onEnterEdit,
      required this.onSave});

  @override
  Widget build(BuildContext context) {
    // Zwei-Reihen-Layout: alle Format-Tools sofort sichtbar, nichts mehr
    // im horizontalen Scroll versteckt.
    // Reihe 1: Inline-Formatierung (Bold/Italic/Strike/Code/Link)
    // Reihe 2: Block-/Listen-Formatierung (Bullet/Numbered/Task/Quote/Help)
    final inlineItems = <Widget>[
      _icon(CupertinoIcons.bold, () => onAction(_MdAction.bold)),
      _icon(CupertinoIcons.italic, () => onAction(_MdAction.italic)),
      _txt('S', () => onAction(_MdAction.strike)),
      _txt('`', () => onAction(_MdAction.code)),
      _icon(CupertinoIcons.link, () => onAction(_MdAction.link)),
    ];
    final blockItems = <Widget>[
      _icon(CupertinoIcons.list_bullet, () => onAction(_MdAction.ul)),
      _icon(CupertinoIcons.list_number, () => onAction(_MdAction.ol)),
      _icon(CupertinoIcons.checkmark_square, () => onAction(_MdAction.task)),
      _icon(CupertinoIcons.quote_bubble, () => onAction(_MdAction.quote)),
      _icon(CupertinoIcons.chevron_down_square,
          () => onAction(_MdAction.details)),
      if (onShowHelp != null) _icon(CupertinoIcons.question, onShowHelp!),
    ];

    final editSaveButton = CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      onPressed: preview ? onEnterEdit : onSave,
      child: Icon(
        preview
            ? CupertinoIcons.pencil_circle_fill
            : CupertinoIcons.check_mark_circled_solid,
        size: 26,
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: CupertinoColors.separator)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Linke Spalte: zwei Reihen Format-Tools
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: inlineItems
                      .map((w) => Expanded(child: Center(child: w)))
                      .toList(),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: blockItems
                      .map((w) => Expanded(child: Center(child: w)))
                      .toList(),
                ),
              ],
            ),
          ),
          // Rechte Spalte: Edit/Save in voller Höhe
          editSaveButton,
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

/// Aufklappbares Panel für <details>/<summary>-Bereiche in der
/// Markdown-Vorschau — Pendant zum nativen HTML-Element der Deck-Web-UI.
/// Zustand (auf/zu) lebt nur in der Ansicht und wird nicht gespeichert,
/// genau wie im Browser.
class _DetailsBlock extends StatefulWidget {
  final String summary;
  final bool initiallyOpen;
  final WidgetBuilder contentBuilder;
  const _DetailsBlock({
    required this.summary,
    required this.initiallyOpen,
    required this.contentBuilder,
  });

  @override
  State<_DetailsBlock> createState() => _DetailsBlockState();
}

class _DetailsBlockState extends State<_DetailsBlock> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final labelColor = CupertinoColors.label.resolveFrom(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header toggelt — der GestureDetector gewinnt gegen den
          // "Tap = Bearbeiten"-Detector der umgebenden Vorschau.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _open ? 0.25 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(CupertinoIcons.chevron_right,
                        size: 15, color: labelColor.withOpacity(0.7)),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      widget.summary,
                      style: TextStyle(
                          fontWeight: FontWeight.w600, color: labelColor),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                    child: widget.contentBuilder(context),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
