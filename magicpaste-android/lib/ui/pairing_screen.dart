import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/l10n.dart';
import '../services/native_sync.dart';
import '../services/network_service.dart';
import '../services/pairing_service.dart';
import 'theme.dart';

/// First-time setup. Step 1 = QR scan, Step 2 = manual IP entry, with a
/// green auto-discovery banner when a PC is found on the network.
class PairingScreen extends StatefulWidget {
  final void Function(PairedPc) onPaired;
  /// When set, the screen is a re-pair over an existing connection: show a way
  /// back that keeps the current PC instead of forcing a new pairing.
  final VoidCallback? onCancel;
  const PairingScreen({super.key, required this.onPaired, this.onCancel});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  int _step = 1;
  bool _busy = false;
  String? _error;
  final _ipController = TextEditingController();
  List<PairedPc> _discovered = [];

  @override
  void initState() {
    super.initState();
    _runDiscovery();
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _runDiscovery() async {
    final found = await PairingService.discover();
    // No auto-fill: with several PCs on the WiFi we can't know which one the
    // user wants. Manual entry stays fully manual (advanced fallback).
    if (mounted) setState(() => _discovered = found);
  }

  Future<void> _connect(String host, int port, [String? token]) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final myName = await NativeSync.deviceName();
    final res = await NetworkService.pair(
        host: host, port: port, deviceName: myName, token: token);
    if (!mounted) return;
    switch (res.status) {
      case PairStatus.ok:
        final tok =
            (res.token != null && res.token!.isNotEmpty) ? res.token : token;
        await PairingService.savePaired(host, port, tok, res.pcName);
        widget.onPaired(PairedPc(host, port, tok, res.pcName));
        break;
      case PairStatus.refused:
        setState(() {
          _busy = false;
          _error = L10n.t('err_refused');
        });
        break;
      case PairStatus.failed:
        setState(() {
          _busy = false;
          _error = L10n.t('err_unreachable');
        });
        break;
    }
  }

  void _connectFromField() {
    final (host, port, token) = PairingService.parseAddress(_ipController.text);
    if (host.isEmpty) {
      setState(() => _error = L10n.t('err_enter_ip'));
      return;
    }
    _connect(host, port, token);
  }

