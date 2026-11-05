import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../settings/settings_screen.dart';

/// One-time onboarding flow shown after the user's first login (#41).
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _totalSteps = 6;

  int _step = 0;
  bool _fourRatings = false;
  int _dailyGoal = 20;
  int _newCardsPerDay = 5;
  bool _touchedRatings = false;
  bool _touchedGoal = false;
  bool _touchedNew = false;
  UserSettings? _serverSettings;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSettings());
  }

  Future<void> _loadSettings() async {
    try {
      final s = await ref.read(apiClientProvider).settings();
      if (!mounted) return;
      setState(() {
        _serverSettings = s;
        if (!_touchedRatings) _fourRatings = s.fourRatings;
        if (!_touchedGoal) _dailyGoal = s.dailyGoal;
        if (!_touchedNew) _newCardsPerDay = s.newCardsPerDay;
      });
    } on Object {
      // Defaults stay in place if the initial settings call fails.
    }
  }

  void _back() {
    if (_saving || _step == 0) return;
    setState(() {
      _error = null;
      _step--;
    });
  }

  void _next() {
    if (_saving) return;
    if (_step < _totalSteps - 1) {
      setState(() {
        _error = null;
        _step++;
      });
    } else {
      unawaited(_finish());
    }
  }

  Future<void> _finish() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final base = _serverSettings ??
        const UserSettings(
          dailyGoal: 20,
          newCardsPerDay: 5,
          notificationsEnabled: true,
          morningTime: '08:00',
          eveningTime: '18:30',
          lastCallTime: '21:00',
          quietFrom: '22:00',
          quietTo: '07:00',
          smartTimes: true,
        );
    final next = base.copyWith(
      fourRatings: _fourRatings,
      dailyGoal: _dailyGoal,
      newCardsPerDay: _newCardsPerDay,
    );
    try {
      final update = await ref.read(apiClientProvider).saveSettings(next);
      final notifications = ref.read(notificationsProvider);
      unawaited(notifications.onSettings(update.settings));
      unawaited(notifications.onSummary(update.summary, update.events));
      if (!mounted) return;
      ref
        ..invalidate(settingsProvider)
        ..invalidate(homeProvider);
      await ref.read(onboardingProvider.notifier).complete();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _step == _totalSteps - 1;
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 48,
                      child: Row(
                        children: [
                          if (_step > 0)
                            IconButton(
                              tooltip: S.back,
                              icon: const Icon(Icons.arrow_back_rounded, color: Q.text),
                              onPressed: _saving ? null : _back,
                            )
                          else
                            const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              S.onboardingStep(_step + 1, _totalSteps),
                              style: QText.body(14, color: Q.textMuted, weight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: _StepIndicator(current: _step, total: _totalSteps),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  key: ValueKey(_step),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: switch (_step) {
                    0 => const _AboutStep(),
                    1 => const _FsrsStep(),
                    2 => _RatingsStep(
                        fourRatings: _fourRatings,
                        onChanged: (v) => setState(() {
                          _touchedRatings = true;
                          _fourRatings = v;
                        }),
                      ),
                    3 => _GoalStep(
                        value: _dailyGoal,
                        onChanged: (v) => setState(() {
                          _touchedGoal = true;
                          _dailyGoal = v.clamp(UserSettings.minGoal, UserSettings.maxGoal);
                        }),
                      ),
                    4 => _NewCardsStep(
                        value: _newCardsPerDay,
                        onChanged: (v) => setState(() {
                          _touchedNew = true;
                          _newCardsPerDay = v.clamp(UserSettings.minNew, UserSettings.maxNew);
                        }),
                      ),
                    _ => _WelcomeStep(
                        fourRatings: _fourRatings,
                        dailyGoal: _dailyGoal,
                        newCardsPerDay: _newCardsPerDay,
                      ),
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error case final error?) ...[
                      Semantics(
                        liveRegion: true,
                        child: Text(error, style: QText.body(14, color: Q.dontKnow, weight: FontWeight.w700)),
                      ),
                      const SizedBox(height: 12),
                    ],
                    PrimaryButton(
                      label: isLast ? S.onboardingStart : S.next,
                      onPressed: _next,
                      busy: _saving,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: i <= current ? Q.primary : Q.surface2,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _AboutStep extends StatelessWidget {
  const _AboutStep();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(S.onboardingAboutTitle, style: QText.heading(32)),
        const SizedBox(height: 10),
        Text(S.onboardingAboutLead, style: QText.body(16, color: Q.textMuted, weight: FontWeight.w400, height: 1.45)),
        const SizedBox(height: 24),
        const Panel(
          child: Column(
            children: [
              _InfoItem(
                icon: Icons.style_rounded,
                color: Q.primary,
                title: S.onboardingAboutCardsTitle,
                text: S.onboardingAboutCardsText,
              ),
              SizedBox(height: 18),
              _InfoItem(
                icon: Icons.local_fire_department_rounded,
                color: Q.multiplier,
                title: S.onboardingAboutStreakTitle,
                text: S.onboardingAboutStreakText,
              ),
              SizedBox(height: 18),
              _InfoItem(
                icon: Icons.star_rounded,
                color: Q.points,
                title: S.onboardingAboutPointsTitle,
                text: S.onboardingAboutPointsText,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FsrsStep extends StatelessWidget {
  const _FsrsStep();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(S.onboardingFsrsTitle, style: QText.heading(32)),
        const SizedBox(height: 10),
        Text(S.onboardingFsrsLead, style: QText.body(16, color: Q.textMuted, weight: FontWeight.w400, height: 1.45)),
        const SizedBox(height: 24),
        const Panel(
          child: Column(
            children: [
              _InfoItem(
                icon: Icons.psychology_rounded,
                color: Q.primary,
                title: S.onboardingFsrsTimingTitle,
                text: S.onboardingFsrsTimingText,
              ),
              SizedBox(height: 18),
              _InfoItem(
                icon: Icons.trending_up_rounded,
                color: Q.info,
                title: S.onboardingFsrsKnowTitle,
                text: S.onboardingFsrsKnowText,
              ),
              SizedBox(height: 18),
              _InfoItem(
                icon: Icons.replay_rounded,
                color: Q.dontKnow,
                title: S.onboardingFsrsDontKnowTitle,
                text: S.onboardingFsrsDontKnowText,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoItem extends StatelessWidget {
  const _InfoItem({required this.icon, required this.color, required this.title, required this.text});

  final IconData icon;
  final Color color;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: Q.tint(color), borderRadius: BorderRadius.circular(14)),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: QText.body(16, weight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(text, style: QText.body(14, color: Q.textMuted, weight: FontWeight.w400, height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }
}

class _RatingsStep extends StatelessWidget {
  const _RatingsStep({required this.fourRatings, required this.onChanged});

  final bool fourRatings;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(S.onboardingRatingsTitle, style: QText.heading(32)),
        const SizedBox(height: 10),
        Text(S.onboardingRatingsLead, style: QText.body(16, color: Q.textMuted, weight: FontWeight.w400, height: 1.45)),
        const SizedBox(height: 24),
        _ChoiceCard(
          title: S.onboardingTwoRatingsTitle,
          subtitle: S.onboardingTwoRatingsText,
          selected: !fourRatings,
          onTap: () => onChanged(false),
          preview: const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Tag(label: S.dontKnow, color: Q.dontKnow),
              Tag(label: S.know, color: Q.primary),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ChoiceCard(
          title: S.onboardingFourRatingsTitle,
          subtitle: S.onboardingFourRatingsText,
          selected: fourRatings,
          onTap: () => onChanged(true),
          preview: const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Tag(label: S.dontKnow, color: Q.dontKnow),
              Tag(label: S.hard, color: Q.points),
              Tag(label: S.know, color: Q.primary),
              Tag(label: S.easy, color: Q.info),
            ],
          ),
        ),
      ],
    );
  }
}

class _GoalStep extends StatelessWidget {
  const _GoalStep({required this.value, required this.onChanged});

  static const easyGoal = 10;
  static const mediumGoal = 20;
  static const hardGoal = 40;

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(S.onboardingGoalTitle, style: QText.heading(28)),
        const SizedBox(height: 8),
        Text(S.onboardingGoalLead, style: QText.body(15, color: Q.textMuted, weight: FontWeight.w400, height: 1.4)),
        const SizedBox(height: 16),
        _PresetCard(
          title: S.presetEasy,
          countLabel: cards(easyGoal),
          hint: S.onboardingGoalEasyHint,
          selected: value == easyGoal,
          onTap: () => onChanged(easyGoal),
        ),
        const SizedBox(height: 8),
        _PresetCard(
          title: S.presetMedium,
          countLabel: cards(mediumGoal),
          hint: S.onboardingGoalMediumHint,
          selected: value == mediumGoal,
          onTap: () => onChanged(mediumGoal),
        ),
        const SizedBox(height: 8),
        _PresetCard(
          title: S.presetHard,
          countLabel: cards(hardGoal),
          hint: S.onboardingGoalHardHint,
          selected: value == hardGoal,
          onTap: () => onChanged(hardGoal),
        ),
        const SizedBox(height: 12),
        _AdjustPanel(
          title: S.onboardingAdjustGoal,
          hint: S.onboardingAdjustGoalHint,
          value: value,
          min: UserSettings.minGoal,
          max: UserSettings.maxGoal,
          decreaseLabel: S.decreaseGoal,
          increaseLabel: S.increaseGoal,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _NewCardsStep extends StatelessWidget {
  const _NewCardsStep({required this.value, required this.onChanged});

  static const easyNew = 3;
  static const mediumNew = 5;
  static const hardNew = 10;

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(S.onboardingNewTitle, style: QText.heading(28)),
        const SizedBox(height: 8),
        Text(S.onboardingNewLead, style: QText.body(15, color: Q.textMuted, weight: FontWeight.w400, height: 1.4)),
        const SizedBox(height: 16),
        _PresetCard(
          title: S.presetEasy,
          countLabel: cards(easyNew),
          hint: S.onboardingNewEasyHint,
          selected: value == easyNew,
          onTap: () => onChanged(easyNew),
        ),
        const SizedBox(height: 8),
        _PresetCard(
          title: S.presetMedium,
          countLabel: cards(mediumNew),
          hint: S.onboardingNewMediumHint,
          selected: value == mediumNew,
          onTap: () => onChanged(mediumNew),
        ),
        const SizedBox(height: 8),
        _PresetCard(
          title: S.presetHard,
          countLabel: cards(hardNew),
          hint: S.onboardingNewHardHint,
          selected: value == hardNew,
          onTap: () => onChanged(hardNew),
        ),
        const SizedBox(height: 12),
        _AdjustPanel(
          title: S.onboardingAdjustNew,
          hint: S.onboardingAdjustNewHint,
          value: value,
          min: UserSettings.minNew,
          max: UserSettings.maxNew,
          decreaseLabel: S.fewerNew,
          increaseLabel: S.moreNew,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({
    required this.fourRatings,
    required this.dailyGoal,
    required this.newCardsPerDay,
  });

  final bool fourRatings;
  final int dailyGoal;
  final int newCardsPerDay;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: Q.tint(Q.primary), borderRadius: BorderRadius.circular(20)),
          child: const Icon(Icons.celebration_rounded, color: Q.primary, size: 34),
        ),
        const SizedBox(height: 20),
        Text(S.onboardingWelcomeTitle, style: QText.heading(34)),
        const SizedBox(height: 10),
        Text(S.onboardingWelcomeLead, style: QText.body(16, color: Q.textMuted, weight: FontWeight.w400, height: 1.45)),
        const SizedBox(height: 24),
        Panel(
          padding: EdgeInsets.zero,
          radius: 20,
          child: Column(
            children: [
              _SummaryRow(
                label: S.onboardingSummaryRatings,
                value: fourRatings ? S.onboardingFourRatingsTitle : S.onboardingTwoRatingsTitle,
              ),
              const Divider(height: 1, color: Q.border),
              _SummaryRow(
                label: S.dailyGoal,
                value: cards(dailyGoal),
              ),
              const Divider(height: 1, color: Q.border),
              _SummaryRow(
                label: S.newPerDay,
                value: cards(newCardsPerDay),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Expanded(child: Text(label, style: QText.body(15, color: Q.textMuted, weight: FontWeight.w600))),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: QText.body(15, color: Q.primary, weight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.preview,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Widget? preview;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$title. $subtitle',
      excludeSemantics: true,
      child: Material(
        color: Q.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: selected ? Q.primary : Q.border, width: selected ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: QText.body(16, weight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(subtitle, style: QText.body(13, color: Q.textMuted, weight: FontWeight.w400, height: 1.4)),
                      if (preview != null) ...[
                        const SizedBox(height: 12),
                        preview!,
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _RadioCheck(selected: selected),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.title,
    required this.countLabel,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String countLabel;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$title, $countLabel. $hint',
      excludeSemantics: true,
      child: Material(
        color: Q.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: selected ? Q.primary : Q.border, width: selected ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(title, style: QText.body(16, weight: FontWeight.w800)),
                          const SizedBox(width: 10),
                          Tag(label: countLabel, color: selected ? Q.primary : Q.textMuted),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(hint, style: QText.body(13, color: Q.textMuted, weight: FontWeight.w400, height: 1.35)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _RadioCheck(selected: selected),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RadioCheck extends StatelessWidget {
  const _RadioCheck({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    if (selected) {
      return Container(
        width: 28,
        height: 28,
        decoration: const BoxDecoration(color: Q.primary, shape: BoxShape.circle),
        child: const Icon(Icons.check_rounded, color: Q.onPrimary, size: 18),
      );
    }
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Q.inputBorder, width: 1.5),
      ),
    );
  }
}

class _AdjustPanel extends StatelessWidget {
  const _AdjustPanel({
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
    return Panel(
      radius: 20,
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
              width: 44,
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
