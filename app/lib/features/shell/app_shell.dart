import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/strings.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';

/// Bottom navigation: Domů / Statistiky / Obchod / Nastavení.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const _items = [
    (S.navHome, Icons.home_rounded),
    (S.navStats, Icons.bar_chart_rounded),
    (S.navShop, Icons.card_giftcard_rounded),
    (S.navSettings, Icons.tune_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(color: Q.nav, border: Border(top: BorderSide(color: Q.border))),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 76,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  for (final (i, item) in _items.indexed)
                    Expanded(
                      child: _NavItem(
                        label: item.$1,
                        icon: item.$2,
                        selected: shell.currentIndex == i,
                        onTap: () => shell.goBranch(i, initialLocation: i == shell.currentIndex),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.label, required this.icon, required this.selected, required this.onTap});

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Q.primary : Q.textMuted;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 40,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 4),
            Text(label, style: QText.body(12, color: color, weight: selected ? FontWeight.w800 : FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
