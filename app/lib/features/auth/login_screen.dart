import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';

/// Přihlášení (design screen 1).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final reason = ref.read(authProvider).reason;
    _error = switch (reason) {
      SignOutReason.sessionExpired => S.sessionExpired,
      SignOutReason.accountDisabled => S.accountDisabled,
      _ => null,
    };
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_username.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = S.fillBoth);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).login(_username.text, _password.text);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 28),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 76),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Logo(),
                    const SizedBox(height: 20),
                    Text(S.appName, style: QText.heading(44).copyWith(height: 1)),
                    const SizedBox(height: 8),
                    Text(S.loginTagline, style: QText.body(18, color: Q.textMuted, height: 1.4)),
                    const Spacer(),
                    const SizedBox(height: 32),
                    _Label(S.username),
                    TextField(
                      controller: _username,
                      autofillHints: const [AutofillHints.username],
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.next,
                      style: QText.body(16, weight: FontWeight.w600),
                      decoration: const InputDecoration(hintText: S.usernameHint),
                    ),
                    const SizedBox(height: 16),
                    _Label(S.password),
                    TextField(
                      controller: _password,
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      style: QText.body(16, weight: FontWeight.w600),
                      decoration: InputDecoration(
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
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Semantics(
                        liveRegion: true,
                        child: Text(_error!, style: QText.body(14, color: Q.dontKnow, weight: FontWeight.w700)),
                      ),
                    ],
                    const SizedBox(height: 24),
                    PrimaryButton(label: S.signIn, onPressed: _submit, busy: _busy),
                    const Spacer(),
                    const SizedBox(height: 32),
                    Panel(
                      radius: 18,
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline_rounded, color: Q.multiplier, size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              S.signInNote,
                              style: QText.body(14, color: Q.textMuted, weight: FontWeight.w400, height: 1.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 72,
        height: 72,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Q.primary, borderRadius: BorderRadius.circular(22)),
        child: Text('Q', style: QText.heading(44, color: Q.onPrimary).copyWith(height: 1, letterSpacing: 0)),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: QText.body(14, weight: FontWeight.w700)),
      );
}
