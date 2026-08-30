import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/features/topics/topics_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http.dart';
import '../../support/harness.dart';

void main() {
  // A configured backend, so requests actually reach the fake adapter instead
  // of being rejected up front by BackendNotConfigured.
  const configured = AppSettings(backend: BackendAddress(host: '10.0.2.2'));

  Widget screen({VoidCallback? onClose}) =>
      TopicsScreen(onClose: onClose ?? () {});

  FakeReply topicsReply(List<Map<String, Object?>> topics) =>
      FakeReply(200, body: {'topics': topics});

  Map<String, Object?> topic({
    String id = 't1',
    String name = 'exercise',
    List<String> aliases = const [],
    int entryCount = 1,
  }) => {
    'id': id,
    'name': name,
    'aliases': aliases,
    'entry_count': entryCount,
  };

  testWidgets('shows a loading indicator before the first response lands', (
    tester,
  ) async {
    final harness = Harness(
      settings: configured,
      adapter: FakeHttpAdapter([
        topicsReply([topic()]),
      ]),
    );
    await tester.pumpWidget(harness.wrap(screen()));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('shows the empty state when there are no topics', (
    tester,
  ) async {
    final harness = Harness(
      settings: configured,
      adapter: FakeHttpAdapter([topicsReply([])]),
    );
    await tester.pumpWidget(harness.wrap(screen()));
    await tester.pumpAndSettle();

    expect(find.text('No topics yet'), findsOneWidget);
    expect(
      find.text(
        'Topics appear once you have written entries the app can read '
        'them from.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'a failed initial load shows the empty state and surfaces the error',
    (tester) async {
      final harness = Harness(
        settings: configured,
        adapter: FakeHttpAdapter([const FakeReply(500)]),
      );
      await tester.pumpWidget(harness.wrap(screen()));
      await tester.pumpAndSettle();

      // Nothing to show and nothing to retry from within the list itself —
      // the failure is reported once, as a SnackBar, rather than replacing
      // the page with a dead end.
      expect(find.text('No topics yet'), findsOneWidget);
      expect(find.text('Server error (500).'), findsOneWidget);
    },
  );

  testWidgets('shows a topic capitalised, with a singular entry count', (
    tester,
  ) async {
    final harness = Harness(
      settings: configured,
      adapter: FakeHttpAdapter([
        topicsReply([topic(name: 'exercise', entryCount: 1)]),
      ]),
    );
    await tester.pumpWidget(harness.wrap(screen()));
    await tester.pumpAndSettle();

    expect(find.text('Exercise'), findsOneWidget);
    // Eyebrow upper-cases for display; its Semantics label carries the
    // original casing, which is covered by the shared Eyebrow widget tests.
    expect(find.text('1 ENTRY'), findsOneWidget);
  });

  testWidgets('pluralises the entry count for more than one entry', (
    tester,
  ) async {
    final harness = Harness(
      settings: configured,
      adapter: FakeHttpAdapter([
        topicsReply([topic(name: 'exercise', entryCount: 4)]),
      ]),
    );
    await tester.pumpWidget(harness.wrap(screen()));
    await tester.pumpAndSettle();

    expect(find.text('4 ENTRIES'), findsOneWidget);
  });

  testWidgets('sorts topics by entry count descending', (tester) async {
    final harness = Harness(
      settings: configured,
      adapter: FakeHttpAdapter([
        topicsReply([
          topic(id: 't1', name: 'sleep', entryCount: 2),
          topic(id: 't2', name: 'exercise', entryCount: 9),
          topic(id: 't3', name: 'work', entryCount: 5),
        ]),
      ]),
    );
    await tester.pumpWidget(harness.wrap(screen()));
    await tester.pumpAndSettle();

    // Order on screen should be exercise (9), work (5), sleep (2) — most
    // entries first — regardless of the order the API returned them in.
    final exerciseTop = tester.getTopLeft(find.text('Exercise')).dy;
    final workTop = tester.getTopLeft(find.text('Work')).dy;
    final sleepTop = tester.getTopLeft(find.text('Sleep')).dy;
    expect(exerciseTop, lessThan(workTop));
    expect(workTop, lessThan(sleepTop));
  });

  testWidgets('keeps the API order for topics tied on entry count', (
    tester,
  ) async {
    final harness = Harness(
      settings: configured,
      adapter: FakeHttpAdapter([
        topicsReply([
          topic(id: 't1', name: 'sleep', entryCount: 3),
          topic(id: 't2', name: 'exercise', entryCount: 3),
        ]),
      ]),
    );
    await tester.pumpWidget(harness.wrap(screen()));
    await tester.pumpAndSettle();

    final sleepTop = tester.getTopLeft(find.text('Sleep')).dy;
    final exerciseTop = tester.getTopLeft(find.text('Exercise')).dy;
    expect(sleepTop, lessThan(exerciseTop));
  });

  testWidgets('shows the existing aliases as badges on a collapsed row', (
    tester,
  ) async {
    final harness = Harness(
      settings: configured,
      adapter: FakeHttpAdapter([
        topicsReply([
          topic(name: 'exercise', aliases: ['gym', 'workout']),
        ]),
      ]),
    );
    await tester.pumpWidget(harness.wrap(screen()));
    await tester.pumpAndSettle();

    expect(find.text('GYM'), findsOneWidget);
    expect(find.text('WORKOUT'), findsOneWidget);
  });

  testWidgets('a collapsed row shows no alias input or Add button', (
    tester,
  ) async {
    final harness = Harness(
      settings: configured,
      adapter: FakeHttpAdapter([
        topicsReply([topic(name: 'exercise')]),
      ]),
    );
    await tester.pumpWidget(harness.wrap(screen()));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('Add'), findsNothing);
  });

  testWidgets('tapping a row expands it and reveals the alias input', (
    tester,
  ) async {
    final harness = Harness(
      settings: configured,
      adapter: FakeHttpAdapter([
        topicsReply([topic(name: 'exercise')]),
      ]),
    );
    await tester.pumpWidget(harness.wrap(screen()));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('Exercise'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Another word for exercise'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);

    // Tapping the row again collapses it back.
    await tester.tap(find.text('Exercise'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('disables Add while the draft is blank', (tester) async {
    final harness = Harness(
      settings: configured,
      adapter: FakeHttpAdapter([
        topicsReply([topic()]),
      ]),
    );
    await tester.pumpWidget(harness.wrap(screen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Exercise'));
    await tester.pumpAndSettle();

    final addButton = tester.widget<ElevatedButton>(
      find.byType(ElevatedButton),
    );
    expect(addButton.enabled, isFalse);

    await tester.enterText(find.byType(TextField), 'gym');
    await tester.pump();

    final enabledButton = tester.widget<ElevatedButton>(
      find.byType(ElevatedButton),
    );
    expect(enabledButton.enabled, isTrue);
  });

  testWidgets('adding an alias refreshes the list and resets the draft', (
    tester,
  ) async {
    final harness = Harness(
      settings: configured,
      adapter: FakeHttpAdapter([
        topicsReply([topic(name: 'exercise')]),
        FakeReply(
          200,
          body: topic(name: 'exercise', aliases: const ['gym']),
        ),
        topicsReply([
          topic(name: 'exercise', aliases: ['gym']),
        ]),
      ]),
    );
    await tester.pumpWidget(harness.wrap(screen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Exercise'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'gym');
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(find.text('GYM'), findsOneWidget);
    expect(harness.adapter.requests[1].method, 'POST');
    expect(harness.adapter.requests[1].path, '/topics/t1/aliases');
    expect(harness.adapter.requests[1].data, {'alias': 'gym'});
    // The third request is the refresh a successful add triggers.
    expect(harness.adapter.requests, hasLength(3));
    expect(find.text('Another word for exercise'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('removing an alias on an expanded row refreshes the list', (
    tester,
  ) async {
    final harness = Harness(
      settings: configured,
      adapter: FakeHttpAdapter([
        topicsReply([
          topic(name: 'exercise', aliases: ['gym']),
        ]),
        FakeReply(
          200,
          body: topic(name: 'exercise', aliases: const []),
        ),
        topicsReply([topic(name: 'exercise')]),
      ]),
    );
    await tester.pumpWidget(harness.wrap(screen()));
    await tester.pumpAndSettle();

    expect(find.text('GYM'), findsOneWidget);
    // Collapsed: the alias is a badge, with no remove control yet.
    expect(find.byTooltip('Remove the alias gym from exercise'), findsNothing);

    await tester.tap(find.text('Exercise'));
    await tester.pumpAndSettle();

    // #150 task 1: the accessible name comes from the semantics tree's
    // `label`, not `IconButton`'s own `tooltip` field.
    expect(
      find.bySemanticsLabel('Remove the alias gym from exercise'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Remove the alias gym from exercise'));
    await tester.pumpAndSettle();

    expect(find.text('GYM'), findsNothing);
    expect(harness.adapter.requests[1].method, 'DELETE');
    expect(harness.adapter.requests[1].path, '/topics/t1/aliases/gym');
  });

  testWidgets(
    'surfaces a failed add as a SnackBar and does not re-show it',
    (tester) async {
      final harness = Harness(
        settings: configured,
        adapter: FakeHttpAdapter([
          topicsReply([topic(name: 'exercise')]),
          const FakeReply(500),
        ]),
      );
      await tester.pumpWidget(harness.wrap(screen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Exercise'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'gym');
      await tester.pump();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(find.text('Server error (500).'), findsOneWidget);
      // The draft was not cleared — the alias was rejected, not accepted.
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'gym',
      );

      // The controller clears the error the moment it is shown, so once the
      // SnackBar's own timer dismisses it, nothing brings the same message
      // back.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Server error (500).'), findsNothing);
    },
  );

  testWidgets('two expanded rows keep separate drafts', (tester) async {
    final harness = Harness(
      settings: configured,
      adapter: FakeHttpAdapter([
        topicsReply([
          topic(id: 't1', name: 'exercise', entryCount: 2),
          topic(id: 't2', name: 'sleep', entryCount: 1),
        ]),
      ]),
    );
    await tester.pumpWidget(harness.wrap(screen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Exercise'));
    await tester.tap(find.text('Sleep'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('topic-draft-t1')), 'gym');
    await tester.pump();

    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('topic-draft-t2')))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('the back button calls onClose', (tester) async {
    var closed = false;
    final harness = Harness(
      settings: configured,
      adapter: FakeHttpAdapter([topicsReply([])]),
    );
    await tester.pumpWidget(
      harness.wrap(screen(onClose: () => closed = true)),
    );
    await tester.pumpAndSettle();

    // #150 task 1: the accessible name comes from the semantics tree's
    // `label`, not `IconButton`'s own `tooltip` field.
    expect(find.bySemanticsLabel('Back'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    expect(closed, isTrue);
  });
}
