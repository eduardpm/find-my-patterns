import 'package:find_my_patterns/core/widgets/journal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('Eyebrow', () {
    testWidgets('shows the text upper-cased', (tester) async {
      await tester.pumpWidget(host(const Eyebrow('Monday, August 24')));
      expect(find.text('MONDAY, AUGUST 24'), findsOneWidget);
      expect(find.text('Monday, August 24'), findsNothing);
    });

    testWidgets('exposes the original casing to the accessibility tree', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(const Eyebrow('3 entries')));
      expect(
        tester.getSemantics(find.byType(Eyebrow)),
        matchesSemantics(label: '3 entries'),
      );
      handle.dispose();
    });
  });

  group('PageHeader', () {
    testWidgets('shows the title without an eyebrow or actions', (
      tester,
    ) async {
      await tester.pumpWidget(host(const PageHeader(title: Text('Today'))));
      expect(find.text('Today'), findsOneWidget);
    });

    testWidgets('shows the eyebrow when given one', (tester) async {
      await tester.pumpWidget(
        host(
          const PageHeader(
            eyebrow: Eyebrow('Diary'),
            title: Text('Today'),
          ),
        ),
      );
      expect(find.text('DIARY'), findsOneWidget);
    });

    testWidgets('shows every provided action', (tester) async {
      await tester.pumpWidget(
        host(
          PageHeader(
            title: const Text('Insights'),
            actions: [
              IconButton(icon: const Icon(Icons.share), onPressed: () {}),
              IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}),
            ],
          ),
        ),
      );
      expect(find.byIcon(Icons.share), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });
  });

  group('JournalCard', () {
    testWidgets('shows its content', (tester) async {
      await tester.pumpWidget(
        host(const JournalCard(child: Text('card body'))),
      );
      expect(find.text('card body'), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        host(
          JournalCard(
            onTap: () => tapped = true,
            child: const Text('tap me'),
          ),
        ),
      );
      await tester.tap(find.text('tap me'));
      expect(tapped, isTrue);
    });

    testWidgets('adds no tap action to the accessibility tree when onTap is '
        'null', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(const JournalCard(child: Text('static'))),
      );
      expect(
        tester.getSemantics(find.byType(InkWell)),
        isSemantics(hasTapAction: false),
      );
      handle.dispose();
    });

    testWidgets('adds a tap action to the accessibility tree when onTap is '
        'set', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(JournalCard(onTap: () {}, child: const Text('tappable'))),
      );
      expect(
        tester.getSemantics(find.byType(InkWell)),
        isSemantics(hasTapAction: true),
      );
      handle.dispose();
    });
  });

  group('PillButton', () {
    testWidgets('calls onPressed when tapped', (tester) async {
      var pressed = false;
      await tester.pumpWidget(
        host(
          PillButton(
            onPressed: () => pressed = true,
            child: const Text('Save'),
          ),
        ),
      );
      await tester.tap(find.text('Save'));
      expect(pressed, isTrue);
    });

    testWidgets('is disabled when onPressed is null', (tester) async {
      await tester.pumpWidget(
        host(const PillButton(onPressed: null, child: Text('Save'))),
      );
      final button = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton),
      );
      expect(button.enabled, isFalse);
    });
  });

  group('SecondaryPillButton', () {
    testWidgets('calls onPressed when tapped', (tester) async {
      var pressed = false;
      await tester.pumpWidget(
        host(
          SecondaryPillButton(
            onPressed: () => pressed = true,
            child: const Text('Cancel'),
          ),
        ),
      );
      await tester.tap(find.text('Cancel'));
      expect(pressed, isTrue);
    });

    testWidgets('is disabled when onPressed is null', (tester) async {
      await tester.pumpWidget(
        host(const SecondaryPillButton(onPressed: null, child: Text('Cancel'))),
      );
      final button = tester.widget<OutlinedButton>(
        find.byType(OutlinedButton),
      );
      expect(button.enabled, isFalse);
    });
  });

  group('EmptyState', () {
    testWidgets('shows the title and nothing optional by default', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const EmptyState(title: Text('Nothing yet'))),
      );
      expect(find.text('Nothing yet'), findsOneWidget);
      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('shows the icon, supporting text and action when given', (
      tester,
    ) async {
      var actionTapped = false;
      await tester.pumpWidget(
        host(
          EmptyState(
            icon: const Icon(Icons.book_outlined),
            title: const Text('Nothing yet'),
            supporting: const Text('Write your first entry.'),
            action: TextButton(
              onPressed: () => actionTapped = true,
              child: const Text('Start writing'),
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.book_outlined), findsOneWidget);
      expect(find.text('Write your first entry.'), findsOneWidget);
      await tester.tap(find.text('Start writing'));
      expect(actionTapped, isTrue);
    });
  });

  group('FeelingDot', () {
    testWidgets('excludes itself from the accessibility tree', (
      tester,
    ) async {
      await tester.pumpWidget(host(const FeelingDot(color: Colors.green)));
      expect(
        find.descendant(
          of: find.byType(FeelingDot),
          matching: find.byType(ExcludeSemantics),
        ),
        findsOneWidget,
      );
    });
  });

  group('StatusBadge', () {
    testWidgets('shows the text upper-cased', (tester) async {
      await tester.pumpWidget(host(const StatusBadge('keep doing')));
      expect(find.text('KEEP DOING'), findsOneWidget);
    });

    testWidgets('shows a leading icon when given one', (tester) async {
      await tester.pumpWidget(
        host(
          const StatusBadge('confirmed', leading: Icon(Icons.check)),
        ),
      );
      expect(find.byIcon(Icons.check), findsOneWidget);
    });
  });
}
