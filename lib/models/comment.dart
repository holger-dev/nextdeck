class CommentMention {
  final String mentionId;
  final String mentionType;
  final String mentionDisplayName;
  const CommentMention({required this.mentionId, required this.mentionType, required this.mentionDisplayName});
  factory CommentMention.fromJson(Map<String, dynamic> json) => CommentMention(
        mentionId: (json['mentionId'] ?? '').toString(),
        mentionType: (json['mentionType'] ?? '').toString(),
        mentionDisplayName: (json['mentionDisplayName'] ?? '').toString(),
      );
}

class CommentItem {
  final int id;
  final int objectId; // cardId
  final String message;
  final String actorId;
  final String actorType;
  final String actorDisplayName;
  final DateTime creationDateTime;
  final List<CommentMention> mentions;
  final CommentItem? replyTo;

  const CommentItem({
    required this.id,
    required this.objectId,
    required this.message,
    required this.actorId,
    required this.actorType,
    required this.actorDisplayName,
    required this.creationDateTime,
    this.mentions = const [],
    this.replyTo,
  });

  factory CommentItem.fromJson(Map<String, dynamic> json) {
    final reply = json['replyTo'];
    return CommentItem(
      id: (json['id'] as num).toInt(),
      objectId: (json['objectId'] as num).toInt(),
      message: (json['message'] ?? '').toString(),
      actorId: (json['actorId'] ?? '').toString(),
      actorType: (json['actorType'] ?? '').toString(),
      actorDisplayName: (json['actorDisplayName'] ?? '').toString(),
      creationDateTime: DateTime.tryParse((json['creationDateTime'] ?? '').toString()) ?? DateTime.now().toUtc(),
      mentions: ((json['mentions'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => CommentMention.fromJson(m.cast<String, dynamic>()))
          .toList(),
      replyTo: (reply is Map) ? CommentItem.fromJson(reply.cast<String, dynamic>()) : null,
    );
  }
}

