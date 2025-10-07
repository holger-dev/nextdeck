import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../models/card_item.dart';
import '../theme/app_theme.dart';
import '../models/label.dart';
import 'package:intl/intl.dart';
import 'dart:math' as Math;
import '../models/board.dart';
import '../l10n/app_localizations.dart';
import 'card_detail_page.dart';

class UpcomingPage extends StatefulWidget {
  const UpcomingPage({super.key});
  @override
  State<UpcomingPage> createState() => _UpcomingPageState();
}

class _UpcomingPageState extends State<UpcomingPage> {
  bool _loading = false;
  int _totalBoards = 0;
  int _doneBoards = 0;
  String? _currentBoardTitle;

  final List<_DueHit> _overdue = [];
  final List<_DueHit> _today = [];
  final List<_DueHit> _tomorrow = [];
  final List<_DueHit> _next7 = [];
  final List<_DueHit> _later = [];

  int _seq = 0;
  final PageController _pageController = PageController();
  int _page = 0;
  int? _lastSeenTabIndex;

  @override
  void initState() {
    super.initState();
    // Prime with already loaded data; background warm-up handled by AppState
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _buildFromLoaded();
    });
  }

  void _clearAll() {
    _overdue.clear();
    _today.clear();
    _tomorrow.clear();
    _next7.clear();
    _later.clear();
  }

  void _buildFromLoaded() {
    final app = context.read<AppState>();
    _clearAll();
    for (final b in app.boards.where((x) => !x.archived)) {
      final cols = app.columnsForBoard(b.id);
      for (final c in cols) {
        final ct = c.title.toLowerCase();
        if (ct.contains('done') || ct.contains('erledigt')) continue; // skip done columns
        for (final k in c.cards) {
          if (k.due == null) continue;
          _addHit(b.id, b.title, c.id, c.title, k);
        }
      }
    }
    if (mounted) setState(() {});
  }

  void _addHit(int boardId, String boardTitle, int stackId, String stackTitle, CardItem card) {
    if (card.due == null) return;
    final st = stackTitle.toLowerCase();
    if (st.contains('done') || st.contains('erledigt')) return; // skip done
    final now = DateTime.now();
    final due = card.due!;
    final hit = _DueHit(boardId: boardId, boardTitle: boardTitle, stackId: stackId, stackTitle: stackTitle, card: card);
    if (due.isBefore(now)) {
      _overdue.add(hit);
      return;
    }
    final startToday = DateTime(now.year, now.month, now.day);
    final endToday = startToday.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
    final startTomorrow = startToday.add(const Duration(days: 1));
    final endTomorrow = startToday.add(const Duration(days: 2)).subtract(const Duration(milliseconds: 1));
    final end7 = startToday.add(const Duration(days: 8)).subtract(const Duration(milliseconds: 1));
    if (!due.isBefore(startToday) && !due.isAfter(endToday)) {
      _today.add(hit);
    } else if (!due.isBefore(startTomorrow) && !due.isAfter(endTomorrow)) {
      _tomorrow.add(hit);
    } else if (due.isAfter(endTomorrow) && !due.isAfter(end7)) {
      _next7.add(hit);
    } else if (due.isAfter(end7)) {
      _later.add(hit);
    }
  }

  void _rebuildFromCacheAndTrackLoading() {
    final app = context.read<AppState>();
    final refs = app.upcomingCacheRefs();
    if (refs != null) {
      _overdue.clear(); _today.clear(); _tomorrow.clear(); _next7.clear(); _later.clear();
      _resolve(refs['overdue']!, _overdue);
      _resolve(refs['today']!, _today);
      _resolve(refs['tomorrow']!, _tomorrow);
      _resolve(refs['next7']!, _next7);
      _resolve(refs['later']!, _later);
    } else {
      _buildFromLoaded();
    }
    final boards = app.boards.where((x) => !x.archived).toList();
    _totalBoards = boards.length;
    _doneBoards = 0; // Not tracked strictly in cache mode
    _loading = app.isWarming;
    _currentBoardTitle = null;
    if (mounted) setState(() {});
  }

  void _resolve(List<Map<String, int>> refs, List<_DueHit> into) {
    final app = context.read<AppState>();
    for (final e in refs) {
      final bId = e['b']!; final sId = e['s']!; final cId = e['c']!;
      final cols = app.columnsForBoard(bId);
      if (cols.isEmpty) continue;
      final stack = cols.firstWhere((x) => x.id == sId, orElse: () => cols.first);
      final ct = stack.title.toLowerCase();
      if (ct.contains('done') || ct.contains('erledigt')) continue;
      CardItem? card;
      final idx = stack.cards.indexWhere((x) => x.id == cId);
      if (idx >= 0) {
        card = stack.cards[idx];
      } else if (stack.cards.isNotEmpty) {
        card = stack.cards.first;
      }
      if (card == null) continue;
      final board = app.boards.firstWhere((b) => b.id == bId, orElse: () => Board(id: bId, title: 'Board'));
      into.add(_DueHit(boardId: bId, boardTitle: board.title, stackId: sId, stackTitle: stack.title, card: card));
    }
  }

  Future<void> _ensureAllAndRebuild() async {
    final app = context.read<AppState>();
    final mySeq = ++_seq;
    setState(() { _loading = true; _currentBoardTitle = null; _totalBoards = 0; _doneBoards = 0; });
    var boards = app.boards.where((x) => !x.archived).toList();
    if (boards.isEmpty && !app.localMode) {
      try {
        await app.refreshBoards();
        if (mySeq != _seq) return;
        boards = app.boards.where((x) => !x.archived).toList();
      } catch (_) {}
    }
    _totalBoards = boards.length;
    _clearAll();
    for (final b in boards) {
      if (mySeq != _seq) return;
      _currentBoardTitle = b.title;
      setState(() {});
      if (app.columnsForBoard(b.id).isEmpty) {
        await app.refreshColumnsFor(b);
        if (mySeq != _seq) return;
      }
      final cols = app.columnsForBoard(b.id);
      const pool = 3;
      for (int i = 0; i < cols.length; i += pool) {
        if (mySeq != _seq) return;
        final slice = cols.skip(i).take(pool).toList();
        await Future.wait(slice.map((c) async {
          if (mySeq != _seq) return;
          await app.ensureCardsFor(b.id, c.id);
          if (mySeq != _seq) return;
          final fresh = app.columnsForBoard(b.id).firstWhere((x) => x.id == c.id, orElse: () => c);
          final ct = fresh.title.toLowerCase();
          if (ct.contains('done') || ct.contains('erledigt')) return;
          for (final k in fresh.cards) {
            if (k.due == null) continue;
            _addHit(b.id, b.title, c.id, c.title, k);
          }
          if (mounted) setState(() {});
        }));
      }
      _doneBoards++;
      if (mounted) setState(() {});
    }
    int cmp(CardItem a, CardItem b) => (a.due ?? DateTime.now()).compareTo(b.due ?? DateTime.now());
    _overdue.sort((a, b) => cmp(a.card, b.card));
    _today.sort((a, b) => cmp(a.card, b.card));
    _tomorrow.sort((a, b) => cmp(a.card, b.card));
    _next7.sort((a, b) => cmp(a.card, b.card));
    _later.sort((a, b) => cmp(a.card, b.card));
    if (mounted) setState(() { _loading = false; _currentBoardTitle = null; });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final l10n = L10n.of(context);
    final currentTab = app.tabController.index;
    if (_lastSeenTabIndex != currentTab) {
      // Trigger auto-load when this tab becomes active
      if (currentTab == 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _ensureAllAndRebuild();
        });
      }
      _lastSeenTabIndex = currentTab;
    }
    return CupertinoPageScaffold(
      backgroundColor: AppTheme.appBackground(app),
      navigationBar: CupertinoNavigationBar(
        middle: Text(l10n.upcomingTitle),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () async {
                final l10n = L10n.of(context);
                final buckets = [
                  l10n.overdueLabel,
                  l10n.today,
                  l10n.tomorrow,
                  l10n.next7Days,
                  l10n.later,
                ];
                await showCupertinoModalPopup(
                  context: context,
                  builder: (ctx) => CupertinoActionSheet(
                    title: Text(l10n.selectColumn),
                    actions: buckets
                        .asMap()
                        .entries
                        .map((e) => CupertinoActionSheetAction(
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                final target = e.key;
                                _pageController.animateToPage(target, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
                              },
                              child: Text(e.value),
                            ))
                        .toList(),
                    cancelButton: CupertinoActionSheetAction(
                      onPressed: () => Navigator.of(ctx).pop(),
                      isDefaultAction: true,
                      child: Text(l10n.cancel),
                    ),
                  ),
                );
              },
              child: const Icon(CupertinoIcons.list_bullet),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _loading ? null : () => _rebuildFromCacheAndTrackLoading(),
              child: _loading ? const CupertinoActivityIndicator() : const Icon(CupertinoIcons.refresh),
            ),
          ],
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            if (_loading)
              Positioned(
                left: 12, right: 12, top: 8,
                child: Row(children: [
                  const CupertinoActivityIndicator(),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    _currentBoardTitle == null ? l10n.searchingInProgress : l10n.searchingBoard(_currentBoardTitle!),
                    style: const TextStyle(color: CupertinoColors.systemGrey),
                  )),
                ]),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 0),
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _bucketView(context, l10n.overdueLabel, _overdue, emphasize: true),
                  _bucketView(context, l10n.today, _today),
                  _bucketView(context, l10n.tomorrow, _tomorrow),
                  _bucketView(context, l10n.next7Days, _next7),
                  _bucketView(context, l10n.later, _later),
                ],
              ),
            ),
            // Top arrows like board view (overlay above pages), hidden at edges
            if (_page > 0)
              Positioned(
                left: 8,
                top: 14,
                child: _Arrow(
                  onTap: () {
                    final target = (_pageController.page ?? 0).floor() - 1;
                    if (target >= 0) {
                      _pageController.animateToPage(target, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
                    }
                  },
                  icon: CupertinoIcons.chevron_back,
                  enabled: true,
                ),
              ),
            if (_page < 4)
              Positioned(
                right: 8,
                top: 14,
                child: _Arrow(
                  onTap: () {
                    final target = (_pageController.page ?? 0).ceil() + 1;
                    if (target <= 4) {
                      _pageController.animateToPage(target, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
                    }
                  },
                  icon: CupertinoIcons.chevron_forward,
                  enabled: true,
                ),
              ),
            // bottom arrows removed per request
          ],
        ),
      ),
    );
  }

  Widget _bucketView(BuildContext context, String title, List<_DueHit> items, {bool emphasize = false}) {
    final app = context.watch<AppState>();
    final isTablet = MediaQuery.of(context).size.shortestSide >= 600;
    final Color containerBg = () {
      if (!app.smartColors) {
        return CupertinoTheme.of(context).brightness == Brightness.dark ? CupertinoColors.black : CupertinoColors.systemGrey6;
      }
      final baseCol = AppTheme.preferredColumnColor(app, title, 0);
      return app.isDarkMode ? AppTheme.blend(baseCol, const Color(0xFF000000), 0.75) : AppTheme.blend(baseCol, const Color(0xFFFFFFFF), 0.55);
    }();
    final baseForCards = app.smartColors
        ? AppTheme.preferredColumnColor(app, title, 0)
        : (CupertinoTheme.of(context).brightness == Brightness.dark ? CupertinoColors.systemGrey5 : CupertinoColors.systemGrey6);
    return Container(
      decoration: BoxDecoration(color: containerBg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Center(child: Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: emphasize ? CupertinoColors.destructiveRed : null))),
          ),
          if (items.isEmpty)
            Expanded(child: Center(child: Text(L10n.of(context).noDueCards, style: const TextStyle(color: CupertinoColors.systemGrey))))
          else
            Expanded(
            child: CupertinoScrollbar(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final h = items[i];
                  final bg = AppTheme.cardBgFromBase(app, h.card.labels, baseForCards, i);
                  final textOn = AppTheme.textOn(bg);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: _UpcomingTile(
                      title: h.card.title,
                      description: h.card.description,
                      labels: h.card.labels,
                      due: h.card.due,
                      background: bg,
                      contextColor: AppTheme.textOn(bg),
                      meta: '${h.boardTitle} · ${h.stackTitle}',
                      onTap: () {
                        Navigator.of(context).push(CupertinoPageRoute(builder: (_) => CardDetailPage(cardId: h.card.id, boardId: h.boardId, stackId: h.stackId, bgColor: bg)));
                      },
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

  List<Widget> _buildSection(BuildContext context, String title, List<_DueHit> items, {bool emphasize = false}) {
    if (items.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
        child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: emphasize ? CupertinoColors.destructiveRed : CupertinoColors.label)),
      ),
      ...items.map((h) => CupertinoButton(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            onPressed: () {
              Navigator.of(context).push(CupertinoPageRoute(builder: (_) {
                final app = context.read<AppState>();
                final cols = app.columnsForBoard(h.boardId);
                final colIdx = cols.indexWhere((c) => c.id == h.stackId);
                final bg = AppTheme.cardBg(app, h.card.labels, colIdx < 0 ? 0 : colIdx, 0);
                return CardDetailPage(cardId: h.card.id, boardId: h.boardId, stackId: h.stackId, bgColor: bg);
              }));
            },
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(h.card.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('${h.boardTitle} · ${h.stackTitle}', style: const TextStyle(fontSize: 12, color: CupertinoColors.systemGrey)),
                ],
              ),
            ),
          )),
    ];
  }
}

