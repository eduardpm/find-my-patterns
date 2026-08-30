import 'package:find_my_patterns/core/theme/app_theme.dart';
import 'package:find_my_patterns/core/theme/journal_metrics.dart';
import 'package:find_my_patterns/core/widgets/feature_placeholder.dart';
import 'package:find_my_patterns/core/widgets/journal.dart';
import 'package:find_my_patterns/core/widgets/premium_lock.dart';
import 'package:find_my_patterns/core/widgets/status_views.dart';
import 'package:flutter/material.dart';

import '../screen_registry.dart';

/// Mirrors `day_entries_screen.dart`'s private `_DayStepButton`: a fixed
/// 48x48 circular icon button that carries no text and never grows with
/// text scale. One of the two real shapes `PageHeader.actions` is built
/// with in `lib/` today.
Widget _dayStepButton(IconData icon, String description) => SizedBox(
  width: JournalSpacing.x7,
  height: JournalSpacing.x7,
  child: Semantics(
    label: description,
    button: true,
    child: ExcludeSemantics(
      child: OutlinedButton(
        onPressed: () {},
        style: OutlinedButton.styleFrom(
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
        ),
        child: Icon(icon),
      ),
    ),
  ),
);

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
/// **`PageHeader.actions` is built as both real call-site shapes, not one
/// invented combination.** Every `PageHeader(... actions: ...)` in `lib/` is
/// one of exactly two shapes, and a combination of a `StatusBadge` and an
/// icon button together -- what this case built for one revision of this
/// ticket -- appears nowhere and produced a measurement (34-238px overflow)
/// that did not describe a real screen. The two shapes that do exist:
///
/// - `day_entries_screen.dart:261`: two `_DayStepButton`s (`_dayStepButton`
///   above), each a fixed 48dp circle that never grows with text scale, next
///   to a title that is always a plain entry count (stressed here as
///   "12 entries", a two-digit count rather than the one-digit case a real
///   day this light would show).
/// - `experiment_results_screen.dart:228`: a single `StatusBadge` built by
///   the file's own private `_StatusBadgeFor`, whose text comes from the
///   closed `ExperimentStatus` enum -- `'Active'`, `'Finished'`, or
///   `'Abandoned'`, and nothing else ever reaches it. `'Abandoned'` is the
///   longest and is what is used below. The title beside it is
///   `_capitalise(experiment.patternTopic)`; the longest topic the backend's
///   own canonical list produces (`backend/src/topics/canonicalization.ts`,
///   `CURATED_TOPIC_KEYWORDS`) is `'fruit and vegetables'`, so `'Fruit and
///   vegetables'` is used rather than a shorter or invented topic.
///
/// The rest of the content is likewise drawn from real call sites: the
/// eyebrow mirrors `day_entries_screen.dart`'s own
/// `DateFormat('EEEE, MMMM d')`; the stacked button pair's labels are
/// `entry_detail_screen.dart`'s edit-conflict pair ("Keep mine (overwrite)"
/// / an even longer PillButton label from `experiment_setup_sheet.dart`,
/// "Abandon it and start this instead"), stacked full-width the way that
/// screen actually lays them out, not side by side; the empty state's
/// icon/title/supporting/action combination is `day_entries_screen.dart`'s
/// own no-entries state, and its supporting sentence is
/// `insights_screen.dart`'s `_InsufficientDataState` text with concrete
/// numbers filled in; `JournalCard` wraps prose the length of a real diary
/// paragraph, matching `entry_detail_screen.dart`'s own
/// `JournalCard(child: Text(conflict.mine, ...))`. The badge `Wrap` adds
/// "procrastination" -- a plausible single-word topic alias (aliases are
/// free-typed text per `topic.dart`'s own doc comment, so nothing bounds
/// their length or shape the way the canonical list bounds a topic name) --
/// next to the app's own two longest fixed badge strings.
Widget _journalDesignSystemScreen() => MaterialApp(
  theme: buildLightTheme(),
  home: Builder(
    builder: (context) {
      final headlineSmall = Theme.of(context).textTheme.headlineSmall;
      final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;
      return Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(JournalSpacing.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // `day_entries_screen.dart`'s shape: date eyebrow, entry-count
              // title, two fixed-size chevron actions.
              PageHeader(
                eyebrow: const Eyebrow('Wednesday, September 30'),
                title: Text('12 entries', style: headlineSmall),
                actions: [
                  _dayStepButton(Icons.chevron_left, 'Previous day'),
                  _dayStepButton(Icons.chevron_right, 'Next day'),
                ],
              ),
              const SizedBox(height: JournalSpacing.x5),
              // `experiment_results_screen.dart`'s shape: a fixed eyebrow,
              // a capitalised-topic title, one status-badge action.
              PageHeader(
                eyebrow: const Eyebrow('N-of-1 experiment'),
                title: Text('Fruit and vegetables', style: headlineSmall),
                actions: [
                  StatusBadge('Abandoned', contentColor: onSurfaceVariant),
                ],
              ),
              const SizedBox(height: JournalSpacing.x5),
              JournalCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Slept badly and woke up several times, then the '
                      'morning got better.',
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
                    // Stacked full-width, not side by side: this is
                    // `entry_detail_screen.dart`'s own conflict-resolution
                    // pair (`SizedBox(width: double.infinity, child:
                    // PillButton(...))` above a matching
                    // `SecondaryPillButton`), the only place in the app
                    // that puts these two buttons together.
                    SizedBox(
                      width: double.infinity,
                      child: PillButton(
                        onPressed: () {},
                        child: const Text(
                          'Abandon it and start this instead',
                        ),
                      ),
                    ),
                    const SizedBox(height: JournalSpacing.x2),
                    SizedBox(
                      width: double.infinity,
                      child: SecondaryPillButton(
                        onPressed: () {},
                        child: const Text('Keep mine (overwrite)'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: JournalSpacing.x5),
              EmptyState(
                icon: const Icon(Icons.insights),
                title: const Text('Not enough data yet'),
                supporting: const Text(
                  'Keep logging entries — once a topic and a feeling '
                  'repeat at least 3 times in the last 30 days, the '
                  'pattern shows up here.',
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
      );
    },
  ),
);

/// `lib/core/widgets/` and the app root.
final coreWidgets = ScreenArea(
  name: 'core widgets',
  cases: [
    ScreenCase(
      name: 'PremiumLock',
      source: 'core/widgets/premium_lock.dart',
      // Two variants, not one: `onUpgrade` is what tells `PremiumLock`'s two
      // rendered shapes apart (see the class doc comment), and #173 was
      // exactly this case's own blind spot -- the original version here
      // only built the `onUpgrade: null` shape, so the `OutlinedButton`
      // never rendered and its overflow (`Flexible` missing around it,
      // unlike the message `Text`'s `Expanded`) could not appear. Both
      // shapes are real: the buttonless one is every other call site's
      // message-only lock; the buttoned one is `digest_screen.dart`'s
      // locked branch, with its own real message and a real
      // `onUpgrade` callback.
      build: () => MaterialApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(JournalSpacing.x4),
                  child: PremiumLock(
                    message: 'Weekly digests are a Premium feature.',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(JournalSpacing.x4),
                  child: PremiumLock(
                    message: 'Weekly digests are a Premium feature.',
                    onUpgrade: () {},
                  ),
                ),
              ],
            ),
          ),
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
