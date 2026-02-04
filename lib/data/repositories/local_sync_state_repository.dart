import '../../domain/models/sync_state.dart';
import '../sources/sync_state_local_db.dart';
import 'sync_state_repository.dart';

class LocalSyncStateRepository implements SyncStateRepository {
  LocalSyncStateRepository({required SyncStateLocalDb localDb})
      : _localDb = localDb;

  final SyncStateLocalDb _localDb;

  @override
  Future<SyncState> fetch() async {
    final raw = await _localDb.getState();
    if (raw == null) {
      return SyncState();
    }
    return SyncState.fromMap(raw);
  }

  @override
  Future<void> save(SyncState state) async {
    await _localDb.putState(state.toMap());
  }
}
