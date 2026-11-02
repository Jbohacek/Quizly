import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';

/// Bottom navigation: Domů / Statistiky / Obchod / Nastavení. Obchod is left out for a user
/// the admin keeps out of the shop.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  /// Label, icon and the shell branch it opens.
  static const _items = [
    (S.navHome, Icons.home_rounded, 0),
    (S.navStats, Icons.bar_chart_rounded, 1),
    (S.navShop, Icons.card_giftcard_rounded, shopBranch),
    (S.navSettings, Icons.tune_rounded, 3),
  ];

  static const shopBranch = 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shop = ref.watch(shopEnabledProvider);
    final items = [for (final item in _items) if (shop || item.$3 != shopBranch) item];
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
                  for (final (label, icon, branch) in items)
                    Expanded(
                      child: _NavItem(
                        label: label,
                        icon: icon,
                        selected: shell.currentIndex == branch,
                        onTap: () => shell.goBranch(branch, initialLocation: branch == shell.currentIndex),
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
