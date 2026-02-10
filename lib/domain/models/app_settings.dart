class AppSettings {
  AppSettings({
    required this.reminderMinutes,
    required this.showImages,
    required this.reminderEnabled,
    required this.syncEnabled,
    required this.syncIntervalSeconds,
    required this.updatedAt,
  });

  final int reminderMinutes;
  final bool showImages;
  final bool reminderEnabled;
  final bool syncEnabled;
  final int syncIntervalSeconds;
  final DateTime updatedAt;

  static AppSettings defaults() {
    return AppSettings(
      reminderMinutes: 20 * 60,
      showImages: true,
      reminderEnabled: true,
      syncEnabled: true,
      syncIntervalSeconds: 60,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  AppSettings copyWith({
    int? reminderMinutes,
    bool? showImages,
    bool? reminderEnabled,
    bool? syncEnabled,
    int? syncIntervalSeconds,
    DateTime? updatedAt,
  }) {
    return AppSettings(
      reminderMinutes: reminderMinutes ?? this.reminderMinutes,
      showImages: showImages ?? this.showImages,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      syncEnabled: syncEnabled ?? this.syncEnabled,
      syncIntervalSeconds: syncIntervalSeconds ?? this.syncIntervalSeconds,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'reminderMinutes': reminderMinutes,
      'showImages': showImages,
      'reminderEnabled': reminderEnabled,
      'syncEnabled': syncEnabled,
      'syncIntervalSeconds': syncIntervalSeconds,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  static AppSettings fromMap(Map data) {
    final minutes = data['reminderMinutes'];
    final showImages = data['showImages'];
    final reminderEnabled = data['reminderEnabled'];
    final syncEnabled = data['syncEnabled'];
    final syncIntervalSeconds = data['syncIntervalSeconds'];
    final updatedAtRaw = data['updatedAt'];

    return AppSettings(
      reminderMinutes: minutes is int ? minutes : 20 * 60,
      showImages: showImages is bool ? showImages : true,
      reminderEnabled: reminderEnabled is bool ? reminderEnabled : true,
      syncEnabled: syncEnabled is bool ? syncEnabled : true,
      syncIntervalSeconds: syncIntervalSeconds is int
          ? syncIntervalSeconds
          : 60,
      updatedAt: updatedAtRaw is int
          ? DateTime.fromMillisecondsSinceEpoch(updatedAtRaw)
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
