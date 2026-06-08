import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/l10n.dart';
import 'theme.dart';

/// Android bottom navigation bar — Home / History / Settings.
class MpBottomNav extends StatelessWidget {
  final int active; // 0 home, 1 history, 2 settings
  final ValueChanged<int> onTap;
  const MpBottomNav({super.key, required this.active, required this.onTap});

  static const _items = [
    (icon: Icons.home_outlined, activeIcon: Icons.home, key: 'nav_home'),
    (icon: Icons.history, activeIcon: Icons.history, key: 'nav_history'),
    (icon: Icons.settings_outlined, activeIcon: Icons.settings, key: 'nav_settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xF70B0B0E),
            border: Border(top: BorderSide(color: Color(0x14FFFFFF))),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: List.generate(_items.length, (i) {
                final a = i == active;
                final item = _items[i];
                return Expanded(
                  child: InkWell(
                    onTap: () => onTap(i),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 9),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              if (a)
                                Container(
                                  width: 50,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: const Color(0x2E7C3AED),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              Icon(
                                a ? item.activeIcon : item.icon,
                                size: 22,
                                color: a ? MP.violetLight : const Color(0x61FFFFFF),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            L10n.t(item.key),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: a ? FontWeight.w600 : FontWeight.w400,
                              color: a ? MP.violetLight : const Color(0x6BFFFFFF),
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
