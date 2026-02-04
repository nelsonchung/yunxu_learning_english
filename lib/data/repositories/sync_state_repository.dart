import '../../domain/models/sync_state.dart';

abstract class SyncStateRepository {
  Future<SyncState> fetch();
  Future<void> save(SyncState state);
}
