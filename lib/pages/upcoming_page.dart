import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../models/card_item.dart';
import '../theme/app_theme.dart';
import '../theme/design_tokens.dart';
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
  // Issue #84: Karten ohne Fälligkeitsdatum — eigene Sektion wie in NC Deck
  final List<_DueHit> _noDue = [];

  int _seq = 0;
  final PageController _pageController = PageController();
  int _page = 0;
  int? _lastSeenTabIndex;
  int _lastScanDone = -1;
  // Fingerprint des Hidden-Board-Sets — triggert Listen-Rebuild bei Änderung
  String _lastHiddenFp = '';

  @override
  void initState() {
    super.initState();
    // Prime with already loaded data; background warm-up handled by AppState
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rebuildFromCacheAndTrackLoading();
    });
  }

  @override
  void dispose() {
    // Leak-Fix: PageController wurde bisher nie freigegeben
    _pageController.dispose();
    super.dispose();
  }

  void _clearAll() {
    _overdue.clear();
    _today.clear();
    _tomorrow.clear();
    _next7.clear();
    _later.clear();
    _noDue.clear();
  }

  void _buildFromLoaded() {
    final app = context.read<AppState>();
    _clearAll();
    // Fix: ausgeblendete Boards nicht in Anstehend aufnehmen
    for (final b in app.boards
        .where((x) => !x.archived && !app.isBoardHidden(x.id))) {
      final cols = app.columnsForBoard(b.id);
      for (final c in cols) {
        final ct = c.title.toLowerCase();
        if (ct.contains('done') || ct.contains('erledigt'))
          continue; // skip done columns
        for (final k in c.cards) {
          _addHit(app, b.id, b.title, c.id, c.title, k);
        }
      }
    }
    if (mounted) setState(() {});
  }

  void _addHit(AppState app, int boardId, String boardTitle, int stackId,
      String stackTitle, CardItem card) {
    if (card.done != null) return;
    if (!app.shouldIncludeAssignedCard(card)) return;
    final st = stackTitle.toLowerCase();
    if (st.contains('done') || st.contains('erledigt')) return; // skip done
    final now = DateTime.now();
    final hit = _DueHit(
        boardId: boardId,
        boardTitle: boardTitle,
        stackId: stackId,
        stackTitle: stackTitle,
        card: card);
    // Issue #84: Karten ohne Fälligkeit in eigene Sektion
    if (card.due == null) {
      _noDue.add(hit);
      return;
    }
    final due = card.due!;
    if (due.isBefore(now)) {
      _overdue.add(hit);
      return;
    }
    final startToday = DateTime(now.year, now.month, now.day);
    final endToday = startToday
        .add(const Duration(days: 1))
        .subtract(const Duration(milliseconds: 1));
    final startTomorrow = startToday.add(const Duration(days: 1));
    final endTomorrow = startToday
        .add(const Duration(days: 2))
        .subtract(const Duration(milliseconds: 1));
    final end7 = startToday
        .add(const Duration(days: 8))
        .subtract(const Duration(milliseconds: 1));
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
      _clearAll();
      _resolve(app, refs['overdue']!, _overdue);
      _resolve(app, refs['today']!, _today);
      _resolve(app, refs['tomorrow']!, _tomorrow);
      _resolve(app, refs['next7']!, _next7);
      _resolve(app, refs['later']!, _later);
      _resolve(app, refs['nodue'] ?? const [], _noDue);
      if (_overdue.isEmpty &&
          _today.isEmpty &&
          _tomorrow.isEmpty &&
          _next7.isEmpty &&
          _later.isEmpty &&
          _noDue.isEmpty) {
        _buildFromLoaded();
      }
    } else {
      _buildFromLoaded();
    }
    final boards = app.boards
        .where((x) => !x.archived && !app.isBoardHidden(x.id))
        .toList();
    _totalBoards = boards.length;
    _doneBoards = 0; // Not tracked strictly in cache mode
    // Kein Spinner für Cache-Rebuild; Hintergrund-Scan zeigt separaten Fortschritt
    _loading = false;
    _currentBoardTitle = null;
    if (mounted) setState(() {});
  }

  void _resolve(AppState app, List<Map<String, int>> refs, List<_DueHit> into) {
    for (final e in refs) {
      final bId = e['b']!;
      final sId = e['s']!;
      final cId = e['c']!;
      // Fix: Refs aus ÄLTEREN Caches können ausgeblendete Boards enthalten
      // (der Cache wird nur beim Sync/Toggle neu gebaut) — hier immer
      // gegen den aktuellen Hidden-Status filtern.
      if (app.isBoardHidden(bId)) continue;
      final cols = app.columnsForBoard(bId);
      if (cols.isEmpty) continue;
      final stack =
          cols.firstWhere((x) => x.id == sId, orElse: () => cols.first);
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
      if (card.done != null) continue;
      if (!app.shouldIncludeAssignedCard(card)) continue;
      final board = app.boards.firstWhere((b) => b.id == bId,
          orElse: () => Board(id: bId, title: 'Board'));
      into.add(_DueHit(
          boardId: bId,
          boardTitle: board.title,
          stackId: sId,
          stackTitle: stack.title,
          card: card));
    }
  }

  Future<void> _ensureAllAndRebuild() async {
    final app = context.read<AppState>();
    final mySeq = ++_seq;
    setState(() {
      _loading = true;
      _currentBoardTitle = null;
      _totalBoards = 0;
      _doneBoards = 0;
    });
    var boards = app.boards.where((x) => !x.archived).toList();
    if (boards.isEmpty && !app.localMode) {
      try {
        await app.refreshBoards(forceNetwork: true);
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
      // Nur Spalten aus Cache oder bereits geladenem Zustand verwenden
      final cols = app.columnsForBoard(b.id);
      for (final c in cols) {
        final ct = c.title.toLowerCase();
        if (ct.contains('done') || ct.contains('erledigt')) continue;
        for (final k in c.cards) {
          _addHit(app, b.id, b.title, c.id, c.title, k);
        }
      }
      _doneBoards++;
      if (mounted) setState(() {});
    }
    int cmp(CardItem a, CardItem b) =>
        (a.due ?? DateTime.now()).compareTo(b.due ?? DateTime.now());
    _overdue.sort((a, b) => cmp(a.card, b.card));
    _today.sort((a, b) => cmp(a.card, b.card));
    _tomorrow.sort((a, b) => cmp(a.card, b.card));
    _next7.sort((a, b) => cmp(a.card, b.card));
    _later.sort((a, b) => cmp(a.card, b.card));
    // Ohne Fälligkeit: alphabetisch nach Board, dann Titel
    _noDue.sort((a, b) {
      final byBoard = a.boardTitle
          .toLowerCase()
          .compareTo(b.boardTitle.toLowerCase());
      if (byBoard != 0) return byBoard;
      return a.card.title.toLowerCase().compareTo(b.card.title.toLowerCase());
    });
    if (mounted)
      setState(() {
        _loading = false;
        _currentBoardTitle = null;
      });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final l10n = L10n.of(context);
    // When background scan advances, rebuild lists from cache to show new hits
    if (app.upcomingScanDone != _lastScanDone) {
      _lastScanDone = app.upcomingScanDone;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _rebuildFromCacheAndTrackLoading();
      });
    }
    // Hidden-Boards-Fix (Trigger): Ändert sich das Set der ausgeblendeten
    // Boards (Toggle in der Übersicht, oder das verzögerte Laden beim
    // App-Start), werden die Listen neu aufgebaut. Vorher wurden sie nur
    // bei Tab-Wechsel/Scan neu gebaut — wer im Anstehend-Tab startete,
    // behielt Listen, die VOR dem Laden des Hidden-Sets entstanden waren.
    final hiddenFp = (app.boards
            .where((b) => app.isBoardHidden(b.id))
            .map((b) => b.id)
            .toList()
          ..sort())
        .join(',');
    if (hiddenFp != _lastHiddenFp) {
      _lastHiddenFp = hiddenFp;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _rebuildFromCacheAndTrackLoading();
      });
    }
    // Hidden-Boards-Fix (doppelter Boden, Render-Ebene): egal wie die
    // Listen zustande kamen — ausgeblendete Boards werden nie angezeigt.
    List<_DueHit> vis(List<_DueHit> l) =>
        l.where((h) => !app.isBoardHidden(h.boardId)).toList(growable: false);
    final visOverdue = vis(_overdue);
    final visToday = vis(_today);
    final visTomorrow = vis(_tomorrow);
    final visNext7 = vis(_next7);
    final visLater = vis(_later);
    final visNoDue = vis(_noDue);
    final currentTab = app.tabController.index;
    if (_lastSeenTabIndex != currentTab) {
      // Beim Betreten nur lokal neu aufbauen, keine automatischen Netz-Requests
      if (currentTab == 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _rebuildFromCacheAndTrackLoading();
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
            if (!app.upcomingSingleColumn)
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
                    l10n.noDueLabel,
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
                                  _pageController.animateToPage(target,
                                      duration:
                                          const Duration(milliseconds: 220),
                                      curve: Curves.easeOut);
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
              onPressed: () async {
                final next = !app.upcomingAssignedOnly;
                app.setUpcomingAssignedOnly(next);
                if (next) {
                  await app.refreshUpcomingAssigneesIfNeeded();
                }
                _rebuildFromCacheAndTrackLoading();
              },
              child: Icon(app.upcomingAssignedOnly
                  ? CupertinoIcons.person_fill
                  : CupertinoIcons.person),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: (app.upcomingScanActive || app.isSyncing)
                  ? null
                  : () async {
                      // Perform delta sync (only changed boards) to avoid overwriting local changes
                      await app.refreshUpcomingDelta(forceFull: false);
                      // Rebuild view from updated cache
                      if (mounted) _rebuildFromCacheAndTrackLoading();
                    },
              child: (app.upcomingScanActive || app.isSyncing)
                  ? const CupertinoActivityIndicator()
                  : const Icon(CupertinoIcons.refresh),
            ),
          ],
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            if (app.bootSyncing &&
                visOverdue.isEmpty &&
                visToday.isEmpty &&
                visTomorrow.isEmpty &&
                visNext7.isEmpty &&
                visLater.isEmpty &&
                visNoDue.isEmpty)
              const Center(child: CupertinoActivityIndicator()),
            // moved overlay below to ensure it paints on top
            if (!app.upcomingSingleColumn)
              Padding(
                padding: const EdgeInsets.only(top: 0),
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (i) => setState(() => _page = i),
                  children: [
                    _bucketView(context, l10n.overdueLabel, visOverdue,
                        emphasize: true),
                    _bucketView(context, l10n.today, visToday),
                    _bucketView(context, l10n.tomorrow, visTomorrow),
                    _bucketView(context, l10n.next7Days, visNext7),
                    _bucketView(context, l10n.later, visLater),
                    _bucketView(context, l10n.noDueLabel, visNoDue),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 0),
                child: CupertinoScrollbar(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(12, 8, 12, DT.tabBarReserve),
                    children: [
                      ..._buildSection(context, l10n.overdueLabel, visOverdue,
                          emphasize: true, showEmptyHeaderOnly: true),
                      ..._buildSection(context, l10n.today, visToday,
                          showEmptyHeaderOnly: true),
                      ..._buildSection(context, l10n.tomorrow, visTomorrow,
                          showEmptyHeaderOnly: true),
                      ..._buildSection(context, l10n.next7Days, visNext7,
                          showEmptyHeaderOnly: true),
                      ..._buildSection(context, l10n.later, visLater,
                          showEmptyHeaderOnly: true),
                      ..._buildSection(context, l10n.noDueLabel, visNoDue,
                          showEmptyHeaderOnly: true),
                    ],
                  ),
                ),
              ),
            // NC 2.0: Bucket-Navigation als fixes Overlay oben rechts —
            // bildschirm-rechtsbündig, identisch zur Board-Ansicht.
            if (!app.upcomingSingleColumn)
              Positioned(
                top: 12,
                right: 16,
                child: _UpPagerPill(
                  current: _page.clamp(0, _bucketCount - 1),
                  total: _bucketCount,
                  onPrev: () => _animateToBucket(_page - 1),
                  onNext: () => _animateToBucket(_page + 1),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static const int _bucketCount = 6;

  void _animateToBucket(int target) {
    if (target < 0 || target >= _bucketCount) return;
    _pageController.animateToPage(target,
        duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  Widget _bucketView(BuildContext context, String title, List<_DueHit> items,
      {bool emphasize = false}) {
    final app = context.watch<AppState>();
    final isTablet = MediaQuery.of(context).size.shortestSide >= 600;
    final Color containerBg = () {
      if (!app.smartColors) {
        return CupertinoTheme.of(context).brightness == Brightness.dark
            ? CupertinoColors.black
            : CupertinoColors.systemGrey6;
      }
      final baseCol = AppTheme.preferredColumnColor(app, title, 0);
      return app.isDarkMode
          ? AppTheme.blend(baseCol, const Color(0xFF000000), 0.75)
          : AppTheme.blend(baseCol, const Color(0xFFFFFFFF), 0.55);
    }();
    final neutralBase = AppTheme.neutralCardBase(app);
    final baseForCards = app.cardColorsFromLabels
        ? (app.smartColors
            ? AppTheme.preferredColumnColor(app, title, 0)
            : neutralBase)
        : neutralBase;
    return Container(
      decoration: BoxDecoration(color: containerBg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // NC 2.0: Header im gleichen Stil wie die Board-Spalten —
          // linksbündig, fette Typo, Zähler-Pill. Rechts 120px frei für
          // die fixe Pager-Pill (Overlay).
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 120, 8),
            child: Row(
              children: [
                Flexible(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          color: emphasize
                              ? CupertinoColors.destructiveRed
                              : null)),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: (emphasize && items.isNotEmpty
                            ? CupertinoColors.destructiveRed
                            : CupertinoColors.systemGrey)
                        .withOpacity(0.18),
                    borderRadius: BorderRadius.circular(DT.radiusFull),
                  ),
                  child: Text('${items.length}',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: emphasize && items.isNotEmpty
                              ? CupertinoColors.destructiveRed
                              : CupertinoColors.systemGrey)),
                ),
              ],
            ),
          ),
          if (items.isEmpty)
            Expanded(
                child: Center(
                    child: Text(L10n.of(context).noDueCards,
                        style: const TextStyle(
                            color: CupertinoColors.systemGrey))))
          else
            Expanded(
              child: CupertinoScrollbar(
                child: ListView.builder(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, DT.tabBarReserve),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final h = items[i];
                    final bg = AppTheme.cardBgFromBase(
                        app, h.card.labels, baseForCards, i);
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
                          Navigator.of(context).push(CupertinoPageRoute(
                              builder: (_) => CardDetailPage(
                                  cardId: h.card.id,
                                  boardId: h.boardId,
                                  stackId: h.stackId,
                                  bgColor: bg)));
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

  List<Widget> _buildSection(
      BuildContext context, String title, List<_DueHit> items,
      {bool emphasize = false,
      bool showEmpty = false,
      bool showEmptyHeaderOnly = false}) {
    if (items.isEmpty && !showEmpty && !showEmptyHeaderOnly) return const [];
    // NC 2.0: Einspalten-Modus im gleichen Look wie der Spalten-Modus —
    // fetter Header mit Zähler-Pill und echte _UpcomingTile-Karten statt
    // der alten nackten CupertinoButton-Zeilen (blaue Titel).
    final app = context.watch<AppState>();
    final themeColor = CupertinoTheme.of(context).textTheme.textStyle.color ??
        CupertinoColors.label;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
      child: Row(
        children: [
          Flexible(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: emphasize && items.isNotEmpty
                        ? CupertinoColors.destructiveRed
                        : themeColor)),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
            decoration: BoxDecoration(
              color: (emphasize && items.isNotEmpty
                      ? CupertinoColors.destructiveRed
                      : CupertinoColors.systemGrey)
                  .withOpacity(0.18),
              borderRadius: BorderRadius.circular(DT.radiusFull),
            ),
            child: Text('${items.length}',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: emphasize && items.isNotEmpty
                        ? CupertinoColors.destructiveRed
                        : CupertinoColors.systemGrey)),
          ),
        ],
      ),
    );
    if (items.isEmpty) {
      if (showEmptyHeaderOnly) {
        return [header];
      }
      if (showEmpty) {
        return [
          header,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Text(L10n.of(context).noDueCards,
                style: const TextStyle(
                    color: CupertinoColors.systemGrey, fontSize: 13)),
          ),
        ];
      }
      return const [];
    }
    final neutralBase = AppTheme.neutralCardBase(app);
    final baseForCards = app.cardColorsFromLabels
        ? (app.smartColors
            ? AppTheme.preferredColumnColor(app, title, 0)
            : neutralBase)
        : neutralBase;
    return [
      header,
      ...items.asMap().entries.map((entry) {
        final i = entry.key;
        final h = entry.value;
        final bg = AppTheme.cardBgFromBase(app, h.card.labels, baseForCards, i);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: _UpcomingTile(
            title: h.card.title,
            description: h.card.description,
            labels: h.card.labels,
            due: h.card.due,
            meta: '${h.boardTitle} · ${h.stackTitle}',
            background: bg,
            contextColor: AppTheme.textOn(bg),
            onTap: () {
              Navigator.of(context).push(CupertinoPageRoute(builder: (_) {
                return CardDetailPage(
                    cardId: h.card.id,
                    boardId: h.boardId,
                    stackId: h.stackId,
                    bgColor: bg);
              }));
            },
          ),
        );
      }),
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
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    // NC 2.0: identische Design-Sprache wie die Board-Karten — Licht-
    // Oberkante, weiche Elevation, Due-Badge als getönte Pill.
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(DT.radiusL),
          border: Border(
            top: BorderSide(
                color:
                    CupertinoColors.white.withOpacity(isDark ? 0.10 : 0.55),
                width: 1),
          ),
          boxShadow: DT.shadowM(isDark),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    height: 1.25,
                    color: textColor)),
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
                  return Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(description!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: textColor.withOpacity(0.72),
                            fontSize: 13.5,
                            height: 1.35)),
                  );
                }
                return const SizedBox.shrink();
              }),
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  if (due != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _dueColor(due!, textColor).withOpacity(0.16),
                        borderRadius: BorderRadius.circular(DT.radiusFull),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(CupertinoIcons.time,
                              size: 13, color: _dueColor(due!, textColor)),
                          const SizedBox(width: 4),
                          Text(
                            _formatDue(due!),
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: _dueColor(due!, textColor)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // Issue #84: Meta (Board · Stack) auch für Karten OHNE
                  // Fälligkeit anzeigen — sonst wüsste man in der neuen
                  // „Ohne Fälligkeit"-Sektion nicht, wo die Karte liegt.
                  Expanded(
                      child: Text(meta,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontSize: 12,
                              color: textColor.withOpacity(0.75)),
                          overflow: TextOverflow.ellipsis)),
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
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(label.title.isEmpty ? 'Label' : label.title,
          style:
              TextStyle(color: tc, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

Color _dueColor(DateTime due, Color defaultColor) {
  final now = DateTime.now();
  if (due.isBefore(now)) return CupertinoColors.systemRed;
  if (due.difference(now).inHours <= 24) return CupertinoColors.activeOrange;
  return defaultColor.withOpacity(0.98);
}

// Perf: Formatter einmal cachen statt pro Tile-Render neu konstruieren
final DateFormat _dueFormat = DateFormat.MMMd().add_Hm();

String _formatDue(DateTime due) => _dueFormat.format(due.toLocal());

Color? _parseDeckColor(String raw) {
  if (raw.isEmpty) return null;
  var s = raw.trim();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 3) {
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
  final r = bg.red / 255.0;
  final g = bg.green / 255.0;
  final b = bg.blue / 255.0;
  double lum(double c) =>
      c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4) as double;
  final L = 0.2126 * lum(r) + 0.7152 * lum(g) + 0.0722 * lum(b);
  return L > 0.5 ? CupertinoColors.black : CupertinoColors.white;
}

/// NC 2.0: kompakte Pager-Pill (‹ n/m ›) — fixes Overlay oben rechts,
/// identisch zur Board-Ansicht.
class _UpPagerPill extends StatelessWidget {
  final int current;
  final int total;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  const _UpPagerPill(
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

class _DueHit {
  final int boardId;
  final String boardTitle;
  final int stackId;
  final String stackTitle;
  final CardItem card;
  _DueHit(
      {required this.boardId,
      required this.boardTitle,
      required this.stackId,
      required this.stackTitle,
      required this.card});
}
