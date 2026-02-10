enum RestoreStatus { idle, restoring, restored, newInstall, failed }

class SyncState {
  SyncState({
    this.lastSyncAt,
    this.lastAttemptAt,
    this.lastRestoreAttemptAt,
    this.lastErrorCode,
    this.lastErrorMessage,
    this.restoreStatus = RestoreStatus.idle,
    this.hasEverSynced = false,
  });

  final DateTime? lastSyncAt;
  final DateTime? lastAttemptAt;
  final DateTime? lastRestoreAttemptAt;
  final String? lastErrorCode;
  final String? lastErrorMessage;
  final RestoreStatus restoreStatus;
  final bool hasEverSynced;

  SyncState copyWith({
    DateTime? lastSyncAt,
    bool clearLastSyncAt = false,
    DateTime? lastAttemptAt,
    bool clearLastAttemptAt = false,
    DateTime? lastRestoreAttemptAt,
    bool clearLastRestoreAttemptAt = false,
    String? lastErrorCode,
    bool clearLastErrorCode = false,
    String? lastErrorMessage,
    bool clearLastErrorMessage = false,
    RestoreStatus? restoreStatus,
    bool? hasEverSynced,
  }) {
    return SyncState(
      lastSyncAt: clearLastSyncAt ? null : (lastSyncAt ?? this.lastSyncAt),
      lastAttemptAt: clearLastAttemptAt
          ? null
          : (lastAttemptAt ?? this.lastAttemptAt),
      lastRestoreAttemptAt: clearLastRestoreAttemptAt
          ? null
          : (lastRestoreAttemptAt ?? this.lastRestoreAttemptAt),
      lastErrorCode: clearLastErrorCode
          ? null
          : (lastErrorCode ?? this.lastErrorCode),
      lastErrorMessage: clearLastErrorMessage
          ? null
          : (lastErrorMessage ?? this.lastErrorMessage),
      restoreStatus: restoreStatus ?? this.restoreStatus,
      hasEverSynced: hasEverSynced ?? this.hasEverSynced,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'lastSyncAt': lastSyncAt?.millisecondsSinceEpoch,
      'lastAttemptAt': lastAttemptAt?.millisecondsSinceEpoch,
      'lastRestoreAttemptAt': lastRestoreAttemptAt?.millisecondsSinceEpoch,
      'lastErrorCode': lastErrorCode,
      'lastErrorMessage': lastErrorMessage,
      'restoreStatus': restoreStatus.name,
      'hasEverSynced': hasEverSynced,
    };
  }

  static SyncState fromMap(Map data) {
    final lastSyncAtRaw = data['lastSyncAt'];
    final lastAttemptAtRaw = data['lastAttemptAt'];
    final lastRestoreAttemptAtRaw = data['lastRestoreAttemptAt'];
    final restoreStatusRaw = data['restoreStatus'];
    final hasEverSyncedRaw = data['hasEverSynced'];

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
      lastRestoreAttemptAt: lastRestoreAttemptAtRaw is int
          ? DateTime.fromMillisecondsSinceEpoch(lastRestoreAttemptAtRaw)
          : null,
      lastErrorCode: data['lastErrorCode'] as String?,
      lastErrorMessage: data['lastErrorMessage'] as String?,
      restoreStatus: parsedRestoreStatus,
      hasEverSynced: hasEverSyncedRaw is bool ? hasEverSyncedRaw : false,
    );
  }
}
