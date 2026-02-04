class SyncState {
  SyncState({this.lastSyncAt});

  final DateTime? lastSyncAt;

  SyncState copyWith({DateTime? lastSyncAt}) {
    return SyncState(lastSyncAt: lastSyncAt ?? this.lastSyncAt);
  }

  Map<String, Object?> toMap() {
    return {
      'lastSyncAt': lastSyncAt?.millisecondsSinceEpoch,
    };
  }

  static SyncState fromMap(Map data) {
    final raw = data['lastSyncAt'];
    final lastSyncAt = raw is int ? DateTime.fromMillisecondsSinceEpoch(raw) : null;
    return SyncState(lastSyncAt: lastSyncAt);
  }
}
