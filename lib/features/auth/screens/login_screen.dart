import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:loqui/core/auth/auth_service.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _identity = TextEditingController(); // login: name#xxxx or email
  final _username = TextEditingController(); // register
  final _email = TextEditingController(); // register (optional)
  final _password = TextEditingController();

  bool _registerMode = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _identity.dispose();
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = ref.read(authControllerProvider.notifier);
    try {
      if (_registerMode) {
        await auth.register(
          _username.text.trim(),
          _password.text,
          _email.text.trim(),
        );
      } else {
        await auth.login(_identity.text.trim(), _password.text);
      }
      // success: router redirects on auth state change
    } catch (e) {
      setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message(Object e) {
    final s = e.toString();
    return s.contains(': ') ? s.split(': ').last : s;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Loqui',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 24),
                if (_registerMode) ...[
                  TextField(
                    controller: _username,
                    decoration: const InputDecoration(labelText: 'username'),
                    autofillHints: const [AutofillHints.newUsername],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _email,
                    decoration: const InputDecoration(
                      labelText: 'Email (optional)',
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                ] else
                  TextField(
                    controller: _identity,
                    decoration: const InputDecoration(
                      labelText: 'Handle (name#0000) or email',
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true,
                  onSubmitted: (_) => _busy ? null : _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_registerMode ? 'Create account' : 'Log in'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _registerMode = !_registerMode;
                          _error = null;
                        }),
                  child: Text(
                    _registerMode
                        ? 'Have an account? Log in'
                        : 'New here? Create an account',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
