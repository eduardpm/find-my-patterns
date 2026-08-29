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

  testWidgets('shows one shared axis with ticks at -1, 0 and +1', (
    tester,
  ) async {
    await tester.pumpWidget(app(WhenPanel(insights: buildWhenInsights())));

    expect(find.text('-1'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('+1'), findsOneWidget);
  });

  testWidgets(
    'a thin bucket draws no per-row text and no unlabelled decimal',
    (tester) async {
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

      // The old per-row apology is gone entirely -- only the single legend
      // at the bottom explains what a hollow marker means.
      expect(find.text('fewer than 3 entries'), findsNothing);
      expect(find.textContaining('-0.'), findsNothing);
      expect(find.textContaining('+0.'), findsNothing);
    },
  );

  testWidgets(
    'shows one legend line for every suppressed bucket, not one per row',
    (tester) async {
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
                buildBucket(
                  key: 'tuesday',
                  label: 'Tuesday',
                  sufficient: false,
                  averageValence: null,
                  entryCount: 2,
                ),
              ],
              timesOfDay: const [],
            ),
          ),
        ),
      );

      expect(
        find.text('○ fewer than 3 entries — not enough to show'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'shows no legend at all once every bucket is sufficient',
    (tester) async {
      await tester.pumpWidget(
        app(
          WhenPanel(
            insights: buildWhenInsights(
              weekdays: [buildBucket(key: 'monday', label: 'Monday')],
              timesOfDay: const [],
            ),
          ),
        ),
      );

      expect(find.textContaining('not enough to show'), findsNothing);
    },
  );

  testWidgets(
    'a sufficient bucket prints the labelled average and the entry count',
    (tester) async {
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
                  entryCount: 15,
                ),
              ],
              timesOfDay: const [],
            ),
          ),
        ),
      );

      expect(
        find.text('average valence +0.40 · 15 entries'),
        findsOneWidget,
      );
    },
  );

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
                averageValence: -0.27,
                entryCount: 15,
              ),
            ],
            timesOfDay: const [],
          ),
        ),
      ),
    );

    expect(
      find.text('average valence -0.27 · 15 entries'),
      findsOneWidget,
    );
  });

  testWidgets('pluralises "entry" for a single-entry sufficient bucket', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        WhenPanel(
          insights: buildWhenInsights(
            minBucketEntries: 1,
            weekdays: [
              buildBucket(
                key: 'monday',
                label: 'Monday',
                sufficient: true,
                averageValence: 0.1,
                entryCount: 1,
              ),
            ],
            timesOfDay: const [],
          ),
        ),
      ),
    );

    expect(find.text('average valence +0.10 · 1 entry'), findsOneWidget);
  });

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

  group('semantics', () {
    testWidgets(
      'labels a sufficient row with the weekday, the exact average and the '
      'entry count',
      (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          app(
            WhenPanel(
              insights: buildWhenInsights(
                weekdays: [
                  buildBucket(
                    key: 'friday',
                    label: 'Friday',
                    sufficient: true,
                    averageValence: -0.27,
                    entryCount: 15,
                  ),
                ],
                timesOfDay: const [],
              ),
            ),
          ),
        );

        expect(
          find.bySemanticsLabel(
            'Friday: average valence -0.27 from 15 entries',
          ),
          findsOneWidget,
        );
        handle.dispose();
      },
    );

    testWidgets(
      'labels a suppressed row with the weekday and the minimum, without a '
      'fabricated number',
      (tester) async {
        final handle = tester.ensureSemantics();
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

        expect(
          find.bySemanticsLabel(
            'Monday: fewer than 3 entries, not enough to show',
          ),
          findsOneWidget,
        );
        handle.dispose();
      },
    );

    testWidgets('folds the best-of-window status into the row label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        app(
          WhenPanel(
            insights: buildWhenInsights(
              weekdays: [
                buildBucket(
                  key: 'friday',
                  label: 'Friday',
                  sufficient: true,
                  averageValence: 0.4,
                  entryCount: 5,
                ),
              ],
              timesOfDay: const [],
              bestWeekday: 'friday',
            ),
          ),
        ),
      );

      expect(
        find.bySemanticsLabel(
          'Friday: average valence +0.40 from 5 entries, the best in this '
          'window',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('at 320dp width and 2x text scale', () {
    Widget narrow(Widget child) => MediaQuery(
      data: const MediaQueryData(
        size: Size(320, 900),
        textScaler: TextScaler.linear(2),
      ),
      child: app(child),
    );

    testWidgets('renders every row with no overflow', (tester) async {
      await tester.pumpWidget(
        narrow(
          WhenPanel(
            insights: buildWhenInsights(
              weekdays: [
                buildBucket(key: 'wednesday', label: 'Wednesday'),
                buildBucket(
                  key: 'thursday',
                  label: 'Thursday',
                  sufficient: false,
                  averageValence: null,
                  entryCount: 1,
                ),
              ],
              timesOfDay: [
                buildBucket(key: 'afternoon', label: 'Afternoon'),
              ],
              bestWeekday: 'wednesday',
              worstTimeOfDay: 'afternoon',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('By day of the week'), findsOneWidget);
      expect(find.text('By time of day'), findsOneWidget);
      expect(find.text('BEST'), findsOneWidget);
      expect(find.text('HARDEST'), findsOneWidget);
      expect(
        find.text('○ fewer than 3 entries — not enough to show'),
        findsOneWidget,
      );
    });

    testWidgets('renders the empty window state with no overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        narrow(WhenPanel(insights: buildWhenInsights(totalEntries: 0))),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