  Future<void> _scanQr() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _QrScannerScreen()),
    );
    if (result != null && mounted) {
      final (host, port, token) = PairingService.parseAddress(result);
      _connect(host, port, token);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // When re-pairing over an existing connection, intercept the system back
      // button so it returns to the current connection instead of leaving.
      canPop: widget.onCancel == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onCancel?.call();
      },
      child: Scaffold(
        backgroundColor: MP.base,
        body: MpBackground(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _stepHeader(),
                const SizedBox(height: 13),
                if (_discovered.isNotEmpty) ...[
                  _discoveryBanner(_discovered.first),
                  const SizedBox(height: 13),
                ],
                if (_error != null) ...[
                  _errorBanner(_error!),
                  const SizedBox(height: 13),
                ],
                Expanded(
                  child: SingleChildScrollView(
                    child: _step == 1 ? _stepQr() : _stepManual(),
                  ),
                ),
                if (_busy) const LinearProgressIndicator(minHeight: 2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (_step == 2)
          TextButton.icon(
            onPressed: () => setState(() => _step = 1),
            style: TextButton.styleFrom(foregroundColor: MP.textSec, padding: EdgeInsets.zero),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: Text(L10n.t('back'), style: const TextStyle(fontSize: 14)),
          )
        else if (widget.onCancel != null)
          TextButton.icon(
            onPressed: widget.onCancel,
            style: TextButton.styleFrom(foregroundColor: MP.textSec, padding: EdgeInsets.zero),
            icon: const Icon(Icons.close, size: 18),
            label: Text(L10n.t('keep_current_pc'), style: const TextStyle(fontSize: 14)),
          )
        else
          const SizedBox(height: 30),
        Row(
          children: [
            for (var i = 1; i <= 2; i++) ...[
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 6,
                width: i == _step ? 22 : 7,
                margin: const EdgeInsets.only(right: 5),
                decoration: BoxDecoration(
                  color: i == _step ? MP.violet : const Color(0x38FFFFFF),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ],
            Text(L10n.t('step_of', {'n': '$_step'}),
                style: const TextStyle(fontSize: 12, color: MP.textMuted)),
          ],
        ),
      ],
    );
  }

  Widget _discoveryBanner(PairedPc pc) {
    return GestureDetector(
      onTap: _busy ? null : () => _connect(pc.host, pc.port),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0x1722C55E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x4022C55E)),
        ),
        child: Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: MP.green,
                boxShadow: [BoxShadow(color: MP.green, blurRadius: 8)],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(L10n.t('pc_found'),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600, color: MP.green)),
                  Text('${pc.host} · ${pc.port}',
                      style: const TextStyle(fontSize: 11, color: MP.textSec)),
                ],
              ),
            ),
            Text(L10n.t('connect_arrow'),
                style: const TextStyle(fontSize: 13, color: MP.violetLight, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _errorBanner(String msg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0x17F87171),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x40F87171)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 18, color: MP.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(msg,
                style: const TextStyle(fontSize: 12.5, color: MP.textSec, height: 1.45)),
          ),
        ],
      ),
    );
  }

  Widget _stepQr() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        Center(
          child: Column(
            children: [
              Text(L10n.t('scan_to_connect'),
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w700, color: MP.textPrimary, letterSpacing: -0.5)),
              const SizedBox(height: 6),
              Text(L10n.t('scan_from_pc'),
                  style: const TextStyle(fontSize: 13, color: MP.textSec)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        GlassCard(
          glow: GlassGlow.violet,
          padding: const EdgeInsets.all(22),
          child: Column(
            children: [
              GestureDetector(
                onTap: _busy ? null : _scanQr,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: QrImageView(
                    data: 'Scan the QR shown by MagicPaste on your PC',
                    size: 188,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                L10n.t('tap_code_open'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: MP.textMuted, height: 1.55),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _orDivider(),
        const SizedBox(height: 16),
        _ghostButton(L10n.t('enter_ip_manually'), () => setState(() => _step = 2)),
      ],
    );
  }

  Widget _stepManual() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        Text(L10n.t('enter_pc_address'),
            style: const TextStyle(
                fontSize: 24, fontWeight: FontWeight.w700, color: MP.textPrimary, letterSpacing: -0.5)),
        const SizedBox(height: 6),
        Text(L10n.t('type_local_ip'),
            style: const TextStyle(fontSize: 13, color: MP.textSec)),
        const SizedBox(height: 14),
        GlassCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(L10n.t('ip_address_label'),
                  style: const TextStyle(
                      fontSize: 11, color: MP.textMuted, letterSpacing: 0.8)),
              const SizedBox(height: 8),
              TextField(
                controller: _ipController,
                keyboardType: TextInputType.url,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.:]')),
                ],
                style: const TextStyle(
                    fontSize: 18, color: MP.textPrimary, fontFamily: 'monospace', letterSpacing: 1.2),
                cursorColor: MP.violetLight,
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: '192.168.1.105',
                  hintStyle: TextStyle(color: Color(0x40FFFFFF), fontFamily: 'monospace'),
                  prefixIcon: Icon(Icons.language, size: 18, color: Color(0x47FFFFFF)),
                  prefixIconConstraints: BoxConstraints(minWidth: 28),
                ),
                onSubmitted: (_) => _connectFromField(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(colors: [MP.violet, Color(0xFF5B21B6)]),
            boxShadow: const [BoxShadow(color: Color(0x667C3AED), blurRadius: 28, offset: Offset(0, 8))],
          ),
          child: TextButton(
            onPressed: _busy ? null : _connectFromField,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 15),
              foregroundColor: Colors.white,
            ),
            child: Text(L10n.t('connect'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
          ),
        ),
        const SizedBox(height: 14),
        GlassCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 18,
                height: 18,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0x33A78BFA),
                  border: Border.all(color: const Color(0x59A78BFA)),
                ),
                child: const Center(
                  child: Text('i',
                      style: TextStyle(fontSize: 10, color: MP.violetLight, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  L10n.t('where_find_ip'),
                  style: const TextStyle(fontSize: 12, color: MP.textMuted, height: 1.6),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _orDivider(),
        const SizedBox(height: 16),
        _ghostButton(L10n.t('scan_qr_instead'), () => setState(() => _step = 1)),
      ],
    );
  }

  Widget _orDivider() {
    return Row(
      children: [
        const Expanded(child: ColoredBox(color: Color(0x17FFFFFF), child: SizedBox(height: 1))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(L10n.t('or'), style: const TextStyle(fontSize: 12, color: MP.textMuted)),
        ),
        const Expanded(child: ColoredBox(color: Color(0x17FFFFFF), child: SizedBox(height: 1))),
      ],
    );
  }

  Widget _ghostButton(String label, VoidCallback onTap) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: MP.glass,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MP.glassBorder),
      ),
      child: TextButton(
        onPressed: _busy ? null : onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          foregroundColor: MP.textSec,
        ),
        child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      ),
    );
  }
}

class _QrScannerScreen extends StatefulWidget {
  const _QrScannerScreen();

  @override
  State<_QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<_QrScannerScreen> {
  // Explicit controller (mobile_scanner v7): the widget auto-starts it and
  // handles the app-lifecycle pause/resume; we just dispose it. Restricting to
  // QR + noDuplicates keeps the decoder light and avoids double-pops.
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final value = capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
    if (value == null || value.isEmpty) return;
    _handled = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MP.base,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(L10n.t('scan_pc_qr_title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on, color: Colors.white),
            tooltip: L10n.t('torch'),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: MobileScanner(
        controller: _controller,
        onDetect: _onDetect,
        // Show a spinner while the camera warms up instead of a black frame.
        placeholderBuilder: (context) => const ColoredBox(
          color: Colors.black,
          child: Center(child: CircularProgressIndicator(color: MP.violetLight)),
        ),
        // If the camera can't open (a known issue on some MIUI builds), tell
        // the user instead of leaving a silent black screen — they can still
        // pair via network discovery / manual IP.
        errorBuilder: (context, error) => Container(
          color: Colors.black,
          padding: const EdgeInsets.all(28),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined, color: MP.textMuted, size: 44),
              const SizedBox(height: 14),
              Text(
                L10n.t('camera_failed', {'code': error.errorCode.name}),
                textAlign: TextAlign.center,
                style: const TextStyle(color: MP.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                L10n.t('camera_failed_hint'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: MP.textSec, fontSize: 13, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
