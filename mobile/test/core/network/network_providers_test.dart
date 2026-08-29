import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:find_my_patterns/core/network/network_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// A path provider that answers with a real temporary directory.
class FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  FakePathProvider(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the default cookie jar is in-memory', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(cookieJarProvider), isA<CookieJar>());
    expect(container.read(cookieJarProvider), isNot(isA<PersistCookieJar>()));
  });

  test('the client is built over the injected jar', () {
    final jar = CookieJar();
    final container = ProviderContainer(
      overrides: [cookieJarProvider.overrideWithValue(jar)],
    );
    addTearDown(container.dispose);
    expect(container.read(apiClientProvider).cookieJar, same(jar));
  });

  test('the client provider is a singleton within a scope', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(apiClientProvider),
      same(container.read(apiClientProvider)),
    );
  });

  test('createPersistentCookieJar stores cookies under app storage', () async {
    final directory = Directory.systemTemp.createTempSync(
      'find_my_patterns_test',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    PathProviderPlatform.instance = FakePathProvider(directory.path);

    final jar = await createPersistentCookieJar();
    expect(jar, isA<PersistCookieJar>());

    final uri = Uri.parse('http://10.0.2.2:8000');
    await jar.saveFromResponse(uri, [Cookie('session', 'abc')]);
    expect(await jar.loadForRequest(uri), isNotEmpty);
    expect(Directory('${directory.path}/.cookies').existsSync(), isTrue);
  });
}