class _UpcomingTile extends StatelessWidget {
  final String title;
  final String? description;
  final List<Label> labels;
  final DateTime? due;
  final String meta;
  final Color background;
  final Color contextColor;
  final VoidCallback onTap;
  const _UpcomingTile({
    required this.title,
    required this.description,
    required this.labels,
    required this.due,
    required this.meta,
    required this.background,
    required this.contextColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = AppTheme.textOn(background);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: CupertinoColors.black.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4)),
          ],
          border: Border.all(color: CupertinoColors.separator.withOpacity(0.6)),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor)),
            if (labels.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.start,
                children: labels.map((l) => _LabelChipMini(label: l)).toList(),
              ),
            ],
            if ((description ?? '').isNotEmpty)
              Builder(builder: (context) {
                final app = context.watch<AppState>();
                if (app.showDescriptionText) {
                  final s = description!;
                  final trimmed = s.length > 200 ? (s.substring(0, 200) + '…') : s;
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(trimmed, style: TextStyle(color: textColor.withOpacity(0.85), fontSize: 14)),
                  );
                }
                return const SizedBox.shrink();
              }),
            if (due != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(CupertinoIcons.time, size: 14, color: _dueColor(due!, textColor)),
                    const SizedBox(width: 4),
                    Text(
                      _formatDue(due!),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _dueColor(due!, textColor)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(meta, style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.75)), overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LabelChipMini extends StatelessWidget {
  final Label label;
  const _LabelChipMini({required this.label});
  @override
  Widget build(BuildContext context) {
    final bg = _parseDeckColor(label.color) ?? CupertinoColors.systemGrey4;
    final tc = _bestTextColor(bg);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(label.title.isEmpty ? 'Label' : label.title, style: TextStyle(color: tc, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

Color _dueColor(DateTime due, Color defaultColor) {
  final now = DateTime.now();
  if (due.isBefore(now)) return CupertinoColors.systemRed;
  if (due.difference(now).inHours <= 24) return CupertinoColors.activeOrange;
  return defaultColor.withOpacity(0.98);
}

String _formatDue(DateTime due) {
  final fmt = DateFormat.MMMd().add_Hm();
  return fmt.format(due.toLocal());
}

Color? _parseDeckColor(String raw) {
  if (raw.isEmpty) return null;
  var s = raw.trim();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 3) { s = s.split('').map((c) => '$c$c').join(); }
  if (s.length == 6) { s = 'FF$s'; }
  if (s.length != 8) return null;
  final val = int.tryParse(s, radix: 16);
  if (val == null) return null;
  return Color(val);
}

Color _bestTextColor(Color bg) {
  final r = bg.red / 255.0; final g = bg.green / 255.0; final b = bg.blue / 255.0;
  double lum(double c) => c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4) as double;
  final L = 0.2126 * lum(r) + 0.7152 * lum(g) + 0.0722 * lum(b);
  return L > 0.5 ? CupertinoColors.black : CupertinoColors.white;
}

class _Arrow extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  final bool enabled;
  const _Arrow({required this.onTap, required this.icon, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 26, color: enabled ? CupertinoColors.systemGrey : CupertinoColors.systemGrey4),
      ),
    );
  }
}

class _DueHit {
  final int boardId;
  final String boardTitle;
  final int stackId;
  final String stackTitle;
  final CardItem card;
  _DueHit({required this.boardId, required this.boardTitle, required this.stackId, required this.stackTitle, required this.card});
}
