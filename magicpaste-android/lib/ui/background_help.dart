import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/l10n.dart';
import 'theme.dart';

/// Bridge to the native MIUI deep-links + OEM detection.
class BackgroundHelp {
  static const _ch = MethodChannel('magicpaste/native');

  static Future<bool> isXiaomi() async {
    try {
      return (await _ch.invokeMethod<bool>('isXiaomi')) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openAutostart() async {
    try {
      await _ch.invokeMethod('openAutostart');
    } catch (_) {}
  }

  static Future<void> openBattery() async {
    try {
      await _ch.invokeMethod('openBattery');
    } catch (_) {}
  }

  static Future<void> openAppDetails() async {
    try {
      await _ch.invokeMethod('openAppDetails');
    } catch (_) {}
  }
}

/// Bottom sheet that walks the user through the OEM settings needed for
/// reliable background detection (Autostart, no battery limits, lock in
/// recents) with deep-link buttons. Shown when enabling "Always-on detection"
/// on Xiaomi, and on demand from Settings.
Future<void> showBackgroundHelp(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _BackgroundHelpSheet(),
  );
}

class _BackgroundHelpSheet extends StatelessWidget {
  const _BackgroundHelpSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF161318),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(top: BorderSide(color: MP.glassBorder)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0x33FFFFFF),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(L10n.t('bg_title'),
                style: const TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w700, color: MP.textPrimary)),
            const SizedBox(height: 6),
            Text(
              L10n.t('bg_intro'),
              style: const TextStyle(fontSize: 13, color: MP.textSec, height: 1.45),
            ),
            const SizedBox(height: 18),
            _Step(
              n: '1',
              title: L10n.t('bg_s1_title'),
              desc: L10n.t('bg_s1_desc'),
              action: L10n.t('bg_s1_action'),
              onTap: BackgroundHelp.openAutostart,
            ),
            const SizedBox(height: 12),
            _Step(
              n: '2',
              title: L10n.t('bg_s2_title'),
              desc: L10n.t('bg_s2_desc'),
              action: L10n.t('bg_s2_action'),
              onTap: BackgroundHelp.openBattery,
            ),
            const SizedBox(height: 12),
            _Step(
              n: '3',
              title: L10n.t('bg_s3_title'),
              desc: L10n.t('bg_s3_desc'),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  backgroundColor: MP.violet,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(L10n.t('done'),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String n;
  final String title;
  final String desc;
  final String? action;
  final Future<void> Function()? onTap;
  const _Step({
    required this.n,
    required this.title,
    required this.desc,
    this.action,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MP.glass,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MP.glassBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [MP.violet, Color(0xFF5B21B6)]),
            ),
            child: Text(n,
                style: const TextStyle(
                    color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w700, color: MP.textPrimary)),
                const SizedBox(height: 3),
                Text(desc,
                    style: const TextStyle(fontSize: 12.5, color: MP.textSec, height: 1.4)),
                if (action != null && onTap != null) ...[
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: onTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0x2E7C3AED),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0x597C3AED)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(action!,
                              style: const TextStyle(
                                  color: MP.violetLight,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(width: 6),
                          const Icon(Icons.arrow_forward, size: 13, color: MP.violetLight),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
