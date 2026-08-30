import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/diary/digest.dart';
import 'package:find_my_patterns/core/diary/feeling.dart';
import 'package:find_my_patterns/core/diary/pattern.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/core/theme/app_theme.dart';
import 'package:find_my_patterns/core/theme/journal_metrics.dart';
import 'package:find_my_patterns/core/widgets/journal.dart';
import 'package:find_my_patterns/features/insights/charts/mood_trend_chart.dart';
import 'package:find_my_patterns/features/insights/digest_screen.dart';
import 'package:find_my_patterns/features/insights/weak_signal_row.dart';
import 'package:find_my_patterns/features/insights/withdrawal_notice.dart';
import 'package:flutter/material.dart';

import '../../features/insights/json_fixtures.dart';
import '../fake_http.dart';
import '../harness.dart';
import '../screen_registry.dart';

/// The feeling catalog [_weakSignalPattern] resolves its `feeling_key`
/// through -- one long-labelled entry is enough, since the row shows only
/// this one pattern's own feeling.
const _feelingCatalog = FeelingCatalog([
  Feeling('overstimulated', 'Overstimulated', Valence.negative, 'tense'),
]);

/// An inverse pattern with a multi-word topic and a long single-word
/// feeling label -- the shape that stresses `_captionFor`'s single-line
/// caption hardest.
Pattern _weakSignalPattern() => patternFromJson(
  patternJson(
    id: 'weak-1',
    kind: 'inverse',
    topic: 'unstructured evening screen time',
    feeling: 'overstimulated',
  ),
  _feelingCatalog,
);

/// A withdrawal with a long, multi-word topic, two-digit counts and a
/// full-sentence reason -- the shape `ACCESSIBILITY.md` itself asks for:
/// "still 8 occurrences, but the association is no longer stronger than
/// your usual rate by the minimum of 1.5x."
Withdrawal _withdrawal() => withdrawalFromJson(
  withdrawalJson(
    topic: 'long unplanned afternoon meetings',
    feeling: 'stressed',
    kind: 'inverse',
    previousCount: 24,
    newCount: 11,
    reason: 'below_lift',
    detailText:
        'Without long unplanned afternoon meetings, stressed was still 11 '
        'of 24 occurrences, but the association is no longer stronger than '
        'your usual rate by the minimum of 1.5x, so this pattern no longer '
        'clears the confidence bar.',
    isNew: true,
  ),
);

/// The mood-trend chart's own `GET /insights/series` reply: five days, four
/// scored -- at least three scored days are required to reach the real
/// chart with its "+1"/"0"/"-1" axis rather than the empty state -- one with
/// a two-digit entry count and one deliberately unscored, the shape a real
/// week produces.
Map<String, Object?> _seriesReply() => seriesJson(
  points: [
    seriesPointJson(date: '2026-07-28', score: 0.4, entryCount: 2),
    seriesPointJson(date: '2026-07-29', score: -0.6, entryCount: 12),
    seriesPointJson(
      date: '2026-07-30',
      score: null,
      entryCount: 1,
      confirmedFeelingCount: 0,
    ),
    seriesPointJson(date: '2026-07-31', score: 0.1, entryCount: 3),
    seriesPointJson(date: '2026-08-01', score: 0.9, entryCount: 4),
  ],
);

/// A fully-populated digest -- all three parts present, a two-digit entry
/// count, and sentences as long as a real week's worth of evidence
/// produces.
Digest _digest() => Digest(
  false,
  14,
  const CalendarDate(2026, 8, 24),
  const DigestHighlight(
    'pattern-1',
    PatternKind.forward,
    'long uninterrupted focus blocks',
    Feeling('calm', 'Calm', Valence.positive, 'uplifted'),
    12,
    3.4,
    'Long uninterrupted focus blocks showed up with calm in 12 of your 14 '
        'entries this week, continuing a pattern that has now held for the '
        'last 30 days.',
  ),
  const Recommendation(
    'long uninterrupted focus blocks',
    'Keep scheduling long uninterrupted focus blocks',
    'On days with long uninterrupted focus blocks, calm is 3.4x more '
        "likely (12 of 14 with vs 4 of 20 without). Keep doing this -- here's "
        'the evidence.',
    'pattern-1',
  ),
  const DigestMovement(
    Feeling('calm', 'Calm', Valence.positive, 'uplifted'),
    14,
    9,
    DigestMovementDirection.up,
    'Calm showed up in 14 entries this week, up from 9 last week -- the '
    'fourth week in a row it has increased.',
  ),
);

