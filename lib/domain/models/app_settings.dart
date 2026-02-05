class AppSettings {
  AppSettings({
    required this.reminderMinutes,
    required this.showImages,
    required this.reminderEnabled,
    required this.syncIntervalSeconds,
  });

  final int reminderMinutes;
  final bool showImages;
  final bool reminderEnabled;
  final int syncIntervalSeconds;

  static AppSettings defaults() {
    return AppSettings(
      reminderMinutes: 20 * 60,
      showImages: true,
      reminderEnabled: true,
      syncIntervalSeconds: 60,
    );
  }

  AppSettings copyWith({
    int? reminderMinutes,
    bool? showImages,
    bool? reminderEnabled,
    int? syncIntervalSeconds,
  }) {
    return AppSettings(
      reminderMinutes: reminderMinutes ?? this.reminderMinutes,
      showImages: showImages ?? this.showImages,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      syncIntervalSeconds: syncIntervalSeconds ?? this.syncIntervalSeconds,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'reminderMinutes': reminderMinutes,
      'showImages': showImages,
      'reminderEnabled': reminderEnabled,
      'syncIntervalSeconds': syncIntervalSeconds,
    };
  }

  static AppSettings fromMap(Map data) {
    final minutes = data['reminderMinutes'];
    final showImages = data['showImages'];
    final reminderEnabled = data['reminderEnabled'];
    final syncIntervalSeconds = data['syncIntervalSeconds'];

    return AppSettings(
      reminderMinutes: minutes is int ? minutes : 20 * 60,
      showImages: showImages is bool ? showImages : true,
      reminderEnabled: reminderEnabled is bool ? reminderEnabled : true,
      syncIntervalSeconds: syncIntervalSeconds is int ? syncIntervalSeconds : 60,
    );
  }
}
