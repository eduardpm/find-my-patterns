import 'dart:io';

import 'package:dio/dio.dart';
import 'package:find_my_patterns/core/auth/auth_controller.dart';
import 'package:find_my_patterns/core/config/app_config.dart';
import 'package:find_my_patterns/core/config/config_providers.dart';
import 'package:find_my_patterns/core/network/api_client.dart';
import 'package:find_my_patterns/core/network/api_error.dart';
import 'package:find_my_patterns/core/network/network_providers.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/core/settings/settings_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http.dart';
import '../../support/fake_settings_store.dart';

void main() {
  const configured = BackendAddress(host: '10.0.2.2');

  /// Builds a container whose HTTP core answers from [adapter].
  (ProviderContainer, ApiClient) containerWith(
    FakeHttpAdapter adapter, {
    bool requireAuth = true,
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
    return (container, client);
  }

  group('restore', () {
    test('starts in the loading state', () {
      final (container, _) = containerWith(FakeHttpAdapter([]));
      expect(container.read(authProvider), AuthStatus.loading);
    });

    test('signs straight in when auth is not required', () async {
      final adapter = FakeHttpAdapter([]);
      final (container, _) = containerWith(adapter, requireAuth: false);
      await container.read(authProvider.notifier).restore();
      expect(container.read(authProvider), AuthStatus.signedIn);
      expect(adapter.requests, isEmpty);
    });

    test('signs out when no server has been configured', () async {
      final adapter = FakeHttpAdapter([]);
      final (container, _) = containerWith(
        adapter,
        backend: BackendAddress.unset,
      );
      await container.read(settingsProvider.future);
      await container.read(authProvider.notifier).restore();
      expect(container.read(authProvider), AuthStatus.signedOut);
      expect(adapter.requests, isEmpty);
    });

    test('a stored session signs the user back in', () async {
      final adapter = FakeHttpAdapter([const FakeReply(200, body: {})]);
      final (container, _) = containerWith(adapter);
      await container.read(settingsProvider.future);
      await container.read(authProvider.notifier).restore();
      expect(container.read(authProvider), AuthStatus.signedIn);
      expect(adapter.requests.single.method, 'GET');
      expect(adapter.requests.single.path, AppConfig.sessionPath);
    });

    test('an expired session signs the user out', () async {
      final (container, _) = containerWith(
        FakeHttpAdapter([const FakeReply(401)]),
      );
      await container.read(settingsProvider.future);
      await container.read(authProvider.notifier).restore();
      expect(container.read(authProvider), AuthStatus.signedOut);
    });

    test('an unreachable server signs the user out', () async {
      final (container, _) = containerWith(
        FakeHttpAdapter([const FakeReply.networkError()]),
      );
      await container.read(settingsProvider.future);
      await container.read(authProvider.notifier).restore();
      expect(container.read(authProvider), AuthStatus.signedOut);
    });
  });

  group('login', () {
    test('signs in and sends the password', () async {
      final adapter = FakeHttpAdapter([const FakeReply(200, body: {})]);
      final (container, _) = containerWith(adapter);
      await container.read(authProvider.notifier).login('hunter2');
      expect(container.read(authProvider), AuthStatus.signedIn);
      expect(adapter.requests.single.data, {'password': 'hunter2'});
      expect(adapter.requests.single.method, 'POST');
      expect(adapter.requests.single.path, AppConfig.sessionPath);
    });

    test('a rejected password throws and leaves the state alone', () async {
      final (container, _) = containerWith(
        FakeHttpAdapter([const FakeReply(401)]),
      );
      await expectLater(
        container.read(authProvider.notifier).login('wrong'),
        throwsA(isA<Unauthorized>()),
      );
      expect(container.read(authProvider), AuthStatus.loading);
    });
  });

  group('logout', () {
    test('tells the server and clears the local session', () async {
      final adapter = FakeHttpAdapter.always(const FakeReply(200, body: {}));
      final (container, client) = containerWith(adapter);
      await container.read(authProvider.notifier).login('hunter2');
      await client.cookieJar.saveFromResponse(
        Uri.parse(configured.origin),
        [Cookie('session', 'abc')],
      );

      await container.read(authProvider.notifier).logout();

      expect(container.read(authProvider), AuthStatus.signedOut);
      expect(
        await client.cookieJar.loadForRequest(Uri.parse(configured.origin)),
        isEmpty,
      );
      expect(adapter.requests.last.method, 'DELETE');
      expect(adapter.requests.last.path, AppConfig.sessionPath);
    });

    test('signs out locally even when the server is unreachable', () async {
      final (container, _) = containerWith(
        FakeHttpAdapter.always(const FakeReply.networkError()),
      );
      await container.read(authProvider.notifier).logout();
      expect(container.read(authProvider), AuthStatus.signedOut);
    });
  });
}
