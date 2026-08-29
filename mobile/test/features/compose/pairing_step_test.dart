import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/diary/entries_api.dart';
import 'package:find_my_patterns/core/diary/entry.dart';
import 'package:find_my_patterns/core/diary/feeling.dart';
import 'package:find_my_patterns/core/diary/topic.dart';
import 'package:find_my_patterns/features/compose/pairing_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  const warm = Feeling('warm', 'Warm', Valence.positive, 'uplifted');
  const disappointed = Feeling(
    'disappointed',
    'Disappointed',
    Valence.negative,
    'low',
  );

  const parents = Topic('topic-parents', 'Parents');
  const run = Topic('topic-run', 'Run');
  const weather = Topic('topic-weather', 'Weather');

  /// A mixed-valence entry -- "Missed my run and felt disappointed, but a
  /// long call with my parents was lovely" (the ticket's own example) --
  /// with `Parents` pre-placed under `Warm`, `Run` under `Disappointed`, and
  /// `Weather` left in "not linked". Feelings are ordered
  /// `[disappointed, warm]` on purpose, matching the ticket's own row-header
  /// example order ("Disappointed", "Warm").
  Entry buildEntry({
    List<Topic> topics = const [parents, run, weather],
    List<TopicFeelingPairing> topicFeelings = const [
      TopicFeelingPairing(
        'topic-parents',
        'Parents',
        warm,
        FeelingSource.suggested,
      ),
      TopicFeelingPairing(
        'topic-run',
        'Run',
        disappointed,
        FeelingSource.suggested,
      ),
    ],
  }) => Entry(
    'entry-1',
    DateTime.utc(2026, 8, 28, 9),
    const CalendarDate(2026, 8, 28),
    EntryMode.freeform,
    'Missed my run and felt disappointed, but a long call with my parents '
        'was lovely.',
    disappointed,
    const [disappointed, warm],
    FeelingSource.confirmed,
    null,
    const {},
    const [],
    null,
    const [],
    1,
    topics: topics,
    topicFeelings: topicFeelings,
  );

  group('pre-fill rendering (E-1a suggestion)', () {
    testWidgets('shows one row per confirmed feeling plus "Not linked"', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          PairingStep(
            entry: buildEntry(),
            isSaving: false,
            onConfirm: (_) {},
            onSkip: () {},
          ),
        ),
      );

      expect(find.text('Which goes with what?'), findsOneWidget);
      expect(find.text('Disappointed'), findsOneWidget);
      expect(find.text('Warm'), findsOneWidget);
      expect(find.text('Not linked'), findsOneWidget);
      expect(
        find.textContaining("won't count toward mixed patterns"),
        findsOneWidget,
      );
    });

    testWidgets(
      'places each topic under the analyser\'s suggested feeling, and an '
      'unsuggested topic under "Not linked"',
      (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          host(
            PairingStep(
              entry: buildEntry(),
              isSaving: false,
              onConfirm: (_) {},
              onSkip: () {},
            ),
          ),
        );

        expect(
          tester.getSemantics(find.bySemanticsLabel('Parents')),
          matchesSemantics(
            label: 'Parents',
            value: 'linked to Warm',
            isButton: true,
            hasTapAction: true,
          ),
        );
        expect(
          tester.getSemantics(find.bySemanticsLabel('Run')),
          matchesSemantics(
            label: 'Run',
            value: 'linked to Disappointed',
            isButton: true,
            hasTapAction: true,
          ),
        );
        expect(
          tester.getSemantics(find.bySemanticsLabel('Weather')),
          matchesSemantics(
            label: 'Weather',
            value: 'not linked',
            isButton: true,
            hasTapAction: true,
          ),
        );
        handle.dispose();
      },
    );
  });

  group('reassignment', () {
    testWidgets(
      'tapping a chip cycles it through every feeling, then "not linked", '
      'then back to its starting feeling',
      (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          host(
            PairingStep(
              entry: buildEntry(),
              isSaving: false,
              onConfirm: (_) {},
              onSkip: () {},
            ),
          ),
        );

        // Starts linked to Warm (the last feeling in the row order).
        expect(
          tester.getSemantics(find.bySemanticsLabel('Parents')).value,
          'linked to Warm',
        );

        await tester.tap(find.bySemanticsLabel('Parents'));
        await tester.pump();
        expect(
          tester.getSemantics(find.bySemanticsLabel('Parents')).value,
          'not linked',
        );

        await tester.tap(find.bySemanticsLabel('Parents'));
        await tester.pump();
        expect(
          tester.getSemantics(find.bySemanticsLabel('Parents')).value,
          'linked to Disappointed',
        );

        await tester.tap(find.bySemanticsLabel('Parents'));
        await tester.pump();
        expect(
          tester.getSemantics(find.bySemanticsLabel('Parents')).value,
          'linked to Warm',
        );
        handle.dispose();
      },
    );

    testWidgets('"Confirm pairing" hands back the board as reassigned', (
      tester,
    ) async {
      List<TopicFeelingAssignment>? confirmed;
      await tester.pumpWidget(
        host(
          PairingStep(
            entry: buildEntry(),
            isSaving: false,
            onConfirm: (pairings) => confirmed = pairings,
            onSkip: () {},
          ),
        ),
      );

      // Unlink Parents (Warm -> not linked), leaving only Run -> Disappointed.
      await tester.tap(find.bySemanticsLabel('Parents'));
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm pairing'));

      expect(confirmed, isNotNull);
      expect(confirmed, [(topicId: 'topic-run', feelingKey: 'disappointed')]);
    });
  });

  group('skip', () {
    testWidgets('"Skip" calls onSkip and never onConfirm', (tester) async {
      var skipped = false;
      var confirmedCalled = false;
      await tester.pumpWidget(
        host(
          PairingStep(
            entry: buildEntry(),
            isSaving: false,
            onConfirm: (_) => confirmedCalled = true,
            onSkip: () => skipped = true,
          ),
        ),
      );

      await tester.tap(find.widgetWithText(OutlinedButton, 'Skip'));

      expect(skipped, isTrue);
      expect(confirmedCalled, isFalse);
    });

    testWidgets('both actions are disabled while isSaving', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        host(
          PairingStep(
            entry: buildEntry(),
            isSaving: true,
            onConfirm: (_) => tapped = true,
            onSkip: () => tapped = true,
          ),
        ),
      );

      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Saving…'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Skip'),
            )
            .onPressed,
        isNull,
      );
      expect(tapped, isFalse);
    });
  });

  group('accessibility and layout', () {
    testWidgets('every topic chip is at least 44 logical pixels tall', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          PairingStep(
            entry: buildEntry(),
            isSaving: false,
            onConfirm: (_) {},
            onSkip: () {},
          ),
        ),
      );

      for (final label in ['Parents', 'Run', 'Weather']) {
        final size = tester.getSize(find.bySemanticsLabel(label));
        expect(size.height, greaterThanOrEqualTo(44));
        expect(size.width, greaterThanOrEqualTo(44));
      }
      handle.dispose();
    });

    for (final textScale in [1.0, 1.3, 2.0]) {
      testWidgets(
        'renders without overflow at 320dp width and ${textScale}x text '
        'scale',
        (tester) async {
          await tester.pumpWidget(
            MediaQuery(
              data: MediaQueryData(
                size: const Size(320, 700),
                textScaler: TextScaler.linear(textScale),
              ),
              child: host(
                PairingStep(
                  entry: buildEntry(),
                  isSaving: false,
                  onConfirm: (_) {},
                  onSkip: () {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.text('Which goes with what?'), findsOneWidget);
          expect(
            find.widgetWithText(ElevatedButton, 'Confirm pairing'),
            findsOneWidget,
          );
        },
      );
    }
  });
}
