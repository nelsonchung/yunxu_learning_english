class AppSettings {
  AppSettings({
    required this.reminderMinutes,
    required this.showImages,
  });

  final int reminderMinutes;
  final bool showImages;

  static AppSettings defaults() {
    return AppSettings(
      reminderMinutes: 20 * 60,
      showImages: true,
    );
  }

  AppSettings copyWith({
    int? reminderMinutes,
    bool? showImages,
  }) {
    return AppSettings(
      reminderMinutes: reminderMinutes ?? this.reminderMinutes,
      showImages: showImages ?? this.showImages,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'reminderMinutes': reminderMinutes,
      'showImages': showImages,
    };
  }

  static AppSettings fromMap(Map data) {
    final minutes = data['reminderMinutes'];
    final showImages = data['showImages'];

    return AppSettings(
      reminderMinutes: minutes is int ? minutes : 20 * 60,
      showImages: showImages is bool ? showImages : true,
    );
  }
}
