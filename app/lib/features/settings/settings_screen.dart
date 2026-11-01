import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/config.dart';
import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';

final settingsProvider = FutureProvider.autoDispose<UserSettings>((ref) => ref.watch(apiClientProvider).settings());

final _versionProvider = FutureProvider<String>((ref) async => (await PackageInfo.fromPlatform()).version);

/// Nastavení (design screen 9). Notification options arrive in Etapa 7.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return SafeArea(
      bottom: false,
      child: switch (settings) {
        AsyncValue(:final value?) => _SettingsBody(initial: value),
        AsyncValue(:final error?) => ErrorView(
            message: error is ApiException ? error.message : S.loadFailed,
            onRetry: () => ref.invalidate(settingsProvider),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _SettingsBody extends ConsumerStatefulWidget {
  const _SettingsBody({required this.initial});

  final UserSettings initial;

  @override
  ConsumerState<_SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends ConsumerState<_SettingsBody> {
  late UserSettings _settings = widget.initial;
  late UserSettings _saved = widget.initial;
  late final ApiClient _client = ref.read(apiClientProvider);
  Timer? _debounce;
  int _saveVersion = 0;

  @override
  void dispose() {
    // A change still waiting for the debounce is saved anyway (best effort).
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
      unawaited(_client.saveSettings(_settings).then<void>((_) {}, onError: (_) {}));
    }
    super.dispose();
  }

  void _change(UserSettings next) {
    setState(() => _settings = next);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () => _save(next));
  }

  Future<void> _save(UserSettings settings) async {
    final version = ++_saveVersion;
    try {
      _saved = (await _client.saveSettings(settings)).settings;
      if (mounted) ref.invalidate(homeProvider);
    } on ApiException catch (e) {
      if (!mounted || version != _saveVersion) return;
      setState(() => _settings = _saved);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${S.settingsSaveFailed} ${e.message}')));
    }
  }

  Future<void> _signOut() async {
    final pending = ref.read(reviewSyncProvider)?.status.pending ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(S.signOutTitle),
        content: Text(pending > 0 ? S.signOutPending(pending) : S.signOutText),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text(S.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Q.dontKnow),
            child: const Text(S.signOut),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(authProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final version = ref.watch(_versionProvider).value ?? '';
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: [
        SizedBox(height: 48, child: Align(alignment: Alignment.centerLeft, child: Text(S.settings, style: QText.heading(28)))),
        const SizedBox(height: 16),
        if (user != null) _Account(user: user),
        const SizedBox(height: 16),
        _SectionTitle(S.learning),
        Panel(
          padding: EdgeInsets.zero,
          radius: 20,
          child: Column(
            children: [
              _Stepper(
                title: S.dailyGoal,
                hint: S.dailyGoalHint,
                value: _settings.dailyGoal,
                min: UserSettings.minGoal,
                max: UserSettings.maxGoal,
                decreaseLabel: S.decreaseGoal,
                increaseLabel: S.increaseGoal,
                onChanged: (v) => _change(_settings.copyWith(dailyGoal: v)),
              ),
              const Divider(height: 1, color: Q.border),
              _Stepper(
                title: S.newPerDay,
                hint: S.newPerDayHint,
                value: _settings.newCardsPerDay,
                min: UserSettings.minNew,
                max: UserSettings.maxNew,
                decreaseLabel: S.fewerNew,
                increaseLabel: S.moreNew,
                onChanged: (v) => _change(_settings.copyWith(newCardsPerDay: v)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SecondaryButton(label: S.signOut, color: Q.dontKnow, outlined: true, onPressed: _signOut),
        const SizedBox(height: 16),
        Text(
          S.version(version, Uri.parse(apiBaseUrl).host),
          textAlign: TextAlign.center,
          style: QText.body(12, color: Q.textMuted, weight: FontWeight.w400),
        ),
      ],
    );
  }
}

class _Account extends StatelessWidget {
  const _Account({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    return Panel(
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: Q.primary, shape: BoxShape.circle),
            child: Text(
              user.displayName.characters.take(1).toString().toUpperCase(),
              style: QText.heading(20, color: Q.onPrimary).copyWith(letterSpacing: 0),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(S.account, style: QText.body(12, color: Q.textMuted, weight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(user.displayName, style: QText.body(17, weight: FontWeight.w800), overflow: TextOverflow.ellipsis),
                Text(user.username, style: QText.body(13, color: Q.textMuted, weight: FontWeight.w600)),
              ],
            ),
          ),
          Text(
            S.passwordByAdmin,
            textAlign: TextAlign.right,
            style: QText.body(12, color: Q.textMuted, weight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(
          text.toUpperCase(),
          style: QText.body(13, color: Q.textMuted, weight: FontWeight.w800).copyWith(letterSpacing: 0.8),
        ),
      );
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.title,
    required this.hint,
    required this.value,
    required this.min,
    required this.max,
    required this.decreaseLabel,
    required this.increaseLabel,
    required this.onChanged,
  });

  final String title;
  final String hint;
  final int value;
  final int min;
  final int max;
  final String decreaseLabel;
  final String increaseLabel;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: QText.body(15, weight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(hint, style: QText.body(12, color: Q.textMuted, weight: FontWeight.w400, height: 1.35)),
              ],
            ),
          ),
          _StepButton(label: decreaseLabel, text: '−', onPressed: value > min ? () => onChanged(value - 1) : null),
          Semantics(
            label: title,
            value: '$value',
            child: SizedBox(
              width: 40,
              child: Text('$value', textAlign: TextAlign.center, style: QText.heading(20).copyWith(letterSpacing: 0)),
            ),
          ),
          _StepButton(label: increaseLabel, text: '+', onPressed: value < max ? () => onChanged(value + 1) : null),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.label, required this.text, required this.onPressed});

  final String label;
  final String text;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: 44,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            backgroundColor: Q.surface2,
            foregroundColor: Q.text,
            disabledForegroundColor: Q.border,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: QText.body(22, weight: FontWeight.w700),
          ),
          child: Text(text),
        ),
      ),
    );
  }
}
