import 'package:flutter/material.dart';

import '../services/pairing_service.dart';
import 'bottom_nav.dart';
import 'history_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';
import 'theme.dart';

/// Hosts the three main tabs (Home / History / Settings) behind the bottom nav.
class MainShell extends StatefulWidget {
  final PairedPc paired;
  final Future<void> Function() onUnpair;
  const MainShell({super.key, required this.paired, required this.onUnpair});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;

  void _go(int i) => setState(() => _tab = i);

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(paired: widget.paired, onNavigate: _go),
      HistoryScreen(onNavigate: _go),
      SettingsScreen(paired: widget.paired, onUnpair: widget.onUnpair, onNavigate: _go),
    ];

    return Scaffold(
      backgroundColor: MP.base,
      body: MpBackground(
        child: SafeArea(
          bottom: false,
          child: IndexedStack(index: _tab, children: pages),
        ),
      ),
      bottomNavigationBar: MpBottomNav(active: _tab, onTap: _go),
    );
  }
}
