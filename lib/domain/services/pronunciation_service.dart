import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/app_settings.dart';

class PronunciationService {
  PronunciationService({FlutterTts? flutterTts})
    : _flutterTts = flutterTts ?? FlutterTts();

  final FlutterTts _flutterTts;

  bool _initialized = false;
  bool _supported = !Platform.isLinux;
  bool _enabled = true;
  double _rate = 0.45;
  String _locale = 'en-US';

  bool get isSupported => _supported;
  bool get isEnabled => _enabled;
  double get rate => _rate;
  String get locale => _locale;

  Future<void> initialize(AppSettings settings) async {
    _enabled = settings.pronunciationEnabled;
    _rate = settings.pronunciationRate;
    _locale = settings.pronunciationLocale;

    if (!_supported || _initialized) {
      return;
    }

    try {
      await _flutterTts.awaitSpeakCompletion(true);
      if (Platform.isAndroid) {
        await _flutterTts.setQueueMode(0);
      }
      if (Platform.isIOS || Platform.isMacOS) {
        await _flutterTts.setSharedInstance(true);
        await _configureAppleAudioSession();
      }
      _initialized = true;
      await applySettings(settings);
    } on MissingPluginException {
      _supported = false;
    } catch (_) {
      _supported = false;
    }
  }

  Future<void> applySettings(AppSettings settings) async {
    _enabled = settings.pronunciationEnabled;
    _rate = settings.pronunciationRate;
    _locale = settings.pronunciationLocale;

    if (!_supported) {
      return;
    }

    await _ensureInitialized(settings);
    if (!_supported || !_initialized) {
      return;
    }

    if (!_enabled) {
      await stop();
      return;
    }

    try {
      await _flutterTts.setSpeechRate(_rate);
      await _setLanguageWithFallback(_locale);
    } on MissingPluginException {
      _supported = false;
    } catch (_) {
      // Keep the app usable even if a locale is unavailable.
    }
  }

  Future<bool> speak(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || !_enabled || !_supported) {
      return false;
    }

    await _ensureInitialized(
      AppSettings.defaults().copyWith(
        pronunciationEnabled: _enabled,
        pronunciationRate: _rate,
        pronunciationLocale: _locale,
      ),
    );
    if (!_supported || !_initialized) {
      return false;
    }

    try {
      await _flutterTts.stop();
      await _flutterTts.setSpeechRate(_rate);
      await _setLanguageWithFallback(_locale);
      final result = await _flutterTts.speak(trimmed);
      return result == 1;
    } on MissingPluginException {
      _supported = false;
      return false;
    } catch (_) {
      return false;
    }
  }

  String? extractEnglishUtterance(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final cjkMatch = RegExp(r'[\u3400-\u9FFF]').firstMatch(trimmed);
    final candidate = cjkMatch == null
        ? trimmed
        : trimmed.substring(0, cjkMatch.start);

    final cleaned = candidate
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceFirst(RegExp(r'^[•·\-\s]+'), '')
        .trim();

    if (cleaned.isEmpty || !RegExp(r'[A-Za-z]').hasMatch(cleaned)) {
      return null;
    }

    return cleaned;
  }

  Future<void> stop() async {
    if (!_supported || !_initialized) {
      return;
    }

    try {
      await _flutterTts.stop();
    } on MissingPluginException {
      _supported = false;
    } catch (_) {
      // No-op.
    }
  }

  Future<void> _ensureInitialized(AppSettings settings) async {
    if (_initialized || !_supported) {
      return;
    }
    await initialize(settings);
  }

  Future<void> _setLanguageWithFallback(String value) async {
    if (!_supported || !_initialized) {
      return;
    }

    final normalized = value.trim().isEmpty ? 'en-US' : value.trim();
    try {
      final availability = await _flutterTts.isLanguageAvailable(normalized);
      if (availability == true) {
        await _flutterTts.setLanguage(normalized);
        return;
      }
    } catch (_) {
      // Some platforms do not implement availability checks consistently.
    }

    await _flutterTts.setLanguage('en-US');
  }

  Future<void> _configureAppleAudioSession() async {
    if (Platform.isIOS) {
      await _flutterTts.setIosAudioCategory(
        // `playback` keeps TTS audible even when the iPhone mute switch is on.
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          IosTextToSpeechAudioCategoryOptions.duckOthers,
          IosTextToSpeechAudioCategoryOptions
              .interruptSpokenAudioAndMixWithOthers,
        ],
        IosTextToSpeechAudioMode.voicePrompt,
      );
      return;
    }

    await _flutterTts
        .setIosAudioCategory(IosTextToSpeechAudioCategory.ambient, [
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
        ], IosTextToSpeechAudioMode.voicePrompt);
  }
}
