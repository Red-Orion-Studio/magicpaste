// User preferences shown on the Settings screen.

import 'package:shared_preferences/shared_preferences.dart';

enum ImageQuality { low, medium, high }

class AppSettings {
  final ImageQuality quality;
  final bool confirmationSound;
  final bool autoStartOnBoot;
  final bool guaranteedBg;

  const AppSettings({
    this.quality = ImageQuality.high,
    this.confirmationSound = true,
    this.autoStartOnBoot = true,
    this.guaranteedBg = false,
  });

  AppSettings copyWith({
    ImageQuality? quality,
    bool? confirmationSound,
    bool? autoStartOnBoot,
    bool? guaranteedBg,
  }) =>
      AppSettings(
        quality: quality ?? this.quality,
        confirmationSound: confirmationSound ?? this.confirmationSound,
        autoStartOnBoot: autoStartOnBoot ?? this.autoStartOnBoot,
        guaranteedBg: guaranteedBg ?? this.guaranteedBg,
      );
}

class SettingsService {
  static const _kQuality = 'mp_quality';
  static const _kSound = 'mp_sound';
  static const _kBoot = 'mp_boot';
  // Native reads this as "flutter.mp_guaranteed_bg" (SyncWorker.KEY_GUARANTEED).
  static const _kGuaranteed = 'mp_guaranteed_bg';

  static Future<AppSettings> load() async {
    final p = await SharedPreferences.getInstance();
    // The native side (notification "Desactivar" action) can flip
    // mp_guaranteed_bg directly on disk; reload so we don't read a stale
    // in-memory copy.
    await p.reload();
    return AppSettings(
      quality: ImageQuality.values[(p.getInt(_kQuality) ?? ImageQuality.high.index)
          .clamp(0, ImageQuality.values.length - 1)],
      confirmationSound: p.getBool(_kSound) ?? true,
      autoStartOnBoot: p.getBool(_kBoot) ?? true,
      guaranteedBg: p.getBool(_kGuaranteed) ?? false,
    );
  }

  static Future<void> setQuality(ImageQuality q) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kQuality, q.index);
  }

  static Future<void> setSound(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kSound, v);
  }

  static Future<void> setBoot(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kBoot, v);
  }

  static Future<void> setGuaranteed(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kGuaranteed, v);
  }
}
