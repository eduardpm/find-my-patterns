import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/config/app_config.dart';
import '../../core/config/config_providers.dart';
import '../../core/theme/journal_metrics.dart';
import '../../core/widgets/journal.dart';
import '../../core/widgets/journal_page_wash.dart';
import '../../core/widgets/server_form.dart';
import 'appearance_card.dart';

/// The shared Settings screen: where the backend is, how the app looks, and
/// what this app is.
///
/// Every app forked from this base keeps this screen more or less verbatim.
class SettingsScreen extends ConsumerWidget {
  /// Creates the Settings screen.
  const SettingsScreen({super.key});

  /// The path the Topics screen is registered under in the app's router.
  ///
  /// Kept as a constant on this screen rather than assumed at the call site,
  /// so the router wiring in `lib/app.dart` and the `context.push` call
  /// below can never silently name two different paths for the same
  /// destination.
  static const String topicsRoute = '/settings/topics';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Stack(
        children: [
          const Positioned.fill(child: JournalPageWash()),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.only(
                left: JournalSpacing.x4,
                right: JournalSpacing.x4,
                top: JournalSpacing.x5,
                bottom: JournalSpacing.x5,
              ),
              children: [
                PageHeader(
                  eyebrow: const Eyebrow('This device'),
                  title: Text('Settings', style: theme.textTheme.headlineSmall),
                ),
                const SizedBox(height: JournalSpacing.x5),
                _Section(
                  title: 'Server',
                  subtitle:
                      "Where this app's backend lives. The emulator's name "
                      'for this machine is 10.0.2.2.',
                  child: const ServerForm(),
                ),
                const SizedBox(height: JournalSpacing.x4),
                const AppearanceCard(),
                const SizedBox(height: JournalSpacing.x4),
                if (ref.watch(requireAuthProvider)) ...[
                  _Section(
                    title: 'Session',
                    subtitle: 'Sign out on this device.',
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          unawaited(ref.read(authProvider.notifier).logout()),
                      icon: const Icon(Icons.logout),
                      label: const Text('Sign out'),
                    ),
                  ),
                  const SizedBox(height: JournalSpacing.x4),
                ],
                // Settings rather than the bottom bar, for the same reason the
                // palette lives here: editing an alias is something you do
                // once when the app has got a word wrong, not a place you
                // visit on the way to writing.
                JournalCard(
                  onTap: () => unawaited(context.push(topicsRoute)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Topics and aliases',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: JournalSpacing.x2),
                      Text(
                        'See what the diary has noticed, and teach it that '
                        'two of your words mean the same thing. Nothing you '
                        'have written changes.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: JournalSpacing.x4),
                _Section(
                  title: 'About',
                  subtitle: null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${AppConfig.appName} ${AppConfig.appVersion}',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'The backend owns the logic; this app stays thin.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One titled card on the Settings screen, in the journal card style.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return JournalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          if (subtitle != null) ...[
            const SizedBox(height: JournalSpacing.x2),
            Text(
              subtitle!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: JournalSpacing.x5),
          child,
        ],
      ),
    );
  }
}
