import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/config/app_config.dart';
import '../../core/config/config_providers.dart';
import '../../core/settings/settings.dart';
import '../../core/settings/settings_controller.dart';
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Topics and aliases',
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
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
                _AdvancedSection(
                  // One central backend, run by the app's owner: nobody
                  // configures a server on a fresh, working install, so this
                  // stays collapsed once a real address is already saved.
                  // Until then — first run, or a saved address that was
                  // never completed — it opens by default, because a
                  // developer running against a local backend, and a first
                  // launch with nowhere else to go, both depend on it being
                  // easy to find.
                  initiallyExpanded:
                      !(ref.watch(settingsProvider).value?.backend ??
                              BackendAddress.unset)
                          .isConfigured,
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

/// The developer-plumbing corner of Settings: where this app's backend
/// lives, collapsed behind a header so it never competes with the settings a
/// paying customer actually uses.
///
/// One central backend run by the app's owner is the product's whole
/// hosting model — nobody self-hosts — so the server address is not a
/// primary setting any more. It still has to work, because local
/// development and any fork that does self-host both depend on it, which is
/// why the section opens and closes rather than disappearing.
class _AdvancedSection extends StatefulWidget {
  /// Builds the Advanced section. Open while [initiallyExpanded] is `true`
  /// and the user has not yet touched the header themselves.
  const _AdvancedSection({required this.initiallyExpanded});

  /// Whether the section should be open absent a manual toggle.
  ///
  /// Watched live rather than read once: settings load asynchronously, so
  /// the very first build of this screen always sees an unconfigured
  /// backend and this starts `true`. Following it keeps the section in step
  /// once the real, saved address arrives a frame later — a `late` field
  /// captured only at construction would freeze on that first, misleading
  /// value instead.
  final bool initiallyExpanded;

  @override
  State<_AdvancedSection> createState() => _AdvancedSectionState();
}

class _AdvancedSectionState extends State<_AdvancedSection> {
  /// The user's own choice, once they have tapped the header; `null` until
  /// then, so [_expanded] keeps following [_AdvancedSection.initiallyExpanded]
  /// up to that point without a later settings change — saving inside the
  /// form this section itself contains — yanking it shut under the user
  /// mid-edit.
  bool? _userToggled;

  bool get _expanded => _userToggled ?? widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return JournalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            label: 'Advanced',
            expanded: _expanded,
            excludeSemantics: true,
            child: InkWell(
              onTap: () => setState(() => _userToggled = !_expanded),
              child: ConstrainedBox(
                // 48dp: the touch-target floor, since the row is otherwise
                // only as tall as a line of text.
                constraints: const BoxConstraints(minHeight: JournalSpacing.x7),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Advanced',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: Icon(
                        Icons.expand_more,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: JournalSpacing.x2),
            Text(
              "Where this app's backend lives. Most people never need this "
              '— the app is configured to talk to one server. The '
              "emulator's name for this machine is 10.0.2.2.",
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: JournalSpacing.x5),
            const ServerForm(),
          ],
        ],
      ),
    );
  }
}
