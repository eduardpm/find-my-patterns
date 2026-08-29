import 'package:find_my_patterns/core/network/network_providers.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/core/settings/settings_controller.dart';
import 'package:find_my_patterns/core/theme/journal_palette.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSettingsStore store;

  ProviderContainer containerWith(FakeSettingsStore store) {
    final container = ProviderContainer(
      overrides: [settingsStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() => store = FakeSettingsStore());

  test('loads the stored settings', () async {
    store = FakeSettingsStore(
      const AppSettings(
        backend: BackendAddress(host: 'stored'),
        themeMode: ThemeModeSetting.dark,
      ),
    );
    final container = containerWith(store);
    final settings = await container.read(settingsProvider.future);
    expect(settings.backend.host, 'stored');
    expect(settings.themeMode, ThemeModeSetting.dark);
  });

  test('the default store is the SharedPreferences one', () {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(settingsStoreProvider),
      isA<SharedPreferencesSettingsStore>(),
    );
  });

  group('saveBackendAddress', () {
    test(
      'validates, stores, and points the HTTP core at the new address',
      () async {
        final container = containerWith(store);
        await container.read(settingsProvider.future);

        final result = await container
            .read(settingsProvider.notifier)
            .saveBackendAddress(rawHost: ' 10.0.2.2 ', rawPort: '9000');

        expect(result, isA<BackendAddressAccepted>());
        expect(store.savedAddresses.single.host, '10.0.2.2');
        expect(store.savedAddresses.single.port, 9000);
        expect(
          container.read(settingsProvider).value?.backend.host,
          '10.0.2.2',
        );
        expect(container.read(apiClientProvider).backend.host, '10.0.2.2');
      },
    );

    test('carries the chosen scheme through', () async {
      final container = containerWith(store);
      await container.read(settingsProvider.future);
      await container
          .read(settingsProvider.notifier)
          .saveBackendAddress(
            rawHost: 'home.example',
            rawPort: '443',
            scheme: BackendScheme.https,
          );
      expect(store.savedAddresses.single.scheme, BackendScheme.https);
    });

    test('writes nothing when the address is rejected', () async {
      final container = containerWith(store);
      await container.read(settingsProvider.future);

      final result = await container
          .read(settingsProvider.notifier)
          .saveBackendAddress(rawHost: '', rawPort: '8000');

      expect(result, isA<BackendAddressRejected>());
      expect(store.savedAddresses, isEmpty);
      expect(container.read(apiClientProvider).backend.isConfigured, isFalse);
    });

    test('a bad port is refused rather than silently defaulted', () async {
      final container = containerWith(store);
      await container.read(settingsProvider.future);

      final result = await container
          .read(settingsProvider.notifier)
          .saveBackendAddress(rawHost: 'h', rawPort: 'not-a-port');

      expect(result, isA<BackendAddressRejected>());
      expect(store.savedAddresses, isEmpty);
    });
  });

  group('saveThemeMode', () {
    test('stores the mode and updates the state', () async {
      final container = containerWith(store);
      await container.read(settingsProvider.future);

      await container
          .read(settingsProvider.notifier)
          .saveThemeMode(ThemeModeSetting.dark);

      expect(store.savedThemeModes.single, ThemeModeSetting.dark);
      expect(
        container.read(settingsProvider).value?.themeMode,
        ThemeModeSetting.dark,
      );
    });
  });

  group('savePalette', () {
    test('stores the palette and updates the state', () async {
      final container = containerWith(store);
      await container.read(settingsProvider.future);

      await container
          .read(settingsProvider.notifier)
          .savePalette(JournalPalette.sage);

      expect(store.savedPalettes.single, JournalPalette.sage);
      expect(
        container.read(settingsProvider).value?.palette,
        JournalPalette.sage,
      );
    });
  });
}
