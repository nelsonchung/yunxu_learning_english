import 'package:flutter/services.dart';

class InstallStateService {
  static const MethodChannel _channel = MethodChannel('install_state');

  Future<bool> shouldAutoRestoreOnEmptyData() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'shouldAutoRestoreOnEmptyData',
      );
      return result ?? true;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return true;
    }
  }
}
