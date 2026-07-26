import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/auth/auth_providers.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _isLoading = false;
  String? _error;

  Future<void> _login() async {
    final l10n = AppLocalizations.of(context)!;
    final username = _username.text.trim();
    final password = _password.text;

    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = l10n.pleaseEnterCredentials);
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final error =
        await ref.read(authProvider.notifier).login(username, password);

    if (mounted) {
      setState(() {
        _isLoading = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.loginTitle,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 32),
                    if (_error != null) ...[
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextField(
                      controller: _username,
                      decoration: InputDecoration(
                        labelText: l10n.usernameLabel,
                        prefixIcon: const Icon(Icons.person),
                        border: const OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: l10n.passwordLabel,
                        prefixIcon: const Icon(Icons.lock),
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _login(),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed: _isLoading ? null : _login,
                        child: _isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.white)
                            : Text(l10n.loginTitle),
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
