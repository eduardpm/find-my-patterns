import 'package:dio/dio.dart';
import 'package:find_my_patterns/core/config/config_providers.dart';
import 'package:find_my_patterns/core/network/api_client.dart';
import 'package:find_my_patterns/core/network/network_providers.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/core/settings/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fake_http.dart';
import 'fake_settings_store.dart';

/// The pieces a widget test needs to drive the app entirely offline.
class Harness {
  /// Wires a fake settings store and a fake HTTP adapter into a provider scope.
  Harness({
    AppSettings settings = const AppSettings(),
    FakeHttpAdapter? adapter,
    this.requireAuth = false,
  }) : store = FakeSettingsStore(settings),
       adapter =
           adapter ?? FakeHttpAdapter.always(const FakeReply(200, body: {})) {
    client = ApiClient(dio: Dio()..httpClientAdapter = this.adapter)
      ..configure(settings.backend);
  }

  /// The in-memory settings store the app reads and writes.
  final FakeSettingsStore store;

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
