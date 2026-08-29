import 'package:find_my_patterns/core/config/app_config.dart';
import 'package:find_my_patterns/features/today/backdate_nudge_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedPreferencesBackdateNudgeStore', () {
    const store = SharedPreferencesBackdateNudgeStore(prefix: 'test');

    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('isDismissed is false on a fresh install', () async {
      expect(await store.isDismissed(), isFalse);
    });

    test('dismiss persists, so a later read comes back true', () async {
      await store.dismiss();

      expect(await store.isDismissed(), isTrue);
    });

    test('the prefix keeps two apps apart on one device', () async {
      const other = SharedPreferencesBackdateNudgeStore(prefix: 'other');

      await store.dismiss();

      expect(await other.isDismissed(), isFalse);
    });

    test('defaults the prefix to the app storage prefix', () {
      expect(
        const SharedPreferencesBackdateNudgeStore().prefix,
        AppConfig.storagePrefix,
      );
    });
  });
}
