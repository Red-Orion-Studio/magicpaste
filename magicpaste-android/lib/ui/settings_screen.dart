import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/l10n.dart';
import '../services/native_sync.dart';
import '../services/pairing_service.dart';
import '../services/settings_service.dart';
import 'background_help.dart';
import 'theme.dart';

class SettingsScreen extends StatefulWidget {
  final PairedPc paired;
  final Future<void> Function() onUnpair;
  final ValueChanged<int> onNavigate;
  const SettingsScreen({
    super.key,
    required this.paired,
    required this.onUnpair,
    required this.onNavigate,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  AppSettings _s = const AppSettings();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-read on resume: the notification "Desactivar" action may have flipped
    // Always-on detection off while we were in the background / shade.
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final s = await SettingsService.load();
    if (mounted) setState(() => _s = s);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 14),
            child: Text(L10n.t('nav_settings'),
                style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: MP.textPrimary,
                    letterSpacing: -0.5)),
          ),

          // Connection
          SectionLabel(L10n.t('connection')),
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                if (widget.paired.name?.isNotEmpty == true) ...[
                  _SRow(label: 'PC', value: widget.paired.name!),
                  const GlassDivider(),
                ],
                _SRow(label: L10n.t('pc_address'), value: widget.paired.host, trailing: _chevron()),
                const GlassDivider(),
                _SRow(label: L10n.t('port_label'), value: '${widget.paired.port}'),
                const GlassDivider(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  child: SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () async {
                        await widget.onUnpair();
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        backgroundColor: const Color(0x247C3AED),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0x4D7C3AED)),
                        ),
                      ),
                      child: Text(L10n.t('change_connection'),
                          style: const TextStyle(
                              color: MP.violetLight, fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Behavior
          SectionLabel(L10n.t('behavior')),
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                _SRow(
                  label: L10n.t('image_quality'),
                  trailing: _QualitySegmented(
                    value: _s.quality,
                    onChanged: (q) async {
                      setState(() => _s = _s.copyWith(quality: q));
                      await SettingsService.setQuality(q);
                    },
                  ),
                ),
                const GlassDivider(),
                _SRow(
                  label: L10n.t('confirmation_sound'),
                  trailing: _Toggle(
                    on: _s.confirmationSound,
                    onChanged: (v) async {
                      setState(() => _s = _s.copyWith(confirmationSound: v));
                      await SettingsService.setSound(v);
                    },
                  ),
                ),
                const GlassDivider(),
                _SRow(
                  label: L10n.t('autostart_on_boot'),
                  trailing: _Toggle(
                    on: _s.autoStartOnBoot,
                    onChanged: (v) async {
                      setState(() => _s = _s.copyWith(autoStartOnBoot: v));
                      await SettingsService.setBoot(v);
                    },
                  ),
                ),
                const GlassDivider(),
                _ToggleRowWithHint(
                  label: L10n.t('always_on'),
                  hint: L10n.t('always_on_hint'),
                  on: _s.guaranteedBg,
                  onChanged: (v) async {
                    setState(() => _s = _s.copyWith(guaranteedBg: v));
                    await SettingsService.setGuaranteed(v);
                    await NativeSync.setGuaranteed(v);
                    // On Xiaomi the service still needs Autostart + battery
                    // settings — nudge the user through them right away.
                    final needsHelp = v && await BackgroundHelp.isXiaomi();
                    if (!mounted) return;
                    if (needsHelp) showBackgroundHelp(context);
                  },
                ),
                const GlassDivider(),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => showBackgroundHelp(context),
                  child: _SRow(
                    label: L10n.t('bg_setup_help'),
                    trailing: _chevron(),
                  ),
                ),
                const GlassDivider(),
                _SRow(
                  label: L10n.t('language'),
                  trailing: _LangSegmented(
                    value: L10n.mode.value,
                    onChanged: (m) async {
                      await L10n.setMode(m);
                      if (mounted) setState(() {});
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // About
          SectionLabel(L10n.t('about')),
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                _SRow(label: L10n.t('version'), value: '0.1.0 Beta'),
                const GlassDivider(),
                _SRow(
                  label: 'GitHub',
                  trailing: GestureDetector(
                    onTap: () => launchUrl(
                      Uri.parse('https://github.com/RedOrionStudio/magicpaste'),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('RedOrionStudio',
                            style: TextStyle(fontSize: 13, color: MP.violetLight)),
                        SizedBox(width: 5),
                        Icon(Icons.open_in_new, size: 13, color: MP.violetLight),
                      ],
                    ),
                  ),
                ),
                const GlassDivider(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0x2E7C3AED),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0x527C3AED)),
                        ),
                        child: const Text('GPL v3',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: MP.violetLight,
                                letterSpacing: 0.6)),
                      ),
                      const SizedBox(width: 10),
                      Text(L10n.t('open_source_free'),
                          style: const TextStyle(fontSize: 12, color: MP.textMuted)),
                    ],
                  ),
                ),
                const GlassDivider(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  child: GestureDetector(
                    onTap: () => launchUrl(
                      Uri.parse('https://www.redorionstudio.com'),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                            text: L10n.t('made_with'),
                            style: const TextStyle(fontSize: 12, color: MP.textMuted)),
                        const TextSpan(
                            text: '❤',
                            style: TextStyle(fontSize: 12, color: Color(0xFFFF3B2E))),
                        TextSpan(
                            text: L10n.t('by'),
                            style: const TextStyle(fontSize: 12, color: MP.textMuted)),
                        TextSpan(
                            text: 'Red ',
                            style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFFEEF2FA),
                                fontWeight: FontWeight.w600)),
                        TextSpan(
                            text: 'Orion',
                            style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFFFF3B2E),
                                fontWeight: FontWeight.w700)),
                        TextSpan(
                            text: ' Studio',
                            style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFFEEF2FA),
                                fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                ),
                const GlassDivider(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => launchUrl(
                      Uri.parse('https://ko-fi.com/redorionstudio'),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('☕  ', style: TextStyle(fontSize: 13)),
                          Text(L10n.t('support_kofi'),
                              style: const TextStyle(fontSize: 13, color: MP.violetLight)),
                          const SizedBox(width: 5),
                          const Icon(Icons.open_in_new, size: 13, color: MP.violetLight),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chevron() =>
      const Icon(Icons.chevron_right, size: 18, color: Color(0x47FFFFFF));
}

class _SRow extends StatelessWidget {
  final String label;
  final String? value;
  final Widget? trailing;
  const _SRow({required this.label, this.value, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14, color: MP.textPrimary)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (value != null)
                Text(value!, style: const TextStyle(fontSize: 13, color: MP.textSec)),
              if (value != null && trailing != null) const SizedBox(width: 7),
              if (trailing != null) trailing!,
            ],
          ),
        ],
      ),
    );
  }
}

