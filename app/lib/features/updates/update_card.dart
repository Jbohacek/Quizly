import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import 'app_update.dart';

/// "Je dostupná nová verze" on Domů: downloads the APK in the app, then opens Android's install screen.
class UpdateCard extends ConsumerStatefulWidget {
  const UpdateCard({super.key});

  @override
  ConsumerState<UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends ConsumerState<UpdateCard> {
  /// 0–1 while downloading, null otherwise.
  double? _progress;
  String? _error;
  CancelToken? _cancel;

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  Future<void> _update(AppLatest latest) async {
    final installer = ref.read(appInstallerProvider);
    final cancel = _cancel = CancelToken();
    setState(() {
      _progress = 0;
      _error = null;
    });
    String path;
    try {
      path = await installer.downloadPath();
      await ref.read(apiClientProvider).downloadApp(
            path,
            cancel: cancel,
            onProgress: (received, total) {
              final size = total > 0 ? total : latest.size;
              if (mounted && size > 0) setState(() => _progress = (received / size).clamp(0, 1));
            },
          );
    } on Object {
      if (mounted && !cancel.isCancelled) {
        setState(() {
          _progress = null;
          _error = S.updateFailed;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _progress = null);
    try {
      await installer.install(path);
    } on Object {
      if (mounted) setState(() => _error = S.updateInstallFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final latest = ref.watch(availableUpdateProvider).value;
    if (latest == null) return const SizedBox.shrink();
    final progress = _progress;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Panel(
        radius: 22,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: Q.primary.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.system_update_rounded, color: Q.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(S.updateTitle, style: QText.body(15, weight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(
                        S.updateText(latest.versionName, formatMegabytes(latest.size)),
                        style: QText.body(13, color: Q.textMuted, weight: FontWeight.w400, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (progress != null) ...[
              const SizedBox(height: 14),
              Semantics(
                label: S.updateDownloading(formatPercent((progress * 100).round())),
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(value: progress, minHeight: 6, backgroundColor: Q.surface2, color: Q.primary),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      S.updateDownloading(formatPercent((progress * 100).round())),
                      style: QText.body(13, color: Q.textMuted, weight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
            if (_error case final error?) ...[
              const SizedBox(height: 10),
              Semantics(
                liveRegion: true,
                child: Text(error, style: QText.body(13, color: Q.dontKnow, weight: FontWeight.w700)),
              ),
            ],
            const SizedBox(height: 10),
            // Wraps on a narrow phone or with large system text.
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: progress != null ? null : () => ref.read(updateLaterProvider.notifier).hide(latest.versionCode),
                  style: TextButton.styleFrom(
                    foregroundColor: Q.textMuted,
                    minimumSize: const Size(64, 44),
                    textStyle: QText.body(14, weight: FontWeight.w800),
                  ),
                  child: const Text(S.updateLater),
                ),
                FilledButton(
                  onPressed: progress != null ? null : () => _update(latest),
                  style: FilledButton.styleFrom(
                    backgroundColor: Q.primary,
                    foregroundColor: Q.onPrimary,
                    minimumSize: const Size(96, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    textStyle: QText.body(14, weight: FontWeight.w800),
                  ),
                  child: const Text(S.updateNow),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
