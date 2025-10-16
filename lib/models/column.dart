import 'card_item.dart';

class Column {
  final int id;
  final String title;
  final List<CardItem> cards;

  const Column({required this.id, required this.title, required this.cards});

  factory Column.fromJson(Map<String, dynamic> json) {
    final raw = json['cards'];
    final list = (raw is List) ? raw.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList() : const <Map<String, dynamic>>[];
    return Column(
      id: (json['id'] as num).toInt(),
      title: (json['title'] ?? json['name'] ?? '').toString(),
      cards: list.map(CardItem.fromJson).toList(),
    );
  }
}
