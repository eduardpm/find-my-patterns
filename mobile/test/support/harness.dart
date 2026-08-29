import 'package:dio/dio.dart';
import 'package:find_my_patterns/core/config/config_providers.dart';
import 'package:find_my_patterns/core/network/api_client.dart';
import 'package:find_my_patterns/core/network/network_providers.dart';
import 'package:find_my_patterns/core/notifications/reminder_providers.dart';
import 'package:find_my_patterns/core/notifications/reminder_service.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/core/settings/settings_controller.dart';
import 'package:find_my_patterns/features/compose/composer_draft.dart';
import 'package:find_my_patterns/features/compose/entry_composer_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notifications/fake_device_time_zone.dart';
import '../core/notifications/fake_notifications_plugin.dart';
import 'fake_composer_draft_store.dart';
import 'fake_first_pattern_store.dart';
import 'fake_http.dart';
import 'fake_settings_store.dart';

/// The pieces a widget test needs to drive the app entirely offline.
class Harness {
  /// Wires a fake settings store, a fake composer-draft store and a fake
  /// HTTP adapter into a provider scope.
  ///
  /// [initialDraft] seeds [draftStore] the way a previous run of the app
  /// having already written a draft to disk would -- so a test can open the
  /// composer straight into "there is a draft to restore" without first
  /// driving a save through the real controller.
  Harness({
    AppSettings settings = const AppSettings(),
    FakeHttpAdapter? adapter,
    this.requireAuth = false,
    ComposerDraft? initialDraft,
    bool firstPatternNotified = true,
  }) : store = FakeSettingsStore(settings),
       draftStore = FakeComposerDraftStore(initialDraft),
       remindersPlugin = FakeNotificationsPlugin(),
       firstPatternStore = FakeFirstPatternNotifiedStore(
         notified: firstPatternNotified,
       ),
       adapter =
           adapter ?? FakeHttpAdapter.always(const FakeReply(200, body: {})) {
    client = ApiClient(dio: Dio()..httpClientAdapter = this.adapter)
      ..configure(settings.backend);
  }

  /// The in-memory settings store the app reads and writes.
  final FakeSettingsStore store;

  /// The in-memory composer-draft store the app reads and writes.
  final FakeComposerDraftStore draftStore;

  /// The fake plugin behind [baseOverrides]' `reminderServiceProvider`.
  ///
  /// Exposed so a test can assert on what got scheduled, or script a
  /// permission result, without ever touching a real platform channel.
  final FakeNotificationsPlugin remindersPlugin;

  /// The fake store behind [baseOverrides]' `firstPatternStoreProvider`
  /// (L-3/#38).
  ///
  /// Starts already notified unless the constructor's
  /// `firstPatternNotified: false` says otherwise -- see
  /// `FakeFirstPatternNotifiedStore`'s own doc comment for why that is the
  /// harness-wide default: most tests using this harness have nothing to
  /// do with the first-pattern celebration, and an already-notified store
  /// keeps `EntryComposerController._checkFirstPattern` from making an
  /// extra `GET /insights` call those tests never scripted a reply for.
  final FakeFirstPatternNotifiedStore firstPatternStore;

  /// The scripted HTTP adapter behind [client].
  final FakeHttpAdapter adapter;

  /// Whether the app under test is gated behind sign-in.
  final bool requireAuth;

  /// The client wired to [adapter].
  late final ApiClient client;

  /// Wraps [child] in the provider scope and a `MaterialApp`.
  Widget wrap(Widget child) => scope(MaterialApp(home: Scaffold(body: child)));

  /// Wraps [child] in the provider scope only, for widgets bringing their own
  /// `MaterialApp`.
  Widget scope(Widget child) =>
      ProviderScope(overrides: baseOverrides, retry: noRetry, child: child);

  /// A headless container over the same fakes, for testing a controller's own
  /// logic without building a widget tree.
  ///
  /// Retry is disabled here for the same reason it is in [scope], and it must
  /// be set on the container rather than on a provider: a provider's own
  /// `retry` outranks the container's, so a provider that named one would drag
  /// the framework's backoff into every test that touches it.
  /// A test that also needs to pin a clock or a poll interval builds its own
  /// container from [baseOverrides] and [noRetry] instead.
  ProviderContainer container() =>
      ProviderContainer(overrides: baseOverrides, retry: noRetry);

  /// The fake wiring every scope in these tests needs.
  ///
  /// Deliberately a field with an inferred type: Riverpod 3.4.2 does not export
  /// `Override`, so the list's element type cannot be written down — but it can
  /// still be inferred and spread into a caller's own `overrides:`.
  late final baseOverrides = [
    requireAuthProvider.overrideWithValue(requireAuth),
    settingsStoreProvider.overrideWithValue(store),
    apiClientProvider.overrideWithValue(client),
    composerDraftStoreProvider.overrideWithValue(draftStore),
    firstPatternStoreProvider.overrideWithValue(firstPatternStore),
    reminderServiceProvider.overrideWithValue(
      ReminderService(
        plugin: remindersPlugin,
        deviceTimeZone: FakeDeviceTimeZone(),
      ),
    ),
  ];

  /// The retry policy every test uses: none.
  ///
  /// The app's real policy is a pure function verified in
  /// `test/core/network/retry_policy_test.dart`. Leaving any retry on here
  /// would make each failure case wait out a real backoff and script extra
  /// replies into the fake adapter — Article 3's "deterministic and offline"
  /// abandoned for no extra coverage. It has to be set on the container rather
  /// than on a provider, because a provider's own `retry` outranks the
  /// container's.
  static Duration? noRetry(int retryCount, Object error) => null;
}
