import 'package:find_my_patterns/core/config/app_config.dart';
import 'package:find_my_patterns/features/compose/first_pattern_notified_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedPreferencesFirstPatternNotifiedStore', () {
    const store = SharedPreferencesFirstPatternNotifiedStore(prefix: 'test');

    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('hasNotified is false on a fresh install', () async {
      expect(await store.hasNotified(), isFalse);
    });

    test('markNotified persists, so a later read comes back true', () async {
      await store.markNotified();

      expect(await store.hasNotified(), isTrue);
    });

    test('survives a fresh instance reading the same key -- the exactly-once '
        'flag outlives the store object, the same way it must outlive an '
        'app restart', () async {
      await store.markNotified();

      const reopened = SharedPreferencesFirstPatternNotifiedStore(
        prefix: 'test',
      );

      expect(await reopened.hasNotified(), isTrue);
    });

    test('the prefix keeps two apps apart on one device', () async {
      const other = SharedPreferencesFirstPatternNotifiedStore(
        prefix: 'other',
      );

      await store.markNotified();

      expect(await other.hasNotified(), isFalse);
    });

    test('defaults the prefix to the app storage prefix', () {
      expect(
        const SharedPreferencesFirstPatternNotifiedStore().prefix,
        AppConfig.storagePrefix,
      );
    });
  });
}
