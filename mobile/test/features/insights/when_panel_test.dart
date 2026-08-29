import 'package:find_my_patterns/core/theme/app_theme.dart';
import 'package:find_my_patterns/features/insights/when_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  Widget app(Widget child) => MaterialApp(
    theme: buildLightTheme(),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  testWidgets('when there is nothing in the window, says so and stops', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        WhenPanel(insights: buildWhenInsights(totalEntries: 0, windowDays: 30)),
      ),
    );

    expect(
      find.text(
        'Nothing in the last 30 days yet — this fills in as you write.',
      ),
      findsOneWidget,
    );
    expect(find.text('By day of the week'), findsNothing);
  });

  testWidgets(
    'summarises the window, pluralising "entries" for more than one',
    (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          WhenPanel(
            insights: buildWhenInsights(totalEntries: 12, windowDays: 30),
          ),
        ),
      );

      expect(
        find.text(
          'Across the 12 entries you confirmed in the last 30 days. These are '
          'times, not causes.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('uses the singular "entry" for exactly one', (tester) async {
    await tester.pumpWidget(
      app(
        WhenPanel(insights: buildWhenInsights(totalEntries: 1, windowDays: 30)),
      ),
    );

    expect(
      find.text(
        'Across the 1 entry you confirmed in the last 30 days. These are '
        'times, not causes.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows both group headings once there is data', (tester) async {
    await tester.pumpWidget(app(WhenPanel(insights: buildWhenInsights())));

    expect(find.text('By day of the week'), findsOneWidget);
    expect(find.text('By time of day'), findsOneWidget);
  });

  testWidgets('a thin bucket says so instead of drawing a marker at zero', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        WhenPanel(
          insights: buildWhenInsights(
            minBucketEntries: 3,
            weekdays: [
              buildBucket(
                key: 'monday',
                label: 'Monday',
                sufficient: false,
                averageValence: null,
                entryCount: 1,
              ),
            ],
            timesOfDay: const [],
          ),
        ),
      ),
    );

    expect(find.text('fewer than 3 entries'), findsOneWidget);
  });

  testWidgets('a sufficient bucket prints the signed average', (tester) async {
    await tester.pumpWidget(
      app(
        WhenPanel(
          insights: buildWhenInsights(
            weekdays: [
              buildBucket(
                key: 'monday',
                label: 'Monday',
                sufficient: true,
                averageValence: 0.4,
              ),
            ],
            timesOfDay: const [],
          ),
        ),
      ),
    );

    expect(find.text('+0.40'), findsOneWidget);
    expect(find.text('fewer than 3 entries'), findsNothing);
  });

  testWidgets('a negative average still prints with its sign', (tester) async {
    await tester.pumpWidget(
      app(
        WhenPanel(
          insights: buildWhenInsights(
            weekdays: [
              buildBucket(
                key: 'monday',
                label: 'Monday',
                sufficient: true,
                averageValence: -0.4,
              ),
            ],
            timesOfDay: const [],
          ),
        ),
      ),
    );

    expect(find.text('-0.40'), findsOneWidget);
  });

  testWidgets(
    'shows the entry count for every bucket regardless of sufficiency',
    (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          WhenPanel(
            insights: buildWhenInsights(
              weekdays: [
                buildBucket(key: 'monday', label: 'Monday', entryCount: 7),
              ],
              timesOfDay: const [],
            ),
          ),
        ),
      );

      expect(find.text('7'), findsOneWidget);
    },
  );

  testWidgets('marks the best and worst bucket with a badge', (tester) async {
    await tester.pumpWidget(
      app(
        WhenPanel(
          insights: buildWhenInsights(
            weekdays: [
              buildBucket(key: 'monday', label: 'Monday'),
              buildBucket(key: 'friday', label: 'Friday'),
            ],
            timesOfDay: const [],
            bestWeekday: 'friday',
            worstWeekday: 'monday',
          ),
        ),
      ),
    );

    expect(find.text('BEST'), findsOneWidget);
    expect(find.text('HARDEST'), findsOneWidget);
  });
}
