import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/l10n.dart';
import '../services/native_sync.dart';
import '../services/network_service.dart';
import '../services/pairing_service.dart';
import '../services/protocol.dart';
import '../services/screenshot_monitor.dart';
import '../services/sent_history.dart';
import '../services/settings_service.dart';
import 'theme.dart';

class HomeScreen extends StatefulWidget {
  final PairedPc paired;
  final ValueChanged<int> onNavigate;
  const HomeScreen({super.key, required this.paired, required this.onNavigate});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _kAutoEnabled = 'mp_auto_enabled';

  bool _autoEnabled = false;
  bool _online = false;
  bool _busy = false;
  List<SentItem> _recent = [];
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAutoState();
    _refresh();
    _rearmIfEnabled();
    // While visible: re-ping + reload recent so background auto-sends show up.
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkOnline();
      _loadRecent();
    });
  }

  /// MIUI / EMUI silently drop JobScheduler entries for "rarely used" apps
  /// between worker runs — the toggle keeps reading TRUE but the URI trigger
  /// no longer exists. Re-arm every time the user opens the app; native call
  /// is idempotent (ExistingWorkPolicy.REPLACE).
  Future<void> _rearmIfEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kAutoEnabled) ?? false) {
      await NativeSync.enable();
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
      // Re-arm the URI trigger if MIUI killed it while the app was
      // backgrounded — cheap idempotent call, no-op if already armed.
      _rearmIfEnabled();
    }
  }

  Future<void> _refresh() async {
    await _checkOnline();
    await _loadRecent();
  }

  Future<void> _loadAutoState() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _autoEnabled = prefs.getBool(_kAutoEnabled) ?? false);
    }
  }

  String _recentSig = '';

  Future<void> _loadRecent() async {
    final items = await SentHistory.load();
    if (!mounted) return;
    final next = items.take(8).toList();
    // Skip the rebuild when nothing changed, to avoid thumbnail flicker.
    final sig = next.map((e) => '${e.timestampMs}:${e.ok}').join(',');
    if (sig == _recentSig) return;
    setState(() {
      _recent = next;
      _recentSig = sig;
    });
  }

  Future<void> _checkOnline() async {
    final ok = await NetworkService.ping(
      host: widget.paired.host,
      port: widget.paired.port,
      token: widget.paired.token,
    );
    if (mounted) setState(() => _online = ok);
  }

  Future<void> _toggleAuto() async {
    final prefs = await SharedPreferences.getInstance();
    if (_autoEnabled) {
      await NativeSync.disable();
      await prefs.setBool(_kAutoEnabled, false);
      if (mounted) setState(() => _autoEnabled = false);
      return;
    }

    final granted = await ScreenshotMonitor.requestImagePermission();
    if (!granted) {
      _snack('Photo permission required');
      return;
    }
    await Permission.notification.request();
    if (!await Permission.ignoreBatteryOptimizations.isGranted) {
      await Permission.ignoreBatteryOptimizations.request();
    }
    await prefs.setInt('mp_last_sent_ms', DateTime.now().millisecondsSinceEpoch);
    await NativeSync.enable();
    await prefs.setBool(_kAutoEnabled, true);
    if (mounted) setState(() => _autoEnabled = true);
    _snack(L10n.t('snack_autosend_on'), seconds: 6);
  }

  void _snack(String msg, {int seconds = 4}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: Duration(seconds: seconds)),
    );
  }

  /// Manual send: newest screenshot → PC, and log to history.
  Future<void> _sendLatest() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final granted = await ScreenshotMonitor.requestImagePermission();
      if (!granted) {
        _snack(L10n.t('snack_photo_perm'));
        return;
      }
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        filterOption: FilterOptionGroup(
          orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
        ),
      );
      AssetEntity? latest;
      for (final album in albums) {
        final n = album.name.toLowerCase();
        if (n.contains('screenshot') || n.contains('captura')) {
          final a = await album.getAssetListPaged(page: 0, size: 1);
          if (a.isNotEmpty) {
            latest = a.first;
            break;
          }
        }
      }
      if (latest == null && albums.isNotEmpty) {
        final a = await albums.first.getAssetListPaged(page: 0, size: 1);
        if (a.isNotEmpty) latest = a.first;
      }
      if (latest == null) {
        _snack(L10n.t('snack_no_ss'));
        return;
      }
      final bytes = await latest.originBytes;
      if (bytes == null) return;
      final title = (await latest.titleAsync).toLowerCase();
      // Apply the quality setting on the sender side (mirrors the native worker).
      final settings = await SettingsService.load();
      final quality = settings.quality;
      Uint8List sendBytes = bytes;
      int fmt = title.endsWith('.png') ? Protocol.imgPng : Protocol.imgJpeg;
      int w = latest.width, h = latest.height;
      if (quality != ImageQuality.high) {
        final low = quality == ImageQuality.low;
        int tw = latest.width, th = latest.height;
        if (low) {
          final longest = w > h ? w : h;
          if (longest > 1280) {
            final s = 1280 / longest;
            tw = (w * s).round();
            th = (h * s).round();
          }
        }
        final data = await latest.thumbnailDataWithSize(
          ThumbnailSize(tw, th),
          quality: low ? 70 : 85,
        );
        if (data != null) {
          sendBytes = data;
          fmt = Protocol.imgJpeg;
          w = tw;
          h = th;
        }
      }
      final thumb = await latest.thumbnailDataWithSize(const ThumbnailSize(160, 240));
      final ok = await NetworkService.sendImage(
        host: widget.paired.host,
        port: widget.paired.port,
        imageBytes: sendBytes,
        imageFormat: fmt,
        width: w,
        height: h,
        token: widget.paired.token,
      );
      await SentHistory.add(SentItem(
        name: title,
        width: latest.width,
        height: latest.height,
        ok: ok,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        thumbB64: thumb != null ? base64Encode(thumb) : null,
      ));
      if (mounted) setState(() => _online = ok);
      await _loadRecent();
      if (ok && settings.confirmationSound) NativeSync.beep();
      _snack(L10n.t(ok ? 'snack_sent_ok' : 'snack_sent_fail'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Simple top-aligned scroll: fixed margins between sections, content sits
    // at the top, and any extra space just stays at the bottom. When content
    // overflows the viewport it scrolls — margins are never compressed.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          const SizedBox(height: 22),
          _statusCard(),
          const SizedBox(height: 28),
          _recentlySent(),
          const SizedBox(height: 28),
          _fab(),
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        const AppLogo(size: 40),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('MagicPaste',
                  style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      color: MP.textPrimary,
                      letterSpacing: -0.5)),
              Text(L10n.t('tagline'),
                  style: const TextStyle(fontSize: 11, color: Color(0xA6A78BFA), letterSpacing: 0.4)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statusCard() {
    final connected = _online;
    return GlassCard(
      glow: connected ? GlassGlow.green : GlassGlow.red,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 11,
                height: 11,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: connected ? MP.green : MP.red,
                  boxShadow: [
                    BoxShadow(color: connected ? MP.green : MP.red, blurRadius: 10),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            connected
                                ? (widget.paired.name?.isNotEmpty == true
                                    ? widget.paired.name!
                                    : widget.paired.host)
                                : L10n.t('searching_pc'),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700, color: MP.textPrimary),
                          ),
                        ),
                        if (connected)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0x2422C55E),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(L10n.t('connected'),
                                style: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w700, color: MP.green)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      L10n.t(connected ? 'ready_take_ss' : 'make_sure_pc'),
                      style: const TextStyle(fontSize: 13, color: MP.textSec, height: 1.45),
                    ),
                    if (connected) ...[
                      const SizedBox(height: 6),
                      Text(
                          L10n.t('port_host', {
                            'p': '${widget.paired.port}',
                            'h': widget.paired.host,
                          }),
                          style: const TextStyle(fontSize: 11, color: MP.textMuted)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (!connected) ...[
            const SizedBox(height: 13),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: _checkOnline,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  backgroundColor: const Color(0x2E7C3AED),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                    side: const BorderSide(color: Color(0x597C3AED)),
                  ),
                ),
                child: Text(L10n.t('retry_connection'),
                    style: const TextStyle(
                        color: MP.violetLight, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _recentlySent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(L10n.t('recently_sent'),
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: MP.textMuted,
                    letterSpacing: 1)),
            Text(L10n.t('items', {'n': '${_recent.length}'}),
                style: const TextStyle(fontSize: 12, color: Color(0xA6A78BFA))),
          ],
        ),
        const SizedBox(height: 10),
        if (_recent.isEmpty)
          const _EmptyRecent()
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.68, // thumbnail (taller than wide)
            ),
            itemCount: _recent.length > 8 ? 8 : _recent.length,
            itemBuilder: (_, i) => _ThumbCard(item: _recent[i]),
          ),
      ],
    );
  }

  Widget _fab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Auto-send switch card — clear ON/OFF state.
        GlassCard(
          glow: _autoEnabled ? GlassGlow.violet : GlassGlow.none,
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: _autoEnabled
                      ? const LinearGradient(colors: [MP.violet, Color(0xFF5B21B6)])
                      : null,
                  color: _autoEnabled ? null : MP.glass,
                  border: Border.all(
                      color: _autoEnabled ? const Color(0x47A78BFA) : MP.glassBorder),
                ),
                child: Icon(Icons.auto_awesome,
                    size: 20, color: _autoEnabled ? Colors.white : MP.textMuted),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(L10n.t('automatic_sending'),
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700, color: MP.textPrimary)),
                    const SizedBox(height: 2),
                    Text(
                      L10n.t(_autoEnabled ? 'autosend_on' : 'autosend_off'),
                      style: const TextStyle(fontSize: 12, color: MP.textSec, height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _Switch(on: _autoEnabled, onChanged: (_) => _toggleAuto()),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Discreet manual re-send.
        Center(
          child: TextButton.icon(
            onPressed: _busy ? null : _sendLatest,
            style: TextButton.styleFrom(foregroundColor: MP.textSec),
            icon: _busy
                ? const SizedBox(
                    width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send_rounded, size: 15),
            label: Text(L10n.t('send_latest'),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ),
      ],
    );
  }
}

