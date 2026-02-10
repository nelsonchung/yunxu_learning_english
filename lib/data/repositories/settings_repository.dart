import '../../domain/models/app_settings.dart';

abstract class SettingsRepository {
  Future<AppSettings> fetch();
  Future<void> save(AppSettings settings);
  Future<bool> hasSavedSettings();
}
