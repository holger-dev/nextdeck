class Board {
  final int id;
  final String title;
  final String? color; // Nextcloud board color (e.g., "#0082C3" or "0082C3")
  final bool archived;

  const Board({required this.id, required this.title, this.color, this.archived = false});

  factory Board.fromJson(Map<String, dynamic> json) => Board(
        id: (json['id'] as num).toInt(),
        title: (json['title'] ?? json['name'] ?? '').toString(),
        color: (json['color'] ?? json['boardColor'] ?? json['bgcolor'])?.toString(),
        archived: _readArchived(json),
      );

  static bool _readArchived(Map<String, dynamic> json) {
    final a = json['archived'] ?? json['isArchived'] ?? json['archivedAt'];
    if (a == null) return false;
    if (a is bool) return a;
    if (a is num) return a != 0;
    final s = a.toString();
    if (s.isEmpty) return false;
    if (s.toLowerCase() == 'true') return true;
    return true; // any non-empty archivedAt treated as archived
  }

  static Board empty() => const Board(id: -1, title: 'Board');
}
