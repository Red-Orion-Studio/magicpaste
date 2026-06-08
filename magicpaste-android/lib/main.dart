import 'package:flutter/material.dart';

import 'services/l10n.dart';
import 'services/pairing_service.dart';
import 'ui/main_shell.dart';
import 'ui/pairing_screen.dart';
import 'ui/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await L10n.init();
  runApp(const MagicPasteApp());
}

class MagicPasteApp extends StatelessWidget {
  const MagicPasteApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuild the whole app when the language changes.
    return ValueListenableBuilder<String>(
      valueListenable: L10n.mode,
      builder: (context, _, __) => MaterialApp(
        title: 'MagicPaste',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: MP.violet,
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: MP.base,
          fontFamily: 'Roboto',
          useMaterial3: true,
        ),
        home: const _Root(),
      ),
    );
  }
}

class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  PairedPc? _paired;
  bool _loading = true;
  // True while the user is changing connection: we show the pairing screen but
  // keep the current pairing so they can cancel and go back to it.
  bool _repairing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final paired = await PairingService.getPaired();
    setState(() {
      _paired = paired;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: MP.base,
        body: Center(child: CircularProgressIndicator(color: MP.violetLight)),
      );
    }
    if (_paired == null || _repairing) {
      return PairingScreen(
        onPaired: (pc) => setState(() {
          _paired = pc;
          _repairing = false;
        }),
        // Offer a way back only when there's an existing connection to return to.
        onCancel: _paired != null ? () => setState(() => _repairing = false) : null,
      );
    }
    return MainShell(
      paired: _paired!,
      // "Change connection" no longer wipes the pairing up front — it just
      // opens the pairing screen; the old connection stays until a new pair
      // succeeds, and the user can back out.
      onUnpair: () async => setState(() => _repairing = true),
    );
  }
}