/// Pill switch matching the design's violet toggle.
class _Switch extends StatelessWidget {
  final bool on;
  final ValueChanged<bool> onChanged;
  const _Switch({required this.on, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!on),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 50,
        height: 28,
        decoration: BoxDecoration(
          gradient: on ? const LinearGradient(colors: [MP.violet, Color(0xFF5B21B6)]) : null,
          color: on ? null : const Color(0x24FFFFFF),
          borderRadius: BorderRadius.circular(14),
          boxShadow:
              on ? const [BoxShadow(color: Color(0x667C3AED), blurRadius: 12)] : null,
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 180),
          alignment: on ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.all(3),
            width: 22,
            height: 22,
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

class _EmptyRecent extends StatelessWidget {
  const _EmptyRecent();
  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 26),
      child: Center(
        child: Text(L10n.t('no_ss_yet'),
            style: const TextStyle(fontSize: 13, color: MP.textMuted)),
      ),
    );
  }
}

class _ThumbCard extends StatelessWidget {
  final SentItem item;
  const _ThumbCard({required this.item});

  String _fmt(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ap';
  }

  @override
  Widget build(BuildContext context) {
    Uint8List? thumb;
    if (item.thumbB64 != null) {
      try {
        thumb = base64Decode(item.thumbB64!);
      } catch (_) {}
    }
    return ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              color: const Color(0xFF2A2730),
              child: thumb != null
                  ? Image.memory(thumb, fit: BoxFit.cover, gaplessPlayback: true)
                  : const Icon(Icons.image_outlined, color: MP.textMuted),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(6, 18, 6, 5),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xC7000000)],
                  ),
                ),
                child: Text(_fmt(item.time),
                    style: const TextStyle(
                        fontSize: 9, color: Color(0xE0FFFFFF), fontWeight: FontWeight.w500)),
              ),
            ),
            Positioned(
              top: 5,
              right: 5,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: item.ok ? MP.green : MP.red,
                ),
                child: Icon(item.ok ? Icons.check : Icons.close, size: 10, color: Colors.white),
              ),
            ),
          ],
        ),
      );
  }
}