class _ToggleRowWithHint extends StatelessWidget {
  final String label;
  final String hint;
  final bool on;
  final ValueChanged<bool> onChanged;
  const _ToggleRowWithHint({
    required this.label,
    required this.hint,
    required this.on,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(fontSize: 14, color: MP.textPrimary)),
              ),
              const SizedBox(width: 10),
              _Toggle(on: on, onChanged: onChanged),
            ],
          ),
          const SizedBox(height: 5),
          Text(hint,
              style: const TextStyle(fontSize: 11.5, color: MP.textMuted, height: 1.45)),
        ],
      ),
    );
  }
}

class _QualitySegmented extends StatelessWidget {
  final ImageQuality value;
  final ValueChanged<ImageQuality> onChanged;
  const _QualitySegmented({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final opts = [
      (ImageQuality.low, L10n.t('q_low')),
      (ImageQuality.medium, L10n.t('q_med')),
      (ImageQuality.high, L10n.t('q_high')),
    ];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: MP.glass,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: opts.map((o) {
          final sel = o.$1 == value;
          return GestureDetector(
            onTap: () => onChanged(o.$1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: sel ? const Color(0x8C7C3AED) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(o.$2,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: sel ? Colors.white : MP.textSec)),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _LangSegmented extends StatelessWidget {
  final String value; // 'system' | 'en' | 'es'
  final ValueChanged<String> onChanged;
  const _LangSegmented({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final opts = [
      ('system', L10n.t('lang_system')),
      ('en', 'EN'),
      ('es', 'ES'),
    ];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: MP.glass, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: opts.map((o) {
          final sel = o.$1 == value;
          return GestureDetector(
            onTap: () => onChanged(o.$1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: sel ? const Color(0x8C7C3AED) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(o.$2,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: sel ? Colors.white : MP.textSec)),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  final bool on;
  final ValueChanged<bool> onChanged;
  const _Toggle({required this.on, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!on),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 42,
        height: 24,
        decoration: BoxDecoration(
          color: on ? MP.violet : const Color(0x24FFFFFF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 180),
          alignment: on ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.all(3),
            width: 18,
            height: 18,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Color(0x59000000), blurRadius: 4, offset: Offset(0, 1))],
            ),
          ),
        ),
      ),
    );
  }
}
