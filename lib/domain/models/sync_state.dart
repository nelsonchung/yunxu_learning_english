enum RestoreStatus { idle, restoring, restored, newInstall, failed }

class SyncState {
  SyncState({
    this.lastSyncAt,
    this.lastAttemptAt,
    this.lastErrorCode,
    this.lastErrorMessage,
    this.restoreStatus = RestoreStatus.idle,
  });

  final DateTime? lastSyncAt;
  final DateTime? lastAttemptAt;
  final String? lastErrorCode;
  final String? lastErrorMessage;
  final RestoreStatus restoreStatus;

  SyncState copyWith({
    DateTime? lastSyncAt,
    bool clearLastSyncAt = false,
    DateTime? lastAttemptAt,
    bool clearLastAttemptAt = false,
    String? lastErrorCode,
    bool clearLastErrorCode = false,
    String? lastErrorMessage,
    bool clearLastErrorMessage = false,
    RestoreStatus? restoreStatus,
  }) {
    return SyncState(
      lastSyncAt: clearLastSyncAt ? null : (lastSyncAt ?? this.lastSyncAt),
      lastAttemptAt: clearLastAttemptAt
          ? null
          : (lastAttemptAt ?? this.lastAttemptAt),
      lastErrorCode: clearLastErrorCode
          ? null
          : (lastErrorCode ?? this.lastErrorCode),
      lastErrorMessage: clearLastErrorMessage
          ? null
          : (lastErrorMessage ?? this.lastErrorMessage),
      restoreStatus: restoreStatus ?? this.restoreStatus,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'lastSyncAt': lastSyncAt?.millisecondsSinceEpoch,
      'lastAttemptAt': lastAttemptAt?.millisecondsSinceEpoch,
      'lastErrorCode': lastErrorCode,
      'lastErrorMessage': lastErrorMessage,
      'restoreStatus': restoreStatus.name,
    };
  }

  static SyncState fromMap(Map data) {
    final lastSyncAtRaw = data['lastSyncAt'];
    final lastAttemptAtRaw = data['lastAttemptAt'];
    final restoreStatusRaw = data['restoreStatus'];

    final parsedRestoreStatus = restoreStatusRaw is String
        ? RestoreStatus.values.firstWhere(
            (item) => item.name == restoreStatusRaw,
            orElse: () => RestoreStatus.idle,
          )
        : RestoreStatus.idle;

    return SyncState(
      lastSyncAt: lastSyncAtRaw is int
          ? DateTime.fromMillisecondsSinceEpoch(lastSyncAtRaw)
          : null,
      lastAttemptAt: lastAttemptAtRaw is int
          ? DateTime.fromMillisecondsSinceEpoch(lastAttemptAtRaw)
          : null,
      lastErrorCode: data['lastErrorCode'] as String?,
      lastErrorMessage: data['lastErrorMessage'] as String?,
      restoreStatus: parsedRestoreStatus,
    );
  }
}
