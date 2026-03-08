class AppSettings {
  AppSettings({
    required this.reminderMinutes,
    required this.showImages,
    required this.reminderEnabled,
    required this.syncEnabled,
    required this.syncIntervalSeconds,
    required this.pronunciationEnabled,
    required this.pronunciationRate,
    required this.pronunciationLocale,
    required this.updatedAt,
  });

  final int reminderMinutes;
  final bool showImages;
  final bool reminderEnabled;
  final bool syncEnabled;
  final int syncIntervalSeconds;
  final bool pronunciationEnabled;
  final double pronunciationRate;
  final String pronunciationLocale;
  final DateTime updatedAt;

  static AppSettings defaults() {
    return AppSettings(
      reminderMinutes: 20 * 60,
      showImages: true,
      reminderEnabled: true,
      syncEnabled: true,
      syncIntervalSeconds: 60,
      pronunciationEnabled: true,
      pronunciationRate: 0.45,
      pronunciationLocale: 'en-US',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  AppSettings copyWith({
    int? reminderMinutes,
    bool? showImages,
    bool? reminderEnabled,
    bool? syncEnabled,
    int? syncIntervalSeconds,
    bool? pronunciationEnabled,
    double? pronunciationRate,
    String? pronunciationLocale,
    DateTime? updatedAt,
  }) {
    return AppSettings(
      reminderMinutes: reminderMinutes ?? this.reminderMinutes,
      showImages: showImages ?? this.showImages,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      syncEnabled: syncEnabled ?? this.syncEnabled,
      syncIntervalSeconds: syncIntervalSeconds ?? this.syncIntervalSeconds,
      pronunciationEnabled: pronunciationEnabled ?? this.pronunciationEnabled,
      pronunciationRate: pronunciationRate ?? this.pronunciationRate,
      pronunciationLocale: pronunciationLocale ?? this.pronunciationLocale,
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
      'pronunciationEnabled': pronunciationEnabled,
      'pronunciationRate': pronunciationRate,
      'pronunciationLocale': pronunciationLocale,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  static AppSettings fromMap(Map data) {
    final minutes = data['reminderMinutes'];
    final showImages = data['showImages'];
    final reminderEnabled = data['reminderEnabled'];
    final syncEnabled = data['syncEnabled'];
    final syncIntervalSeconds = data['syncIntervalSeconds'];
    final pronunciationEnabled = data['pronunciationEnabled'];
    final pronunciationRate = data['pronunciationRate'];
    final pronunciationLocale = data['pronunciationLocale'];
    final updatedAtRaw = data['updatedAt'];

    return AppSettings(
      reminderMinutes: minutes is int ? minutes : 20 * 60,
      showImages: showImages is bool ? showImages : true,
      reminderEnabled: reminderEnabled is bool ? reminderEnabled : true,
      syncEnabled: syncEnabled is bool ? syncEnabled : true,
      syncIntervalSeconds: syncIntervalSeconds is int
          ? syncIntervalSeconds
          : 60,
      pronunciationEnabled: pronunciationEnabled is bool
          ? pronunciationEnabled
          : true,
      pronunciationRate: pronunciationRate is num
          ? pronunciationRate.toDouble()
          : 0.45,
      pronunciationLocale:
          pronunciationLocale is String && pronunciationLocale.trim().isNotEmpty
          ? pronunciationLocale.trim()
          : 'en-US',
      updatedAt: updatedAtRaw is int
          ? DateTime.fromMillisecondsSinceEpoch(updatedAtRaw)
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
