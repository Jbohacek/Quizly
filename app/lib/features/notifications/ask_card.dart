import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';

/// "Mám ti připomínat učení? 🔔" on Domů, once per device, before the system dialog
/// (docs/notifications.md §1).
class NotificationAskCard extends ConsumerStatefulWidget {
  const NotificationAskCard({super.key});

  @override
  ConsumerState<NotificationAskCard> createState() => _NotificationAskCardState();
}

class _NotificationAskCardState extends ConsumerState<NotificationAskCard> {
  bool _busy = false;

  Future<void> _answer({required bool allow}) async {
    setState(() => _busy = true);
    await ref.read(notificationsProvider).answerAsk(allow: allow);
    if (!mounted) return;
    ref
      ..invalidate(notificationAskProvider)
      ..invalidate(notificationPermissionProvider);
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(notificationAskProvider).value != true) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Panel(
        radius: 22,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: Q.primary.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.notifications_none_rounded, color: Q.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(S.askTitle, style: QText.body(15, weight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(S.askText, style: QText.body(13, color: Q.textMuted, weight: FontWeight.w400, height: 1.4)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _busy ? null : () => _answer(allow: false),
                  style: TextButton.styleFrom(
                    foregroundColor: Q.textMuted,
                    minimumSize: const Size(64, 44),
                    textStyle: QText.body(14, weight: FontWeight.w800),
                  ),
                  child: const Text(S.notNow),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : () => _answer(allow: true),
                  style: FilledButton.styleFrom(
                    backgroundColor: Q.primary,
                    foregroundColor: Q.onPrimary,
                    minimumSize: const Size(96, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    textStyle: QText.body(14, weight: FontWeight.w800),
                  ),
                  child: const Text(S.allow),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
