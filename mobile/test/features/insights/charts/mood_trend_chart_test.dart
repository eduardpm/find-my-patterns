import 'dart:async';

import 'package:find_my_patterns/core/auth/tier.dart';
import 'package:find_my_patterns/core/auth/tier_controller.dart';
import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/diary/diary_providers.dart';
import 'package:find_my_patterns/core/diary/digest.dart';
import 'package:find_my_patterns/core/diary/insights_api.dart';
import 'package:find_my_patterns/core/diary/mood_series.dart';
import 'package:find_my_patterns/core/diary/pattern.dart';
import 'package:find_my_patterns/core/network/api_error.dart';
import 'package:find_my_patterns/core/theme/app_theme.dart';
import 'package:find_my_patterns/core/widgets/premium_lock.dart';
import 'package:find_my_patterns/features/insights/charts/mood_trend_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_tier.dart';

/// A double over [InsightsApi] whose only implemented method is [series] --
/// the mood-trend chart never calls the other four, so a call to any of
/// them here is itself a bug worth failing loudly on.
class _FakeInsightsApi implements InsightsApi {
  _FakeInsightsApi(this._respond);

  /// Answers each [series] call from the request it was given, so a test
  /// can return different data per call (e.g. across a period switch) or
  /// throw an [ApiError] to drive the error state.
  final FutureOr<MoodSeries> Function(CalendarDate from, CalendarDate to)
  _respond;

  /// Every `(from, to)` this fake was asked for, in call order.
  final List<({CalendarDate from, CalendarDate to})> seriesCalls = [];

  @override
  Future<MoodSeries> series({
    required CalendarDate from,
    required CalendarDate to,
  }) async {
    seriesCalls.add((from: from, to: to));
    return _respond(from, to);
  }

  @override
  Future<InsightsResult> insights() => throw UnimplementedError();

  @override
  Future<WhenInsights> whenInsights() => throw UnimplementedError();

  @override
  Future<void> acknowledgeWithdrawals() => throw UnimplementedError();

  @override
  Future<Digest> digest() => throw UnimplementedError();
}

