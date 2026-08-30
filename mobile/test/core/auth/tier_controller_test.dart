import 'package:dio/dio.dart';
import 'package:find_my_patterns/core/auth/auth_controller.dart';
import 'package:find_my_patterns/core/auth/tier.dart';
import 'package:find_my_patterns/core/auth/tier_controller.dart';
import 'package:find_my_patterns/core/config/app_config.dart';
import 'package:find_my_patterns/core/config/config_providers.dart';
import 'package:find_my_patterns/core/network/api_client.dart';
import 'package:find_my_patterns/core/network/network_providers.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/core/settings/settings_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http.dart';
import '../../support/fake_settings_store.dart';

void main() {
  const configured = BackendAddress(host: '10.0.2.2');

  /// Builds a container whose HTTP core answers from [adapter], mirroring
  /// `auth_controller_test.dart`'s own `containerWith` -- `tierProvider`
  /// depends on the same [apiClientProvider]/[requireAuthProvider] wiring
  /// [AuthController] does.
  ProviderContainer containerWith(
    FakeHttpAdapter adapter, {
    bool requireAuth = false,
    BackendAddress backend = configured,
  }) {
    final client = ApiClient(dio: Dio()..httpClientAdapter = adapter)
      ..configure(backend);
    final container = ProviderContainer(
      overrides: [
        requireAuthProvider.overrideWithValue(requireAuth),
        apiClientProvider.overrideWithValue(client),
        settingsStoreProvider.overrideWithValue(
          FakeSettingsStore(AppSettings(backend: backend)),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('free before auth has settled -- no request, never a guess', () async {
    final adapter = FakeHttpAdapter([]);
    final container = containerWith(adapter);
    // `authProvider`'s own default, untouched: `AuthStatus.loading`.
    final tier = await container.read(tierProvider.future);
    expect(tier, Tier.free);
    expect(adapter.requests, isEmpty);
  });

  test('free while signed out -- no request of its own', () async {
    // The 401 is `restore`'s own session probe (`auth_controller_test.dart`
    // scripts the identical reply for "an expired session signs the user
    // out"); this test's own assertion is that `tierProvider` adds nothing
    // to it.
    final adapter = FakeHttpAdapter([const FakeReply(401)]);
    final container = containerWith(adapter, requireAuth: true);
    await container.read(settingsProvider.future);
    await container.read(authProvider.notifier).restore();
    expect(container.read(authProvider), AuthStatus.signedOut);

    final tier = await container.read(tierProvider.future);
    expect(tier, Tier.free);
    expect(adapter.requests, hasLength(1));
  });

  group('once signed in', () {
    test('reads the tier from GET /auth/me', () async {
      final adapter = FakeHttpAdapter([
        FakeReply(200, body: {'tier': 'premium', 'expires_at': null}),
      ]);
      final container = containerWith(adapter);
      await container.read(authProvider.notifier).restore();
      expect(container.read(authProvider), AuthStatus.signedIn);

      final tier = await container.read(tierProvider.future);
      expect(tier, Tier.premium);
      expect(adapter.requests.single.method, 'GET');
      expect(adapter.requests.single.path, AppConfig.authMePath);
    });

    test(
      'an unrecognised or absent tier reads as free, never a guess',
      () async {
        final adapter = FakeHttpAdapter([FakeReply(200, body: {})]);
        final container = containerWith(adapter);
        await container.read(authProvider.notifier).restore();

        expect(await container.read(tierProvider.future), Tier.free);
      },
    );

    test('a fetch failure falls back to free rather than throwing', () async {
      final adapter = FakeHttpAdapter([const FakeReply.networkError()]);
      final container = containerWith(adapter);
      await container.read(authProvider.notifier).restore();

      expect(await container.read(tierProvider.future), Tier.free);
    });
  });

  test(
    'logout clears a premium tier without any special-cased reset',
    () async {
      final adapter = FakeHttpAdapter([
        FakeReply(200, body: {}), // login
        FakeReply(200, body: {'tier': 'premium'}), // GET /auth/me
        FakeReply(200, body: {}), // logout
      ]);
      final container = containerWith(adapter, requireAuth: true);
      await container.read(authProvider.notifier).login('hunter2');
      expect(await container.read(tierProvider.future), Tier.premium);

      await container.read(authProvider.notifier).logout();

      // Rebuilt from the now-`signedOut` auth state -- not a field that had
      // to be remembered and cleared by hand.
      expect(await container.read(tierProvider.future), Tier.free);
      // No fourth request: `authProvider` moving to `signedOut` resolves this
      // provider without a fetch, the same as the "signed out" case above.
      expect(adapter.requests, hasLength(3));
    },
  );

  test('refresh re-fetches without waiting for authProvider to move', () async {
    final adapter = FakeHttpAdapter([
      FakeReply(200, body: {'tier': 'free'}),
      FakeReply(200, body: {'tier': 'premium'}),
    ]);
    final container = containerWith(adapter);
    await container.read(authProvider.notifier).restore();
    expect(await container.read(tierProvider.future), Tier.free);

    await container.read(tierProvider.notifier).refresh();

    expect(container.read(tierProvider).value, Tier.premium);
    expect(adapter.requests, hasLength(2));
  });
}
