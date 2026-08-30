import 'package:find_my_patterns/core/diary/pattern.dart';
import 'package:find_my_patterns/core/theme/app_theme.dart';
import 'package:find_my_patterns/features/insights/withdrawal_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  Widget app(Widget child) => MaterialApp(
    theme: buildLightTheme(),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  testWidgets(
    'a forward withdrawal reads "Topic → feeling" with a leading capital',
    (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          WithdrawalNotice(
            withdrawal: buildWithdrawal(
              topic: 'coffee',
              feeling: 'stressed',
              kind: PatternKind.forward,
            ),
          ),
        ),
      );

      expect(find.text('Coffee → stressed'), findsOneWidget);
    },
  );

  testWidgets(
    'an inverse withdrawal reads "Without topic → feeling", never the '
    'forward form',
    (tester) async {
      await tester.pumpWidget(
        app(
          WithdrawalNotice(
            withdrawal: buildWithdrawal(
              topic: 'coffee',
              feeling: 'stressed',
              kind: PatternKind.inverse,
            ),
          ),
        ),
      );

      expect(find.text('Without coffee → stressed'), findsOneWidget);
      expect(find.text('Coffee → stressed'), findsNothing);
    },
  );

  testWidgets('shows the previous and new counts', (tester) async {
    await tester.pumpWidget(
      app(
        WithdrawalNotice(
          withdrawal: buildWithdrawal(previousCount: 5, newCount: 1),
        ),
      ),
    );

    expect(find.text('5 → 1'), findsOneWidget);
  });

  testWidgets('shows the detail text the backend sent', (tester) async {
    await tester.pumpWidget(
      app(
        WithdrawalNotice(
          withdrawal: buildWithdrawal(detailText: 'Only 1 of the last 5 held.'),
        ),
      ),
    );

    expect(find.text('Only 1 of the last 5 held.'), findsOneWidget);
  });

  testWidgets(
    'shows a single count, not a delta, when previous and new are equal '
    '(#109 -- "2 → 2" beside "was withdrawn" is a self-contradiction)',
    (tester) async {
      await tester.pumpWidget(
        app(
          WithdrawalNotice(
            withdrawal: buildWithdrawal(
              reason: WithdrawalReason.excludedUnpaired,
              previousCount: 2,
              newCount: 2,
            ),
          ),
        ),
      );

      // `Eyebrow` upper-cases its text for display (`JournalType.eyebrowCase`).
      expect(find.text('2 OCCURRENCES'), findsOneWidget);
      expect(find.text('2 → 2'), findsNothing);
    },
  );

  testWidgets(
    'singularises the count line when the equal count is 1 (defect found '
    'on the live diary: "1 OCCURRENCES")',
    (tester) async {
      await tester.pumpWidget(
        app(
          WithdrawalNotice(
            withdrawal: buildWithdrawal(
              reason: WithdrawalReason.excludedUnpaired,
              previousCount: 1,
              newCount: 1,
            ),
          ),
        ),
      );

      expect(find.text('1 OCCURRENCE'), findsOneWidget);
      expect(find.text('1 OCCURRENCES'), findsNothing);
    },
  );

  for (final entry in {
    WithdrawalReason.belowThreshold: 'NOT ENOUGH LEFT',
    WithdrawalReason.belowLift: 'ASSOCIATION TOO WEAK',
    WithdrawalReason.noLongerConfirmed: 'NO CONFIRMED FEELINGS',
    WithdrawalReason.topicMerged: 'TOPIC MERGED',
    WithdrawalReason.excludedUnpaired: 'NEEDS PAIRING',
  }.entries) {
    testWidgets('labels ${entry.key} as "${entry.value}"', (tester) async {
      await tester.pumpWidget(
        app(WithdrawalNotice(withdrawal: buildWithdrawal(reason: entry.key))),
      );

      expect(find.text(entry.value), findsOneWidget);
    });
  }
}
