import 'package:flutter/cupertino.dart';
import 'dart:async';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../models/card_item.dart';
import '../models/column.dart' as deck;
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import 'card_detail_page.dart';

class GlobalSearchPage extends StatefulWidget {
  const GlobalSearchPage({super.key});
  @override
  State<GlobalSearchPage> createState() => _GlobalSearchPageState();
}

class _GlobalSearchPageState extends State<GlobalSearchPage> {
  final TextEditingController _query = TextEditingController();
  List<_Hit> _hits = const [];
  bool _loading = false;
  Timer? _debounce;

  Future<void> _ensureAllCardsLoaded(AppState app) async {
    // DISABLED: Use local data only instead of old sync system
    // Load stacks and cards for all boards best-effort
    // for (final b in app.boards.where((x) => !x.archived)) {
    //   await app.refreshColumnsFor(b);
    //   for (final c in app.columnsForBoard(b.id)) {
    //     await app.ensureCardsFor(b.id, c.id);
    //   }
    // }
  }

  Future<void> _doSearch() async {
    final q = _query.text.trim().toLowerCase();
    final app = context.read<AppState>();
    setState(() { _loading = true; });
    await _ensureAllCardsLoaded(app);
    final res = <_Hit>[];
    for (final b in app.boards.where((x) => !x.archived)) {
      final cols = app.columnsForBoard(b.id);
      for (final c in cols) {
        for (final k in c.cards) {
          final inTitle = k.title.toLowerCase().contains(q);
          final inDesc = (k.description ?? '').toLowerCase().contains(q);
          if (q.isEmpty || inTitle || inDesc) {
            res.add(_Hit(boardId: b.id, boardTitle: b.title, stackId: c.id, stackTitle: c.title, card: k));
          }
        }
      }
    }
    setState(() { _hits = res; _loading = false; });
  }

  @override
  void initState() {
    super.initState();
    _query.addListener(() {
      final q = _query.text.trim();
      _debounce?.cancel();
      if (q.length >= 3) {
        _debounce = Timer(const Duration(milliseconds: 250), () { if (mounted) _doSearch(); });
      } else if (q.isEmpty) {
        setState(() { _hits = const []; });
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final l10n = L10n.of(context);
    return CupertinoPageScaffold(
      backgroundColor: AppTheme.appBackground(app),
      navigationBar: CupertinoNavigationBar(middle: Text(l10n.searchAllBoards)),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoTextField(
                      controller: _query,
                      placeholder: l10n.searchPlaceholder,
                      onSubmitted: (_) => _doSearch(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CupertinoButton.filled(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), onPressed: _doSearch, child: const Icon(CupertinoIcons.search)),
                ],
              ),
            ),
            if (_loading)
              const Expanded(child: Center(child: CupertinoActivityIndicator()))
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _hits.length,
                  itemBuilder: (ctx, i) {
                    final h = _hits[i];
                    return CupertinoButton(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
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
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Hit {
  final int boardId;
  final String boardTitle;
  final int stackId;
  final String stackTitle;
  final CardItem card;
  _Hit({required this.boardId, required this.boardTitle, required this.stackId, required this.stackTitle, required this.card});
}