void main() {
  const today = CalendarDate(2026, 8, 28);

  /// [tier] defaults to [Tier.premium] -- not [Tier.free] -- so every test
  /// in this file written before M-3 keeps exercising every range rather
  /// than a lock nothing told it to expect. The handful of tests below that
  /// are specifically about the free/locked path pass `Tier.free`
  /// explicitly.
  Widget buildChart(
    FutureOr<MoodSeries> Function(CalendarDate from, CalendarDate to) respond, {
    Tier tier = Tier.premium,
    int? historySpanDays,
  }) => ProviderScope(
    overrides: [
      insightsApiProvider.overrideWithValue(_FakeInsightsApi(respond)),
      moodTrendNowProvider.overrideWithValue(today.toDateTime()),
      tierProvider.overrideWith(() => FixedTierController(tier)),
    ],
    // See `Harness.noRetry`'s own doc: without this, a failed fetch below
    // would retry on a real backoff timer instead of staying in its error
    // state for the test to assert on.
    retry: (retryCount, error) => null,
    child: MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: MoodTrendChart(historySpanDays: historySpanDays),
        ),
      ),
    ),
  );

  /// Taps the chart canvas at [fraction] of its width -- 0 is [from], 1 is
  /// [to] -- the same mapping `_ChartCanvasState._scrubAt` uses to turn a
  /// drag position into a day offset.
  Future<void> scrubAt(WidgetTester tester, double fraction) async {
    final area = find.byKey(const Key('moodTrendScrubArea'));
    final topLeft = tester.getTopLeft(area);
    final size = tester.getSize(area);
    await tester.tapAt(
      topLeft + Offset(size.width * fraction, size.height / 2),
    );
    await tester.pump();
  }

  group('loading, error and empty states', () {
    testWidgets('shows neither the chart nor an error before the first '
        'response lands', (tester) async {
      await tester.pumpWidget(
        buildChart((from, to) => Completer<MoodSeries>().future),
      );
      await tester.pump();

      expect(find.byKey(const Key('moodTrendScrubArea')), findsNothing);
      expect(find.textContaining('Not enough days'), findsNothing);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('an error offers Retry, and Retry re-fetches', (
      tester,
    ) async {
      var calls = 0;
      await tester.pumpWidget(
        buildChart((from, to) {
          calls++;
          if (calls == 1) throw const NetworkFailure('boom');
          return const MoodSeries([]);
        }),
      );
      await tester.pumpAndSettle();

      expect(find.text('Could not reach the server.'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(calls, 2);
      expect(find.text('Could not reach the server.'), findsNothing);
      expect(find.textContaining('Not enough days'), findsOneWidget);
    });

    testWidgets('a Retry that fails again keeps the error state up', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildChart((from, to) => throw const Unauthorized()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Please sign in again.'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      // Still the same failure, not a stuck spinner or a blank card.
      expect(find.text('Please sign in again.'), findsOneWidget);
    });

    testWidgets('an HttpFailure surfaces the server\'s own message', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildChart(
          (from, to) => throw const HttpFailure('server exploded', 500),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('server exploded'), findsOneWidget);
    });

    testWidgets('fewer than 3 scored days in range reads as "not enough '
        'days yet", whether the range is empty or every score is null', (
      tester,
    ) async {
      // Empty range.
      await tester.pumpWidget(buildChart((from, to) => const MoodSeries([])));
      await tester.pumpAndSettle();
      expect(
        find.text('Not enough days yet — keep writing'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('moodTrendScrubArea')), findsNothing);

      // Entries logged, but never a confirmed feeling.
      await tester.pumpWidget(
        buildChart(
          (from, to) => MoodSeries([
            MoodSeriesPoint(from, null, 2, 0),
            MoodSeriesPoint(from.addDays(1), null, 1, 0),
          ]),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Not enough days yet — keep writing'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('moodTrendScrubArea')), findsNothing);
    });
  });

  group('rendered data', () {
    // Five consecutive days at the end of the 30-day window -- no gaps
    // between them, and every one carries a score.
    final densePoints = [
      const MoodSeriesPoint(CalendarDate(2026, 8, 24), 0.2, 3, 3),
      const MoodSeriesPoint(CalendarDate(2026, 8, 25), 0.4, 4, 4),
      const MoodSeriesPoint(CalendarDate(2026, 8, 26), -0.1, 2, 2),
      const MoodSeriesPoint(CalendarDate(2026, 8, 27), 0.6, 5, 5),
      const MoodSeriesPoint(CalendarDate(2026, 8, 28), -0.3, 1, 1),
    ];

    testWidgets('dense data renders the chart and a matching Semantics '
        'summary', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        buildChart((from, to) => MoodSeries(densePoints)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('moodTrendScrubArea')), findsOneWidget);
      // average (0.2+0.4-0.1+0.6-0.3)/5 = 0.16 -> "0.2"; lowest -0.3 on the
      // 28th, highest 0.6 on the 27th; 3+4+2+5+1 = 15 entries.
      expect(
        find.bySemanticsLabel(
          'Mood over the last 30 days: average 0.2, lowest August 28, '
          'highest August 27, based on 15 entries.',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets(
      'sparse data with gaps: the summary and the scrub tooltip both skip '
      'the null-score day for the score itself but still count its entry',
      (tester) async {
        final handle = tester.ensureSemantics();

        // Real gaps between points, plus one logged-but-unconfirmed day
        // (2026-08-15) in between two scored ones.
        final points = [
          const MoodSeriesPoint(CalendarDate(2026, 8, 1), 0.5, 2, 2),
          const MoodSeriesPoint(CalendarDate(2026, 8, 15), null, 1, 0),
          const MoodSeriesPoint(CalendarDate(2026, 8, 20), -0.8, 3, 3),
          const MoodSeriesPoint(CalendarDate(2026, 8, 28), 0.1, 1, 1),
        ];
        await tester.pumpWidget(buildChart((from, to) => MoodSeries(points)));
        await tester.pumpAndSettle();

        // average (0.5-0.8+0.1)/3 = -0.0667 -> "-0.1"; lowest -0.8 on the
        // 20th, highest 0.5 on the 1st; 2+1+3+1 = 7 entries total,
        // including the null-score day's.
        expect(
          find.bySemanticsLabel(
            'Mood over the last 30 days: average -0.1, lowest August 20, '
            'highest August 1, based on 7 entries.',
          ),
          findsOneWidget,
        );

        // Day offsets from `from` (2026-07-30): Aug 15 is 16, Aug 20 is 21,
        // span is 29 -- scrubbing at 16/29 and 21/29 lands nearest to each.
        await scrubAt(tester, 16 / 29);
        expect(
          find.text('August 15, no confirmed feelings, 1 entries'),
          findsOneWidget,
        );

        await scrubAt(tester, 21 / 29);
        expect(find.text('August 20, score -0.80, 3 entries'), findsOneWidget);
        handle.dispose();
      },
    );

    testWidgets('a drag also drives the scrub tooltip, updating as it moves', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildChart((from, to) => MoodSeries(densePoints)),
      );
      await tester.pumpAndSettle();

      final area = find.byKey(const Key('moodTrendScrubArea'));
      final topLeft = tester.getTopLeft(area);
      final size = tester.getSize(area);
      Offset atFraction(double fraction) =>
          topLeft + Offset(size.width * fraction, size.height / 2);

      // Day offsets from `from` (2026-07-30): Aug 24 is 25, Aug 28 is 29 --
      // dragging from the left of that span to its right end. Two separate
      // `moveTo` calls: the first is what wins the tap-vs-pan arena and
      // fires `onPanStart`; the second is a genuine update on top of an
      // already-recognised pan, which is what fires `onPanUpdate`.
      final gesture = await tester.startGesture(atFraction(25 / 29));
      await gesture.moveTo(atFraction(27 / 29));
      await gesture.moveTo(atFraction(29 / 29));
      await gesture.up();
      await tester.pump();

      expect(
        find.text('August 28, score -0.30, 1 entries'),
        findsOneWidget,
      );
    });
  });

  testWidgets(
    'the period switcher refetches for the new range and re-renders',
    (tester) async {
      final handle = tester.ensureSemantics();

      final api = _FakeInsightsApi((from, to) {
        if (to.addDays(-29) == from) {
          // 30-day request.
          return const MoodSeries([
            MoodSeriesPoint(CalendarDate(2026, 8, 26), 0.0, 1, 1),
            MoodSeriesPoint(CalendarDate(2026, 8, 27), 0.0, 1, 1),
            MoodSeriesPoint(CalendarDate(2026, 8, 28), 0.0, 1, 1),
          ]);
        }
        // The 90-day request.
        return const MoodSeries([
          MoodSeriesPoint(CalendarDate(2026, 8, 1), 1.0, 2, 2),
          MoodSeriesPoint(CalendarDate(2026, 8, 2), 1.0, 2, 2),
          MoodSeriesPoint(CalendarDate(2026, 8, 3), 1.0, 2, 2),
        ]);
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            insightsApiProvider.overrideWithValue(api),
            moodTrendNowProvider.overrideWithValue(today.toDateTime()),
            tierProvider.overrideWith(
              () => FixedTierController(Tier.premium),
            ),
          ],
          retry: (retryCount, error) => null,
          child: MaterialApp(
            theme: buildLightTheme(),
            home: const Scaffold(
              body: SingleChildScrollView(child: MoodTrendChart()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel(RegExp('the last 30 days.*based on 3 entries')),
        findsOneWidget,
      );
      expect(api.seriesCalls, hasLength(1));

      await tester.tap(find.text('90 days'));
      await tester.pumpAndSettle();

      expect(api.seriesCalls, hasLength(2));
      expect(api.seriesCalls.last.from, today.addDays(-89));
      expect(api.seriesCalls.last.to, today);
      expect(
        find.bySemanticsLabel(RegExp('the last 90 days.*based on 6 entries')),
        findsOneWidget,
      );
      handle.dispose();
    },
  );

  group('free tier (M-3, #48)', () {
    testWidgets('the default 30-day range is unlocked and unaffected', (
      tester,
    ) async {
      final api = _FakeInsightsApi(
        (from, to) => const MoodSeries([
          MoodSeriesPoint(CalendarDate(2026, 8, 26), 0.0, 1, 1),
          MoodSeriesPoint(CalendarDate(2026, 8, 27), 0.0, 1, 1),
          MoodSeriesPoint(CalendarDate(2026, 8, 28), 0.0, 1, 1),
        ]),
      );
      await tester.pumpWidget(
        buildChart(
          (from, to) => api.series(from: from, to: to),
          tier: Tier.free,
        ),
      );
      await tester.pumpAndSettle();

      expect(api.seriesCalls, hasLength(1));
      expect(find.byType(PremiumLock), findsNothing);
      expect(find.text('90 days'), findsOneWidget);
    });

    testWidgets(
      'selecting 90 days shows the lock, naming the real history span, '
      'instead of whatever the (would-be-422) fetch answers',
      (tester) async {
        final api = _FakeInsightsApi(
          (from, to) => const MoodSeries([
            MoodSeriesPoint(CalendarDate(2026, 8, 26), 0.0, 1, 1),
          ]),
        );
        await tester.pumpWidget(
          buildChart(
            (from, to) => api.series(from: from, to: to),
            tier: Tier.free,
            historySpanDays: 425,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('90 days'));
        await tester.pumpAndSettle();

        expect(find.byType(PremiumLock), findsOneWidget);
        expect(
          find.text(
            'Last 30 days shown. Patterns across your full 14 months — '
            'Premium.',
          ),
          findsOneWidget,
        );
        // No chart, no error, no skeleton underneath the lock -- see
        // `MoodTrendController.build`'s own doc comment for why this
        // client still lets the (real-backend-422) request go out rather
        // than gating the fetch itself: whatever it answers is simply
        // never rendered while the period stays locked for this tier.
        expect(find.byKey(const Key('moodTrendScrubArea')), findsNothing);
        expect(find.textContaining('Not enough days'), findsNothing);
      },
    );

    testWidgets('selecting Year locks the chart with no span to name yet', (
      tester,
    ) async {
      final api = _FakeInsightsApi(
        (from, to) => const MoodSeries([
          MoodSeriesPoint(CalendarDate(2026, 8, 26), 0.0, 1, 1),
        ]),
      );
      await tester.pumpWidget(
        buildChart(
          (from, to) => api.series(from: from, to: to),
          tier: Tier.free,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Year'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Last 30 days shown. Patterns across your full history — Premium.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('tapping Upgrade on the locked chart calls onUpgrade', (
      tester,
    ) async {
      var upgradeTapped = false;
      final api = _FakeInsightsApi(
        (from, to) => const MoodSeries([
          MoodSeriesPoint(CalendarDate(2026, 8, 26), 0.0, 1, 1),
        ]),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            insightsApiProvider.overrideWithValue(api),
            moodTrendNowProvider.overrideWithValue(today.toDateTime()),
            tierProvider.overrideWith(() => FixedTierController(Tier.free)),
          ],
          retry: (retryCount, error) => null,
          child: MaterialApp(
            theme: buildLightTheme(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: MoodTrendChart(
                  onUpgrade: () => upgradeTapped = true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('90 days'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upgrade'));

      expect(upgradeTapped, isTrue);
    });
  });
}
