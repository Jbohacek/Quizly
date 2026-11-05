import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
import '../notifications/notifications.dart';
import 'how_it_works.dart';

final settingsProvider = FutureProvider.autoDispose<UserSettings>((ref) => ref.watch(apiClientProvider).settings());

final _versionProvider = FutureProvider<String>((ref) async => (await PackageInfo.fromPlatform()).version);

/// Nastavení (design screen 9).
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
  late final ApiClient _client;
  late final Notifications _notifications;
  Timer? _debounce;
  int _saveVersion = 0;

  @override
  void initState() {
    super.initState();
    _client = ref.read(apiClientProvider);
    _notifications = ref.read(notificationsProvider);
    unawaited(_notifications.onSettings(widget.initial));
  }

  @override
  void dispose() {
    // A change still waiting for the debounce is saved anyway (best effort).
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
      unawaited(_client.saveSettings(_settings).then<void>(_applied, onError: (_) {}));
    }
    super.dispose();
  }

  /// The reminders follow every saved change; a lowered goal can also complete today.
  Future<void> _applied(SettingsUpdate update) async {
    await _notifications.onSettings(update.settings);
    await _notifications.onSummary(update.summary, update.events);
  }

  void _change(UserSettings next) {
    setState(() => _settings = next);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () => _save(next));
  }

  Future<void> _save(UserSettings settings) async {
    final version = ++_saveVersion;
    try {
      final update = await _client.saveSettings(settings);
      _saved = update.settings;
      unawaited(_applied(update));
      if (mounted) ref.invalidate(homeProvider);
    } on ApiException catch (e) {
      if (!mounted || version != _saveVersion) return;
      setState(() => _settings = _saved);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${S.settingsSaveFailed} ${e.message}')));
    }
  }

  Future<void> _toggleNotifications(bool on) async {
    _change(_settings.copyWith(notificationsEnabled: on));
    if (!on || ref.read(notificationPermissionProvider).value == true) return;
    await _notifications.requestPermission();
    if (mounted) ref.invalidate(notificationPermissionProvider);
  }

  /// Android asks again after one "Don't allow"; after two it only lets the user switch it on in its settings.
  Future<void> _allowNotifications() async {
    if (!await _notifications.requestPermission()) await _notifications.platform.openSystemSettings();
    if (mounted) ref.invalidate(notificationPermissionProvider);
  }

  Future<String?> _pickTime(String title, String current) async {
    final [h, m] = current.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.parse(h), minute: int.parse(m)),
      helpText: title,
      builder: (context, child) =>
          MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (picked == null) return null;
    return '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _pickQuiet() async {
    final from = await _pickTime(S.quietFrom, _settings.quietFrom);
    if (from == null || !mounted) return;
    final to = await _pickTime(S.quietTo, _settings.quietTo);
    if (to == null || !mounted) return;
    if (from == to) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(S.quietSame)));
      return;
    }
    _change(_settings.copyWith(quietFrom: from, quietTo: to));
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

  List<Widget> _notificationSection() {
    final on = _settings.notificationsEnabled;
    final permitted = ref.watch(notificationPermissionProvider).value;
    final smart = _settings.smartTimes ? ref.watch(homeProvider).value?.me.smartEveningTime : null;
    Future<void> time(String title, String current, UserSettings Function(String value) apply) async {
      final picked = await _pickTime(title, current);
      if (picked != null && mounted) _change(apply(picked));
    }

    return [
      if (on && permitted == false) ...[
        _SystemOff(onOpen: _allowNotifications),
        const SizedBox(height: 10),
      ],
      Panel(
        padding: EdgeInsets.zero,
        radius: 20,
        child: Column(
          children: [
            _Toggle(title: S.sendNotifications, hint: S.sendNotificationsHint, value: on, onChanged: _toggleNotifications),
            const Divider(height: 1, color: Q.border),
            _TimeRow(
              title: S.morningReminder,
              hint: S.morningReminderHint,
              value: _settings.morningTime,
              enabled: on,
              onTap: () => time(S.morningReminder, _settings.morningTime, (v) => _settings.copyWith(morningTime: v)),
            ),
            const Divider(height: 1, color: Q.border),
            _TimeRow(
              title: S.eveningReminder,
              hint: smart == null ? S.eveningReminderHint : S.eveningSmart(smart),
              value: _settings.eveningTime,
              enabled: on,
              onTap: () => time(S.eveningReminder, _settings.eveningTime, (v) => _settings.copyWith(eveningTime: v)),
            ),
            const Divider(height: 1, color: Q.border),
            _TimeRow(
              title: S.lastCall,
              hint: S.lastCallHint,
              value: _settings.lastCallTime,
              enabled: on,
              onTap: () => time(S.lastCall, _settings.lastCallTime, (v) => _settings.copyWith(lastCallTime: v)),
            ),
            const Divider(height: 1, color: Q.border),
            _TimeRow(
              title: S.quietHours,
              hint: S.quietHoursHint,
              value: S.quietRange(_settings.quietFrom, _settings.quietTo),
              enabled: on,
              onTap: _pickQuiet,
            ),
            const Divider(height: 1, color: Q.border),
            _Toggle(
              title: S.smartTimes,
              hint: S.smartTimesHint,
              value: _settings.smartTimes,
              enabled: on,
              onChanged: (v) => _change(_settings.copyWith(smartTimes: v)),
            ),
          ],
        ),
      ),
    ];
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
        const SizedBox(height: 10),
        Material(
          color: Q.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Q.border)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.go('/settings/password'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline_rounded, color: Q.textMuted),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(S.changePassword, style: QText.body(15, weight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(S.changePasswordHint, style: QText.body(12, color: Q.textMuted, weight: FontWeight.w400)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Q.textMuted),
                ],
              ),
            ),
          ),
        ),
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
              const Divider(height: 1, color: Q.border),
              _Toggle(
                title: S.fourRatings,
                hint: S.fourRatingsHint,
                value: _settings.fourRatings,
                onChanged: (v) => _change(_settings.copyWith(fourRatings: v)),
              ),
              const Divider(height: 1, color: Q.border),
              _Toggle(
                title: S.showInLeaderboard,
                hint: S.showInLeaderboardHint,
                value: _settings.showInLeaderboard,
                onChanged: (v) => _change(_settings.copyWith(showInLeaderboard: v)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Material(
          color: Q.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Q.border)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => showHowItWorks(context),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
              child: Row(
                children: [
                  const Icon(Icons.help_outline_rounded, color: Q.textMuted),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(S.howItWorks, style: QText.body(15, weight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(S.howItWorksHint, style: QText.body(12, color: Q.textMuted, weight: FontWeight.w400)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Q.textMuted),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _SectionTitle(S.notifications),
        ..._notificationSection(),
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

/// Shown when notifications are on in Quizly but blocked by Android.
class _SystemOff extends StatelessWidget {
  const _SystemOff({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Panel(
      radius: 20,
      color: Q.points.withValues(alpha: 0.10),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.notifications_off_outlined, color: Q.points),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(S.systemOff, style: QText.body(15, weight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(S.systemOffText, style: QText.body(12, color: Q.textMuted, weight: FontWeight.w400, height: 1.35)),
                  ],
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onOpen,
              style: TextButton.styleFrom(
                foregroundColor: Q.points,
                minimumSize: const Size(64, 44),
                textStyle: QText.body(14, weight: FontWeight.w800),
              ),
              child: const Text(S.allowNotifications),
            ),
          ),
        ],
      ),
    );
  }
}

class _RowText extends StatelessWidget {
  const _RowText({required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: QText.body(15, weight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(hint, style: QText.body(12, color: Q.textMuted, weight: FontWeight.w400, height: 1.35)),
        ],
      );
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.title, required this.hint, required this.value, required this.onChanged, this.enabled = true});

  final String title;
  final String hint;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: InkWell(
          onTap: enabled ? () => onChanged(!value) : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              children: [
                Expanded(child: _RowText(title: title, hint: hint)),
                const SizedBox(width: 12),
                Switch(
                  value: value,
                  onChanged: enabled ? onChanged : null,
                  activeTrackColor: Q.primary,
                  activeThumbColor: Q.onPrimary,
                  inactiveTrackColor: Q.surface2,
                  inactiveThumbColor: Q.textMuted,
                  trackOutlineColor: const WidgetStatePropertyAll(Q.border),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({required this.title, required this.hint, required this.value, required this.enabled, required this.onTap});

  final String title;
  final String hint;
  final String value;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: S.timeLabel(title, value),
      hint: hint,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
            child: Row(
              children: [
                Expanded(child: _RowText(title: title, hint: hint)),
                const SizedBox(width: 12),
                Container(
                  constraints: const BoxConstraints(minHeight: 44, minWidth: 64),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(color: Q.surface2, borderRadius: BorderRadius.circular(12)),
                  child: Text(value, style: QText.heading(16).copyWith(letterSpacing: 0)),
                ),
              ],
            ),
          ),
        ),
      ),
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
