class AppSettings {
  AppSettings({
    required this.reminderMinutes,
    required this.showImages,
    required this.reminderEnabled,
  });

  final int reminderMinutes;
  final bool showImages;
  final bool reminderEnabled;

  static AppSettings defaults() {
    return AppSettings(
      reminderMinutes: 20 * 60,
      showImages: true,
      reminderEnabled: true,
    );
  }

  AppSettings copyWith({
    int? reminderMinutes,
    bool? showImages,
    bool? reminderEnabled,
  }) {
    return AppSettings(
      reminderMinutes: reminderMinutes ?? this.reminderMinutes,
      showImages: showImages ?? this.showImages,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'reminderMinutes': reminderMinutes,
      'showImages': showImages,
      'reminderEnabled': reminderEnabled,
    };
  }

  static AppSettings fromMap(Map data) {
    final minutes = data['reminderMinutes'];
    final showImages = data['showImages'];
    final reminderEnabled = data['reminderEnabled'];

    return AppSettings(
      reminderMinutes: minutes is int ? minutes : 20 * 60,
      showImages: showImages is bool ? showImages : true,
      reminderEnabled: reminderEnabled is bool ? reminderEnabled : true,
    );
  }
}
