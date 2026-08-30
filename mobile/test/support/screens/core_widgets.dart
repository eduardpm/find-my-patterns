import 'package:find_my_patterns/core/theme/app_theme.dart';
import 'package:find_my_patterns/core/theme/journal_metrics.dart';
import 'package:find_my_patterns/core/widgets/feature_placeholder.dart';
import 'package:find_my_patterns/core/widgets/journal.dart';
import 'package:find_my_patterns/core/widgets/premium_lock.dart';
import 'package:find_my_patterns/core/widgets/status_views.dart';
import 'package:flutter/material.dart';

import '../screen_registry.dart';

/// Exercises every text-bearing widget `journal.dart` declares, together,
/// since the whole-file registry granularity means the file gets one
/// [ScreenCase] rather than one per class (`no surface is registered by two
/// areas` in `screen_layout_matrix_test.dart` fires on a repeated `source`,
/// same-area repeats included).
///
/// `FeelingDot` is the one widget in the file left out: it paints a filled
/// circle and nothing else (`ExcludeSemantics(child: Container(...))`, no
/// `Text`), so there is nothing here for the sweep's invariants to check.
///
/// Content is drawn from real call sites, not invented: the eyebrow mirrors
/// `day_entries_screen.dart`'s `DateFormat('EEEE, MMMM d')`; the page title
/// is topic-phrase length, matching `experiment_results_screen.dart`'s
/// capitalised `patternTopic` title; the button row's labels are
/// `entry_detail_screen.dart`'s edit-conflict pair ("Keep mine (overwrite)"
/// / an even longer PillButton label from `experiment_setup_sheet.dart`,
/// "Abandon it and start this instead"); the empty state's icon/title/
/// supporting/action combination is `day_entries_screen.dart`'s own
/// no-entries state, and its supporting sentence is
/// `insights_screen.dart`'s `_InsufficientDataState` text with concrete
/// numbers filled in; `JournalCard` wraps prose the length of a real diary
/// paragraph, matching `entry_detail_screen.dart`'s own
/// `JournalCard(child: Text(conflict.mine, ...))`. The badge Wrap adds
/// "procrastination" -- a plausible single-word topic alias with no
/// hyphen or space for a line break to legally land on, unlike a compound
/// word -- next to the app's own two longest fixed badge strings.
Widget _journalDesignSystemScreen() => MaterialApp(
  theme: buildLightTheme(),
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(JournalSpacing.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            eyebrow: const Eyebrow('Wednesday, September 30'),
            title: const Text(
              'Late-night screen time before bed',
              style: TextStyle(fontSize: 24),
            ),
            actions: [
              StatusBadge(
                'Consider changing',
                leading: const Icon(Icons.trending_down, size: 14),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Next day',
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: JournalSpacing.x5),
          JournalCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Slept badly and woke up several times, then the morning '
                  'got better.',
                ),
                const SizedBox(height: JournalSpacing.x3),
                const Wrap(
                  spacing: JournalSpacing.x2,
                  runSpacing: JournalSpacing.x2,
                  children: [
                    StatusBadge('Historical'),
                    StatusBadge('Strong'),
                    StatusBadge('procrastination'),
                  ],
                ),
                const SizedBox(height: JournalSpacing.x4),
                Row(
                  children: [
                    Expanded(
                      child: PillButton(
                        onPressed: () {},
                        child: const Text(
                          'Abandon it and start this instead',
                        ),
                      ),
                    ),
                    const SizedBox(width: JournalSpacing.x2),
                    SecondaryPillButton(
                      onPressed: () {},
                      child: const Text('Keep mine (overwrite)'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: JournalSpacing.x5),
          EmptyState(
            icon: const Icon(Icons.insights),
            title: const Text('Not enough data yet'),
            supporting: const Text(
              'Keep logging entries — once a topic and a feeling repeat at '
              'least 3 times in the last 30 days, the pattern shows up '
              'here.',
              textAlign: TextAlign.center,
            ),
            action: PillButton(
              onPressed: () {},
              child: const Text('Write about this day'),
            ),
          ),
        ],
      ),
    ),
  ),
);

/// `lib/core/widgets/` and the app root.
final coreWidgets = ScreenArea(
  name: 'core widgets',
  cases: [
    ScreenCase(
      name: 'PremiumLock',
      source: 'core/widgets/premium_lock.dart',
      build: () => MaterialApp(
        theme: buildLightTheme(),
        home: const Scaffold(
          body: PremiumLock(message: 'Weekly digests are a Premium feature.'),
        ),
      ),
    ),
    // No real call site exists yet -- grep found none in `lib/`, since every
    // screen in this app has already been built out and replaced its own
    // starter placeholder. Content below stands in for the longest a real
    // one would plausibly carry: a feature name the length of the ones
    // already in this app ("Weekly Pattern Digest", matching
    // `PremiumLock`'s own "Weekly digests" case above) and a full
    // file-to-replace sentence in the message, the shape every other
    // starter placeholder in a `bootstrap`-forked app carries.
    ScreenCase(
      name: 'PlaceholderView',
      source: 'core/widgets/feature_placeholder.dart',
      build: () => MaterialApp(
        theme: buildLightTheme(),
        home: const Scaffold(
          body: PlaceholderView(
            icon: Icons.auto_awesome,
            title: 'Weekly Pattern Digest',
            message:
                'This screen is a placeholder. Replace '
                'lib/features/digest/weekly_digest_screen.dart with the '
                'real screen once its design is ready.',
          ),
        ),
      ),
    ),
    // `LoadingView` and `ErrorView` together, for the same one-source-per-
    // file reason `journal.dart`'s widgets are combined above. `label` has
    // no real call site either -- every `LoadingView()` in `lib/` is bare
    // -- so it is stressed with a plausible sentence of the same shape as
    // this app's own status text (`_messageFor` in `insights_screen.dart`).
    // `ErrorView.message` is stressed with a full sentence rather than one
    // of the app's own short fixed strings ('Could not reach the server.'):
    // `HttpFailure.message` in `api_error.dart` carries the backend's own
    // words verbatim and this client never rewrites them (`CLAUDE.md`'s
    // "the backend owns the logic" rule), so a long server-authored message
    // is the realistic case, not the invented one.
    ScreenCase(
      name: 'StatusViews',
      source: 'core/widgets/status_views.dart',
      build: () => MaterialApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: JournalSpacing.x7),
                const LoadingView(
                  label: 'Checking whether your server is reachable…',
                ),
                const SizedBox(height: JournalSpacing.x7 * 2),
                ErrorView(
                  message:
                      "We couldn't save your changes because another "
                      'device edited this entry after you loaded it. '
                      'Refresh and try again.',
                  onRetry: () {},
                  onConfigure: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    ScreenCase(
      name: 'JournalDesignSystem',
      source: 'core/widgets/journal.dart',
      build: _journalDesignSystemScreen,
    ),
  ],
  unswept: const {
    // Paint no text of their own; nothing for the invariants to check.
    'app.dart',
    'core/widgets/journal_dashed_border.dart',
    'core/widgets/journal_page_wash.dart',
    'core/widgets/journal_scrollbar.dart',

    // Swept transitively by `LoginScreen`, which is where its known #169
    // failure is recorded. Registering it standalone would duplicate that.
    'core/widgets/server_form.dart',
  },
);
