// Bridge to the native (Kotlin) WorkManager-based background sync.
//
// The heavy lifting — MediaStore URI triggers, foreground service, reboot
// survival — happens in Kotlin (see android/.../SyncWorker.kt). This just
// flips it on/off and triggers a one-shot run.

import 'package:flutter/services.dart';

class NativeSync {
  static const _channel = MethodChannel('magicpaste/native');

  /// Arm the URI trigger + periodic safety-net work.
  static Future<void> enable() async {
    await _channel.invokeMethod('enableAutoSync');
  }

  /// Cancel all background work.
  static Future<void> disable() async {
    await _channel.invokeMethod('disableAutoSync');
  }

  /// Toggle "always-on detection": the persistent foreground service that
  /// keeps detecting screenshots even when the app is fully closed (needed on
  /// aggressive OEMs like Xiaomi). Off = lightweight WorkManager trigger only,
  /// no persistent notification.
  static Future<void> setGuaranteed(bool enabled) async {
    await _channel.invokeMethod('setGuaranteedBg', {'enabled': enabled});
  }

  /// Fire a one-shot sync now (used by the manual "send latest" button as a
  /// fallback, and to flush anything pending right after enabling).
  static Future<void> runOnce() async {
    await _channel.invokeMethod('runOnce');
  }

  /// Play the short confirmation beep (same sound as background sends).
  static Future<void> beep() async {
    try {
      await _channel.invokeMethod('beep');
    } catch (_) {}
  }

  /// This phone's name (user-set, else brand + model) to show on the PC.
  static Future<String> deviceName() async {
    try {
      final n = await _channel.invokeMethod<String>('getDeviceName');
      if (n != null && n.trim().isNotEmpty) return n.trim();
    } catch (_) {}
    return 'Android phone';
  }
}
