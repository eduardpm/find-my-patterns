import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/config/app_config.dart';
import '../../core/config/config_providers.dart';
import '../../core/network/api_error.dart';
import '../../core/settings/settings.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/widgets/server_form.dart';

/// The sign-in screen: one password, against the user's own server.
///
/// Only reached when [requireAuthProvider] is on. When no server has been
/// configured yet it shows the server form instead of the password field —
/// without that, a first launch would have no way to reach Settings and no way
/// to sign in, which is a dead end.
class LoginScreen extends ConsumerStatefulWidget {
  /// Creates the sign-in screen.
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController _password = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _showServerForm = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).login(_password.text);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backend =
        ref.watch(settingsProvider).value?.backend ?? BackendAddress.unset;
    final needsServer = !backend.isConfigured || _showServerForm;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    AppConfig.appName,
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    needsServer
                        ? 'First, point this app at your server.'
                        : 'Sign in to your own server.',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (needsServer)
                    ServerForm(
                      onSaved: () => setState(() => _showServerForm = false),
                    )
                  else
                    ..._passwordFields(theme, backend),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _passwordFields(ThemeData theme, BackendAddress backend) => [
    TextField(
      controller: _password,
      obscureText: true,
      autofocus: true,
      onSubmitted: (_) => _submit(),
      decoration: const InputDecoration(
        labelText: 'Password',
        border: OutlineInputBorder(),
      ),
    ),
    const SizedBox(height: 16),
    FilledButton(
      onPressed: _busy ? null : _submit,
      child: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text('Sign in'),
    ),
    if (_error != null) ...[
      const SizedBox(height: 12),
      Semantics(
        liveRegion: true,
        label: 'Sign-in failed: ${_error!}',
        excludeSemantics: true,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 18,
              color: theme.colorScheme.error,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ],
        ),
      ),
    ],
    const SizedBox(height: 16),
    TextButton(
      onPressed: () => setState(() => _showServerForm = true),
      child: Text('Connected to ${backend.origin} — change'),
    ),
  ];
}
