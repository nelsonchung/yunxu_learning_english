import '../../domain/models/app_settings.dart';
import '../sources/settings_local_db.dart';
import 'settings_repository.dart';

class LocalSettingsRepository implements SettingsRepository {
  LocalSettingsRepository({required SettingsLocalDb localDb})
    : _localDb = localDb;

  final SettingsLocalDb _localDb;

  @override
  Future<AppSettings> fetch() async {
    final raw = await _localDb.getSettings();
    if (raw == null) {
      return AppSettings.defaults();
    }
    return AppSettings.fromMap(raw);
  }

  @override
  Future<void> save(AppSettings settings) async {
    await _localDb.putSettings(settings.toMap());
  }

  @override
  Future<bool> hasSavedSettings() async {
    final raw = await _localDb.getSettings();
    return raw != null;
  }
}
