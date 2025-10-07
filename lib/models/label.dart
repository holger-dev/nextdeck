class Label {
  final int id;
  final String title;
  final String color; // hex string like 'a6d5a2' or '#a6d5a2'

  const Label({required this.id, required this.title, required this.color});

  factory Label.fromJson(Map<String, dynamic> json) {
    return Label(
      id: (json['id'] as num?)?.toInt() ?? -1,
      title: (json['title'] ?? json['name'] ?? '').toString(),
      color: (json['color'] ?? '').toString(),
    );
  }
}

