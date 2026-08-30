import 'package:find_my_patterns/core/theme/app_theme.dart';
import 'package:find_my_patterns/core/theme/journal_palette.dart';
import 'package:find_my_patterns/core/widgets/journal_dashed_border.dart';
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

  group('dynamic type (#155a)', () {
    // 320/360dp x 1.0/1.3/2.0 -- the matrix `mobile/ACCESSIBILITY.md` §3
    // asks every screen to clear, 1.0 included: #150 found a real overflow
    // that reproduced identically at 1.0x, so a scale-only sweep would have
    // missed it. `.copyWith` on the ambient `MediaQuery`, never a bare
    // `MediaQueryData`, per the same doc's pitfall -- the latter would
    // discard every other ambient field outright.
    Widget narrow(
      Widget child, {
      required double width,
      required double textScale,
    }) => Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          size: Size(width, 1400),
          textScaler: TextScaler.linear(textScale),
        ),
        child: app(child),
      ),
    );

    for (final width in [320.0, 360.0]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets(
          '${width.toInt()}dp / ${scale}x text scale: every row family, '
          'the heat strip and both badges render with no overflow',
          (tester) async {
            await tester.pumpWidget(
              narrow(
                WhenPanel(
                  insights: buildWhenInsights(
                    weekdays: [
                      // "Wednesday" -- the longest full weekday name this
                      // panel ever renders, in the label column #155a's
                      // split brief flagged as fixed-width (104dp,
                      // `_labelColumnWidth`).
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
                    // Exercises the heat strip's own row (`:569`/`:678`)
                    // and its `DecoratedBox`/dashed cells (`:629`) at the
                    // same time as the row families above.
                    hourly: buildHourlyBuckets(),
                  ),
                ),
                width: width,
                textScale: scale,
              ),
            );
            await tester.pumpAndSettle();

            expect(tester.takeException(), isNull);
            // Positive assertions the content actually rendered, paired
            // with the exception check above (ACCESSIBILITY.md §3):
            // `takeException` alone passes on a tree that painted nothing.
            expect(find.text('By day of the week'), findsOneWidget);
            expect(find.text('By time of day'), findsOneWidget);
            expect(find.text('Wednesday'), findsOneWidget);
            expect(find.text('BEST'), findsOneWidget);
            expect(find.text('HARDEST'), findsOneWidget);
            expect(
              find.text('○ fewer than 3 entries — not enough to show'),
              findsOneWidget,
            );
            expect(find.text('By hour'), findsOneWidget);
          },
        );

        testWidgets(
          '${width.toInt()}dp / ${scale}x text scale: the empty-window '
          'state renders with no overflow',
          (tester) async {
            await tester.pumpWidget(
              narrow(
                WhenPanel(insights: buildWhenInsights(totalEntries: 0)),
                width: width,
                textScale: scale,
              ),
            );
            await tester.pumpAndSettle();

            expect(tester.takeException(), isNull);
            expect(
              find.textContaining('this fills in as you write'),
              findsOneWidget,
            );
          },
        );
      }
    }
  });

  group('heat strip (CH-5)', () {
    testWidgets('does not render when there is no hourly data', (
      tester,
    ) async {
      await tester.pumpWidget(app(WhenPanel(insights: buildWhenInsights())));

      expect(find.text('By hour'), findsNothing);
    });

    testWidgets('renders "By hour" and all twelve cells once there is data', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          WhenPanel(
            insights: buildWhenInsights(hourly: buildHourlyBuckets()),
          ),
        ),
      );

      expect(find.text('By hour'), findsOneWidget);
      for (final key in [
        '00',
        '02',
        '04',
        '06',
        '08',
        '10',
        '12',
        '14',
        '16',
        '18',
        '20',
        '22',
      ]) {
        expect(find.byKey(Key('hourCell-$key')), findsOneWidget);
      }
    });

    testWidgets('shows hour ticks only at 0, 6, 12 and 18', (tester) async {
      await tester.pumpWidget(
        app(
          WhenPanel(
            insights: buildWhenInsights(hourly: buildHourlyBuckets()),
          ),
        ),
      );

      // '0' also appears as the shared −1…+1 axis's zero tick above the
      // weekday/time-of-day rows, so this one text is shared by two ticks
      // rather than unique to the strip.
      expect(find.text('0'), findsNWidgets(2));
      expect(find.text('6'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('18'), findsOneWidget);
      for (final absent in ['2', '4', '8', '10', '14', '16', '20', '22']) {
        expect(find.text(absent), findsNothing);
      }
    });

    testWidgets('colours a sufficient cell using the shared valence ramp', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          WhenPanel(
            insights: buildWhenInsights(
              hourly: buildHourlyBuckets(
                overrides: {
                  '18': buildBucket(
                    key: '18',
                    label: '18:00–20:00',
                    sufficient: true,
                    averageValence: 0.4,
                    entryCount: 7,
                  ),
                },
              ),
            ),
          ),
        ),
      );

      final decoratedBox = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(const Key('hourCell-18')),
          matching: find.byType(DecoratedBox),
        ),
      );
      final decoration = decoratedBox.decoration as BoxDecoration;
      final expected = JournalPalette.defaultPalette
          .colors(dark: false)
          .feelings
          .colorForScore(0.4);
      expect(decoration.color, expected);
      expect(
        find.descendant(
          of: find.byKey(const Key('hourCell-18')),
          matching: find.byType(DashedBorder),
        ),
        findsNothing,
      );
    });

    testWidgets('draws a suppressed cell hollow and dashed, not coloured', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          WhenPanel(
            insights: buildWhenInsights(
              hourly: buildHourlyBuckets(
                overrides: {
                  '22': buildBucket(
                    key: '22',
                    label: '22:00–00:00',
                    sufficient: false,
                    averageValence: null,
                    entryCount: 1,
                  ),
                },
              ),
            ),
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byKey(const Key('hourCell-22')),
          matching: find.byType(DashedBorder),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('hourCell-22')),
          matching: find.byType(DecoratedBox),
        ),
        findsNothing,
      );
    });

    testWidgets(
      'a suppressed hour cell uses the chart\'s one shared legend, not a '
      'second one',
      (tester) async {
        await tester.pumpWidget(
          app(
            WhenPanel(
              insights: buildWhenInsights(
                weekdays: [buildBucket(key: 'monday', label: 'Monday')],
                timesOfDay: [buildBucket(key: 'evening', label: 'Evening')],
                hourly: buildHourlyBuckets(
                  overrides: {
                    '22': buildBucket(
                      key: '22',
                      label: '22:00–00:00',
                      sufficient: false,
                      averageValence: null,
                      entryCount: 1,
                    ),
                  },
                ),
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

    group('tap and long-press detail', () {
      testWidgets(
        'tapping a cell shows its detail line; tapping again hides it',
        (
          tester,
        ) async {
          await tester.pumpWidget(
            app(
              WhenPanel(
                insights: buildWhenInsights(
                  hourly: buildHourlyBuckets(
                    overrides: {
                      '18': buildBucket(
                        key: '18',
                        label: '18:00–20:00',
                        sufficient: true,
                        averageValence: -0.27,
                        entryCount: 15,
                      ),
                    },
                  ),
                ),
              ),
            ),
          );

          const detail = '18:00–20:00 · average valence -0.27 · 15 entries';
          expect(find.text(detail), findsNothing);

          await tester.tap(find.byKey(const Key('hourCell-18')));
          await tester.pump();
          expect(find.text(detail), findsOneWidget);

          await tester.tap(find.byKey(const Key('hourCell-18')));
          await tester.pump();
          expect(find.text(detail), findsNothing);
        },
      );

      testWidgets('tapping a different cell swaps the detail line', (
        tester,
      ) async {
        await tester.pumpWidget(
          app(
            WhenPanel(
              insights: buildWhenInsights(
                hourly: buildHourlyBuckets(
                  overrides: {
                    '18': buildBucket(
                      key: '18',
                      label: '18:00–20:00',
                      sufficient: true,
                      averageValence: -0.27,
                      entryCount: 15,
                    ),
                    '08': buildBucket(
                      key: '08',
                      label: '08:00–10:00',
                      sufficient: true,
                      averageValence: 0.5,
                      entryCount: 4,
                    ),
                  },
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byKey(const Key('hourCell-18')));
        await tester.pump();
        expect(
          find.text('18:00–20:00 · average valence -0.27 · 15 entries'),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('hourCell-08')));
        await tester.pump();
        expect(
          find.text('18:00–20:00 · average valence -0.27 · 15 entries'),
          findsNothing,
        );
        expect(
          find.text('08:00–10:00 · average valence +0.50 · 4 entries'),
          findsOneWidget,
        );
      });

      testWidgets(
        'a suppressed cell reuses the legend\'s phrasing when tapped',
        (tester) async {
          await tester.pumpWidget(
            app(
              WhenPanel(
                insights: buildWhenInsights(
                  hourly: buildHourlyBuckets(
                    overrides: {
                      '10': buildBucket(
                        key: '10',
                        label: '10:00–12:00',
                        sufficient: false,
                        averageValence: null,
                        entryCount: 1,
                      ),
                    },
                  ),
                ),
              ),
            ),
          );

          await tester.tap(find.byKey(const Key('hourCell-10')));
          await tester.pump();
          expect(
            find.text(
              '10:00–12:00 · fewer than 3 entries — not enough to show',
            ),
            findsOneWidget,
          );
        },
      );

      testWidgets(
        'a long press shows the detail line while held and hides it on release',
        (tester) async {
          await tester.pumpWidget(
            app(
              WhenPanel(
                insights: buildWhenInsights(
                  hourly: buildHourlyBuckets(
                    overrides: {
                      '18': buildBucket(
                        key: '18',
                        label: '18:00–20:00',
                        sufficient: true,
                        averageValence: -0.27,
                        entryCount: 15,
                      ),
                    },
                  ),
                ),
              ),
            ),
          );

          const detail = '18:00–20:00 · average valence -0.27 · 15 entries';
          final gesture = await tester.startGesture(
            tester.getCenter(find.byKey(const Key('hourCell-18'))),
          );
          await tester.pump(const Duration(milliseconds: 600));
          expect(find.text(detail), findsOneWidget);

          await gesture.up();
          await tester.pump();
          expect(find.text(detail), findsNothing);
        },
      );
    });

    group('semantics', () {
      testWidgets(
        'summarises the busiest time of day and the lowest hour, from '
        'backend-computed fields alone',
        (tester) async {
          final handle = tester.ensureSemantics();
          await tester.pumpWidget(
            app(
              WhenPanel(
                insights: buildWhenInsights(
                  timesOfDay: [
                    buildBucket(
                      key: 'morning',
                      label: 'Morning',
                      entryCount: 2,
                    ),
                    buildBucket(
                      key: 'evening',
                      label: 'Evening',
                      entryCount: 15,
                    ),
                  ],
                  busiestTimeOfDay: 'evening',
                  hourly: buildHourlyBuckets(
                    overrides: {
                      '22': buildBucket(
                        key: '22',
                        label: '22:00–00:00',
                        sufficient: true,
                        averageValence: -0.6,
                        entryCount: 15,
                      ),
                    },
                  ),
                  worstHour: '22',
                ),
              ),
            ),
          );

          expect(
            find.bySemanticsLabel(
              'By hour: entries cluster in the evening; lowest around '
              '22:00 (from 15 entries).',
            ),
            findsOneWidget,
          );
          handle.dispose();
        },
      );

      testWidgets(
        'falls back to a plain sentence when neither cluster nor lowest is '
        'available',
        (tester) async {
          final handle = tester.ensureSemantics();
          await tester.pumpWidget(
            app(
              WhenPanel(
                insights: buildWhenInsights(hourly: buildHourlyBuckets()),
              ),
            ),
          );

          expect(
            find.bySemanticsLabel(
              'By hour: not enough entries yet to show a pattern.',
            ),
            findsOneWidget,
          );
          handle.dispose();
        },
      );
    });

    testWidgets(
      'renders without error in every palette, light and dark',
      (tester) async {
        for (final palette in JournalPalette.values) {
          for (final dark in [false, true]) {
            await tester.pumpWidget(
              MaterialApp(
                theme: dark
                    ? buildDarkTheme(palette: palette)
                    : buildLightTheme(palette: palette),
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: WhenPanel(
                      insights: buildWhenInsights(
                        hourly: buildHourlyBuckets(
                          overrides: {
                            '22': buildBucket(
                              key: '22',
                              label: '22:00–00:00',
                              sufficient: false,
                              averageValence: null,
                              entryCount: 1,
                            ),
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            expect(
              tester.takeException(),
              isNull,
              reason: '${palette.id}, dark=$dark',
            );
          }
        }
      },
    );
  });
}
