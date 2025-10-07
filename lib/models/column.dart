import 'card_item.dart';

class Column {
  final int id;
  final String title;
  final List<CardItem> cards;

  const Column({required this.id, required this.title, required this.cards});

  factory Column.fromJson(Map<String, dynamic> json) {
    final list = (json['cards'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    return Column(
      id: json['id'] as int,
      title: (json['title'] ?? json['name'] ?? '').toString(),
      cards: list.map(CardItem.fromJson).toList(),
    );
  }
}

