import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';

/// Nastavení → Změnit heslo. Other devices are signed out; this one stays logged in.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  static const minLength = 8;

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _again = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _currentError;
  String? _nextError;
  String? _againError;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _currentError = _current.text.isEmpty ? S.fillCurrentPassword : null;
      _nextError = _next.text.length < ChangePasswordScreen.minLength ? S.passwordTooShort : null;
      _againError = _nextError == null && _again.text != _next.text ? S.passwordsDiffer : null;
      _error = null;
    });
    if (_currentError != null || _nextError != null || _againError != null) return;

    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).changePassword(_current.text, _next.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(S.passwordChanged)));
      context.pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _currentError = e.fieldError('currentPassword');
        _nextError = e.fieldError('newPassword');
        _error = _currentError == null && _nextError == null ? e.message : null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Row(
              children: [
                SizedBox.square(
                  dimension: 44,
                  child: IconButton(
                    tooltip: S.back,
                    onPressed: () => context.pop(),
                    style: IconButton.styleFrom(
                      backgroundColor: Q.surface,
                      foregroundColor: Q.textMuted,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(child: Text(S.changePassword, style: QText.heading(26))),
              ],
            ),
            const SizedBox(height: 12),
            Text(S.passwordRules, style: QText.body(14, color: Q.textMuted, weight: FontWeight.w400, height: 1.45)),
            const SizedBox(height: 24),
            _field(S.currentPassword, _current, _currentError, AutofillHints.password, TextInputAction.next),
            const SizedBox(height: 16),
            _field(S.newPassword, _next, _nextError, AutofillHints.newPassword, TextInputAction.next),
            const SizedBox(height: 16),
            _field(S.newPasswordAgain, _again, _againError, AutofillHints.newPassword, TextInputAction.done),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(_error!, style: QText.body(14, color: Q.dontKnow, weight: FontWeight.w700)),
              ),
            ],
            const SizedBox(height: 24),
            PrimaryButton(label: S.changePassword, onPressed: _submit, busy: _busy),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController controller, String? error, String hint, TextInputAction action) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(label, style: QText.body(14, weight: FontWeight.w700)),
        ),
        TextField(
          controller: controller,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: [hint],
          textInputAction: action,
          onSubmitted: action == TextInputAction.done ? (_) => _submit() : null,
          style: QText.body(16, weight: FontWeight.w600),
          decoration: InputDecoration(
            errorText: error,
            errorStyle: QText.body(13, color: Q.dontKnow, weight: FontWeight.w700),
            // Out of the focus order, so the keyboard's "Next" goes to the next field.
            suffixIcon: ExcludeFocus(
              child: IconButton(
                tooltip: _obscure ? S.showPassword : S.hidePassword,
                color: Q.textMuted,
                icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
