import 'dart:io';

import 'package:find_my_patterns/core/config/app_config.dart';
import 'package:find_my_patterns/core/config/config_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('appVersion matches the version in pubspec.yaml', () {
    final pubspec =
        loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
    final version = (pubspec['version'] as String).split('+').first;
    expect(
      AppConfig.appVersion,
      version,
      reason: 'AppConfig.appVersion and pubspec.yaml have drifted apart.',
    );
  });

  test('the backend contract is a set of absolute paths', () {
    for (final path in [
      AppConfig.healthPath,
      AppConfig.sessionPath,
    ]) {
      expect(path, startsWith('/'));
    }
  });

  test('identity values are set', () {
    expect(AppConfig.appName, isNotEmpty);
    expect(AppConfig.storagePrefix, isNotEmpty);
    expect(AppConfig.defaultPort, greaterThan(0));
  });

  test('requireAuthProvider defaults to the compiled-in setting', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(requireAuthProvider), AppConfig.requireAuth);
  });

  test('requireAuthProvider can be overridden', () {
    final container = ProviderContainer(
      overrides: [requireAuthProvider.overrideWithValue(true)],
    );
    addTearDown(container.dispose);
    expect(container.read(requireAuthProvider), isTrue);
  });
}
