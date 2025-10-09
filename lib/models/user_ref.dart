class UserRef {
  final String id; // uid or group id (primary)
  final String displayName;
  final int? shareType; // 0 user, 1 group (optional)
  final String? altId; // optional alternative id (e.g., unique display like email)
  const UserRef({required this.id, required this.displayName, this.shareType, this.altId});

  factory UserRef.fromJson(Map<String, dynamic> json) {
    return UserRef(
      id: (json['uid'] ?? json['id'] ?? json['userId'] ?? json['userid'] ?? '').toString(),
      displayName: (json['displayname'] ?? json['displayName'] ?? json['label'] ?? json['name'] ?? '').toString(),
      shareType: (json['shareType'] as num?)?.toInt(),
      altId: (json['shareWithDisplayNameUnique'] ?? json['unique'] ?? '').toString().isEmpty
          ? null
          : (json['shareWithDisplayNameUnique'] ?? json['unique']).toString(),
    );
  }
}
