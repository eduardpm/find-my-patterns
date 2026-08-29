import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/diary/digest.dart';
import 'package:find_my_patterns/core/diary/pattern.dart';
import 'package:find_my_patterns/features/insights/digest_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  /// Wraps [digest] in a router with a real `/insights` destination, so a
  /// "See in Insights" tap has somewhere real to land -- the same
  /// lightweight-router pattern `day_entries_screen_test.dart` uses to prove
  /// a `context.go` call, without pulling in the whole app shell.
  Widget app(Digest digest) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => DigestScreen(digest: digest),
        ),
        GoRoute(
          path: '/insights',
          builder: (context, state) =>
              const Scaffold(body: Text('Insights destination')),
        ),
      ],
    );
    return MaterialApp.router(routerConfig: router);
  }

  testWidgets('the empty shape says nothing was written this week', (
    tester,
  ) async {
    await tester.pumpWidget(app(const Digest(true, 0, null, null, null, null)));
    await tester.pumpAndSettle();

    expect(find.text("You didn't write anything this week."), findsOneWidget);
  });

  testWidgets(
    'entries with no qualifying part say so, without inventing one',
    (tester) async {
      await tester.pumpWidget(
        app(
          const Digest(false, 4, CalendarDate(2026, 8, 24), null, null, null),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('4 entries this week, but nothing new to report yet.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('renders the highlight sentence and links into Insights', (
    tester,
  ) async {
    const highlight = DigestHighlight(
      'p1',
      PatternKind.forward,
      'reading',
      null,
      3,
      1.5,
      'reading came up in 3 entries this week.',
    );
    await tester.pumpWidget(
      app(
        const Digest(
          false,
          10,
          CalendarDate(2026, 8, 24),
          highlight,
          null,
          null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('10 entries this week'), findsOneWidget);
    expect(find.text('THIS WEEK’S PATTERN'), findsOneWidget);
    expect(
      find.text('reading came up in 3 entries this week.'),
      findsOneWidget,
    );
    expect(find.text('See in Insights'), findsOneWidget);

    await tester.tap(find.text('See in Insights'));
    await tester.pumpAndSettle();

    expect(find.text('Insights destination'), findsOneWidget);
  });

  testWidgets('renders the recommendation headline and sentence', (
    tester,
  ) async {
    const recommendation = Recommendation(
      'reading',
      'Keep doing reading',
      'On days with reading, calm is 4.5x more likely.',
      'p1',
    );
    await tester.pumpWidget(
      app(
        const Digest(
          false,
          10,
          CalendarDate(2026, 8, 24),
          null,
          recommendation,
          null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Keep doing reading'), findsOneWidget);
    expect(
      find.text('On days with reading, calm is 4.5x more likely.'),
      findsOneWidget,
    );
    expect(find.text('See in Insights'), findsOneWidget);
  });

  testWidgets('renders the movement sentence with no Insights link', (
    tester,
  ) async {
    const movement = DigestMovement(
      null,
      3,
      6,
      DigestMovementDirection.down,
      'anxious appeared in 3 entries this week, down from 6 last week.',
    );
    await tester.pumpWidget(
      app(
        const Digest(
          false,
          10,
          CalendarDate(2026, 8, 24),
          null,
          null,
          movement,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'anxious appeared in 3 entries this week, down from 6 last week.',
      ),
      findsOneWidget,
    );
    // Movement has no pattern behind it to link to, unlike the highlight and
    // the recommendation.
    expect(find.text('See in Insights'), findsNothing);
  });

  testWidgets('renders all three parts together', (tester) async {
    const highlight = DigestHighlight(
      'p1',
      PatternKind.forward,
      'reading',
      null,
      3,
      1.5,
      'reading came up in 3 entries this week.',
    );
    const recommendation = Recommendation(
      'reading',
      'Keep doing reading',
      'On days with reading, calm is 4.5x more likely.',
      'p1',
    );
    const movement = DigestMovement(
      null,
      3,
      6,
      DigestMovementDirection.down,
      'anxious appeared in 3 entries this week, down from 6 last week.',
    );
    await tester.pumpWidget(
      app(
        const Digest(
          false,
          10,
          CalendarDate(2026, 8, 24),
          highlight,
          recommendation,
          movement,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('reading came up in 3 entries this week.'),
      findsOneWidget,
    );
    expect(find.text('Keep doing reading'), findsOneWidget);
    expect(
      find.text(
        'anxious appeared in 3 entries this week, down from 6 last week.',
      ),
      findsOneWidget,
    );
    // One link each for the highlight and the recommendation.
    expect(find.text('See in Insights'), findsNWidgets(2));
  });
}