/// `lib/features/insights/`.
final insights = ScreenArea(
  name: 'insights',
  cases: [
    ScreenCase(
      name: 'MoodTrendChart',
      source: 'features/insights/charts/mood_trend_chart.dart',
      build: () =>
          Harness(
            settings: const AppSettings(
              backend: BackendAddress(host: '10.0.2.2'),
            ),
            adapter: FakeHttpAdapter([FakeReply(200, body: _seriesReply())]),
          ).scope(
            MaterialApp(
              theme: buildLightTheme(),
              home: Scaffold(
                body: Padding(
                  // Matches `insights_screen.dart`'s own ListView padding --
                  // the only horizontal constraint the real screen adds around
                  // this chart, which wraps itself in its own `JournalCard`.
                  padding: const EdgeInsets.symmetric(
                    horizontal: JournalSpacing.x4,
                  ),
                  child: const MoodTrendChart(),
                ),
              ),
            ),
          ),
      // `_PeriodSwitcher`'s three-segment `SegmentedButton` ("30 days",
      // "90 days", "Year") cannot all share a 320-360dp line at 1.3x/2x --
      // "Year" needs 112.0px but is given 64.0px at 320dp/2x (72.8px given
      // 58.4px at 320dp/1.3x; 360dp is only 1.1px short at 1.3x, 34.7px
      // short at 2x). Same family as #169's HTTP/HTTPS switcher: a control
      // decision (a different period picker), not a mechanical fix.
      // Consolidated into #169, which covers all three SegmentedButton call
      // sites: the fix is one shared segmented-choice widget, not a patch
      // per screen. Remove this entry when that lands.
      knownFailures: const {
        '320x1.3': '#169',
        '320x2.0': '#169',
        '360x1.3': '#169',
        '360x2.0': '#169',
      },
    ),
    ScreenCase(
      name: 'WithdrawalNotice',
      source: 'features/insights/withdrawal_notice.dart',
      build: () => MaterialApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: Padding(
            // Matches `_WithdrawalsSection`'s own `JournalCard` plus the
            // screen's ListView padding -- the real width this notice is
            // ever given (`insights_screen.dart`).
            padding: const EdgeInsets.symmetric(
              horizontal: JournalSpacing.x4,
            ),
            child: JournalCard(
              child: WithdrawalNotice(withdrawal: _withdrawal()),
            ),
          ),
        ),
      ),
    ),
    ScreenCase(
      name: 'WeakSignalRow',
      source: 'features/insights/weak_signal_row.dart',
      build: () => MaterialApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: Padding(
            // Matches the screen's own ListView padding -- `WeakSignalRow`
            // is not wrapped in its own `JournalCard` on the real screen.
            padding: const EdgeInsets.symmetric(
              horizontal: JournalSpacing.x4,
            ),
            child: WeakSignalRow(
              pattern: _weakSignalPattern(),
              constants: EngineConstants.placeholder,
              onOpenEntry: (entryId, entryDate) {},
            ),
          ),
        ),
      ),
    ),
    ScreenCase(
      name: 'DigestScreen',
      source: 'features/insights/digest_screen.dart',
      build: () => MaterialApp(
        theme: buildLightTheme(),
        // Two states, stacked: `DigestScreen` renders entirely different
        // content for a real digest and for the `null`/locked one (M-3,
        // #48), and `screen_layout_matrix_test.dart`'s own "no surface is
        // registered by two areas" guard allows one `ScreenCase` per
        // `source` -- so both are exercised inside this one case, each
        // given half the matrix's tall viewport, rather than as two cases
        // that would collide on the same source.
        home: Column(
          children: [
            Expanded(child: DigestScreen(digest: _digest())),
            const Expanded(child: DigestScreen(digest: null)),
          ],
        ),
      ),
      // The locked (`digest: null`) branch throws a `RenderFlex overflowed
      // by 8.0 pixels on the right` at 320dp/2x -- traced to
      // `core/widgets/premium_lock.dart`'s own `Row`, which never wraps its
      // `OutlinedButton('Upgrade')` in a `Flexible` the way it wraps the
      // message `Text` in `Expanded`. `DigestScreen`'s locked branch is the
      // only call site that passes a non-null `onUpgrade`, which is why the
      // existing dedicated `PremiumLock` `ScreenCase`
      // (`test/support/screens/core_widgets.dart`) never sees it -- the
      // same #163 shape, a passing case that never exercises the real call
      // shape. `premium_lock.dart` is a shared core widget outside this
      // area's ownership, so this is reported rather than fixed here. #173.
      knownFailures: const {'320x2.0': '#173'},
    ),
  ],
  unswept: const {},
);
