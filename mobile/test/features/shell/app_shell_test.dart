import 'package:find_my_patterns/app.dart';
import 'package:find_my_patterns/features/calendar/calendar_screen.dart';
import 'package:find_my_patterns/features/insights/insights_screen.dart';
import 'package:find_my_patterns/features/settings/settings_screen.dart';
import 'package:find_my_patterns/features/today/today_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/harness.dart';

void main() {
  /// The tabs are tall screens; a small test surface makes them overflow, which
  /// is a layout artefact of the test and not something to assert about.
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('shows the diary’s four tabs and opens on Today', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(Harness().scope(const FindMyPatternsApp()));
    await tester.pumpAndSettle();

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.destinations, hasLength(4));
    expect(bar.selectedIndex, 0);
    expect(find.byType(TodayScreen), findsOneWidget);
  });

  testWidgets('each tab shows its own screen', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(Harness().scope(const FindMyPatternsApp()));
    await tester.pumpAndSettle();

    Future<void> tapTab(String label) async {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    await tapTab('Insights');
    expect(find.byType(InsightsScreen), findsOneWidget);

    await tapTab('Calendar');
    expect(find.byType(CalendarScreen), findsOneWidget);

    await tapTab('Settings');
    expect(find.byType(SettingsScreen), findsOneWidget);

    await tapTab('Today');
    expect(find.byType(TodayScreen), findsOneWidget);
  });
}
