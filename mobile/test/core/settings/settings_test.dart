import 'package:find_my_patterns/core/config/app_config.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/core/theme/journal_palette.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BackendScheme', () {
    test('fromId resolves known ids', () {
      expect(BackendScheme.fromId('http'), BackendScheme.http);
      expect(BackendScheme.fromId('https'), BackendScheme.https);
    });

    test('fromId falls back to http for anything else', () {
      expect(BackendScheme.fromId('ftp'), BackendScheme.http);
      expect(BackendScheme.fromId(null), BackendScheme.http);
    });

    test('every scheme has a label', () {
      for (final scheme in BackendScheme.values) {
        expect(scheme.label, isNotEmpty);
      }
    });
  });

  group('BackendAddress', () {
    test('origin joins scheme, host and port', () {
      const address = BackendAddress(host: '192.168.1.20');
      expect(address.origin, 'http://192.168.1.20:8000');
      expect(
        const BackendAddress(
          scheme: BackendScheme.https,
          host: 'home.example',
          port: 443,
        ).origin,
        'https://home.example:443',
      );
    });

    test('isConfigured is false until a host is set', () {
      expect(BackendAddress.unset.isConfigured, isFalse);
      expect(const BackendAddress(host: '10.0.2.2').isConfigured, isTrue);
    });

    test('unset uses the configured default port', () {
      expect(BackendAddress.unset.port, AppConfig.defaultPort);
    });

    test('copyWith replaces only what it is given', () {
      const address = BackendAddress(host: 'a', port: 1);
      expect(
        address.copyWith(host: 'b'),
        const BackendAddress(host: 'b', port: 1),
      );
      expect(
        address.copyWith(port: 2),
        const BackendAddress(host: 'a', port: 2),
      );
      expect(
        address.copyWith(scheme: BackendScheme.https).scheme,
        BackendScheme.https,
      );
      expect(address.copyWith(), address);
    });

    test('equality and hashCode cover every field', () {
      const a = BackendAddress(host: 'h', port: 1);
      expect(a, const BackendAddress(host: 'h', port: 1));
      expect(a.hashCode, const BackendAddress(host: 'h', port: 1).hashCode);
      expect(a, isNot(const BackendAddress(host: 'h', port: 2)));
      expect(a, isNot(const BackendAddress(host: 'x', port: 1)));
      expect(
        a,
        isNot(
          const BackendAddress(scheme: BackendScheme.https, host: 'h', port: 1),
        ),
      );
      expect(a, isNot(const Object()));
    });

    test('toString is the origin', () {
      expect(const BackendAddress(host: 'h').toString(), 'http://h:8000');
    });
  });

  group('BackendAddress.parse', () {
    BackendAddress accept(String host, String port, [BackendScheme? scheme]) {
      final result = BackendAddress.parse(
        rawHost: host,
        rawPort: port,
        scheme: scheme ?? BackendScheme.http,
      );
      return (result as BackendAddressAccepted).address;
    }

    String reject(String host, String port) {
      final result = BackendAddress.parse(rawHost: host, rawPort: port);
      return (result as BackendAddressRejected).message;
    }

    test('trims whitespace around the host and port', () {
      expect(accept('  10.0.2.2  ', ' 9000 ').host, '10.0.2.2');
      expect(accept('  10.0.2.2  ', ' 9000 ').port, 9000);
    });

    test('strips a pasted scheme and adopts it', () {
      final parsed = accept('https://home.example', '443');
      expect(parsed.host, 'home.example');
      expect(parsed.scheme, BackendScheme.https);
    });

    test('strips a pasted http scheme', () {
      expect(accept('http://10.0.2.2', '8000').host, '10.0.2.2');
    });

    test('matches a pasted scheme case-insensitively', () {
      expect(accept('HTTPS://home.example', '443').scheme, BackendScheme.https);
    });

    test('strips trailing slashes', () {
      expect(accept('http://10.0.2.2///', '8000').host, '10.0.2.2');
    });

    test('keeps the chosen scheme when none is pasted', () {
      expect(
        accept('home.example', '443', BackendScheme.https).scheme,
        BackendScheme.https,
      );
    });

    test('rejects an empty host', () {
      expect(reject('', '8000'), contains('Enter a host'));
      expect(reject('   ', '8000'), contains('Enter a host'));
      expect(reject('https://', '8000'), contains('Enter a host'));
    });

    test('rejects a host containing spaces', () {
      expect(
        reject('10.0.2.2 8000', '8000'),
        contains('cannot contain spaces'),
      );
    });

    test('rejects a port that is not a number', () {
      expect(reject('h', 'abc'), contains('not a port number'));
      expect(reject('h', ''), contains('not a port number'));
    });

    test('rejects a port outside the valid range', () {
      expect(reject('h', '0'), contains('between'));
      expect(reject('h', '65536'), contains('between'));
      expect(reject('h', '-1'), contains('between'));
    });

    test('accepts the extremes of the valid range', () {
      expect(accept('h', '1').port, BackendAddress.minPort);
      expect(accept('h', '65535').port, BackendAddress.maxPort);
    });
  });

  group('ThemeModeSetting', () {
    test('fromId resolves known ids', () {
      expect(ThemeModeSetting.fromId('light'), ThemeModeSetting.light);
      expect(ThemeModeSetting.fromId('dark'), ThemeModeSetting.dark);
      expect(ThemeModeSetting.fromId('system'), ThemeModeSetting.system);
    });

    test('fromId falls back to system for unknown values', () {
      expect(ThemeModeSetting.fromId('paper'), ThemeModeSetting.system);
      expect(ThemeModeSetting.fromId(null), ThemeModeSetting.system);
    });

    test('every mode has a label', () {
      for (final mode in ThemeModeSetting.values) {
        expect(mode.label, isNotEmpty);
      }
    });
  });

  group('ReminderTime', () {
    test('defaults to off', () {
      expect(const ReminderTime(hour: 9, minute: 0).enabled, isFalse);
    });

    test('copyWith replaces only what it is given', () {
      const reminder = ReminderTime(hour: 9, minute: 0);
      expect(
        reminder.copyWith(hour: 10),
        const ReminderTime(hour: 10, minute: 0),
      );
      expect(
        reminder.copyWith(minute: 30),
        const ReminderTime(hour: 9, minute: 30),
      );
      expect(
        reminder.copyWith(enabled: true),
        const ReminderTime(hour: 9, minute: 0, enabled: true),
      );
      expect(reminder.copyWith(), reminder);
    });

    test('equality and hashCode cover every field', () {
      const a = ReminderTime(hour: 9, minute: 0, enabled: true);
      expect(a, const ReminderTime(hour: 9, minute: 0, enabled: true));
      expect(
        a.hashCode,
        const ReminderTime(hour: 9, minute: 0, enabled: true).hashCode,
      );
      expect(a, isNot(const ReminderTime(hour: 10, minute: 0, enabled: true)));
      expect(a, isNot(const ReminderTime(hour: 9, minute: 5, enabled: true)));
      expect(a, isNot(const ReminderTime(hour: 9, minute: 0)));
      expect(a, isNot(const Object()));
    });

    test('reads as a zero-padded time with its on/off state', () {
      expect(
        const ReminderTime(hour: 9, minute: 0, enabled: true).toString(),
        '09:00 (on)',
      );
      expect(
        const ReminderTime(hour: 21, minute: 5).toString(),
        '21:05 (off)',
      );
    });

    test('maxCount is six', () {
      expect(ReminderTime.maxCount, 6);
    });
  });

  group('kDefaultReminders', () {
    test('suggests a morning and an evening slot, both off', () {
      expect(kDefaultReminders, [
        const ReminderTime(hour: 9, minute: 0),
        const ReminderTime(hour: 21, minute: 0),
      ]);
      expect(kDefaultReminders.every((r) => !r.enabled), isTrue);
    });
  });

  group('AppSettings', () {
    test('defaults to the default palette', () {
      expect(const AppSettings().palette, JournalPalette.defaultPalette);
    });

    test('defaults to the default reminder suggestions', () {
      expect(const AppSettings().reminders, kDefaultReminders);
    });

    test('copyWith replaces only what it is given', () {
      const settings = AppSettings();
      expect(
        settings.copyWith(themeMode: ThemeModeSetting.dark).themeMode,
        ThemeModeSetting.dark,
      );
      expect(
        settings
            .copyWith(backend: const BackendAddress(host: 'h'))
            .backend
            .host,
        'h',
      );
      expect(
        settings.copyWith(palette: JournalPalette.sage).palette,
        JournalPalette.sage,
      );
      expect(
        settings.copyWith(reminders: const []).reminders,
        isEmpty,
      );
      expect(settings.copyWith(), settings);
    });

    test('equality and hashCode cover every field', () {
      const a = AppSettings(
        themeMode: ThemeModeSetting.dark,
        palette: JournalPalette.sage,
      );
      expect(
        a,
        const AppSettings(
          themeMode: ThemeModeSetting.dark,
          palette: JournalPalette.sage,
        ),
      );
      expect(
        a.hashCode,
        const AppSettings(
          themeMode: ThemeModeSetting.dark,
          palette: JournalPalette.sage,
        ).hashCode,
      );
      expect(a, isNot(const AppSettings()));
      expect(
        a,
        isNot(
          const AppSettings(
            backend: BackendAddress(host: 'h'),
            themeMode: ThemeModeSetting.dark,
            palette: JournalPalette.sage,
          ),
        ),
      );
      expect(
        a,
        isNot(
          const AppSettings(
            themeMode: ThemeModeSetting.dark,
            palette: JournalPalette.dusk,
          ),
        ),
      );
      expect(
        a,
        isNot(
          AppSettings(
            themeMode: ThemeModeSetting.dark,
            palette: JournalPalette.sage,
            reminders: const [ReminderTime(hour: 1, minute: 1)],
          ),
        ),
      );
      expect(a, isNot(const Object()));
    });
  });

  group('SharedPreferencesSettingsStore', () {
    const store = SharedPreferencesSettingsStore(prefix: 'test');

    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('load returns defaults on a fresh install', () async {
      final settings = await store.load();
      expect(settings.backend, BackendAddress.unset);
      expect(settings.themeMode, ThemeModeSetting.system);
      expect(settings.palette, JournalPalette.defaultPalette);
    });

    test('round-trips the backend address including the scheme', () async {
      const address = BackendAddress(
        scheme: BackendScheme.https,
        host: 'home.example',
        port: 443,
      );
      await store.saveBackendAddress(address);
      expect((await store.load()).backend, address);
    });

    test('round-trips the theme mode', () async {
      await store.saveThemeMode(ThemeModeSetting.dark);
      expect((await store.load()).themeMode, ThemeModeSetting.dark);
    });

    test('round-trips the palette', () async {
      await store.savePalette(JournalPalette.dusk);
      expect((await store.load()).palette, JournalPalette.dusk);
    });

    test('an unrecognised stored palette falls back to the default', () async {
      SharedPreferences.setMockInitialValues({
        'test.appearance_palette': 'sepia',
      });
      expect((await store.load()).palette, JournalPalette.defaultPalette);
    });

    test(
      'load returns the default reminder suggestions on a fresh install',
      () async {
        expect((await store.load()).reminders, kDefaultReminders);
      },
    );

    test(
      'round-trips a list of reminders, including the enabled flag',
      () async {
        const reminders = [
          ReminderTime(hour: 7, minute: 15, enabled: true),
          ReminderTime(hour: 13, minute: 0),
          ReminderTime(hour: 22, minute: 45, enabled: true),
        ];
        await store.saveReminders(reminders);
        expect((await store.load()).reminders, reminders);
      },
    );

    test(
      'an empty saved list is read back as empty, not the default '
      'suggestions',
      () async {
        await store.saveReminders(const []);
        expect((await store.load()).reminders, isEmpty);
      },
    );

    test(
      'unreadable stored JSON falls back to the default suggestions',
      () async {
        SharedPreferences.setMockInitialValues({
          'test.reminders': 'not json',
        });
        expect((await store.load()).reminders, kDefaultReminders);
      },
    );

    test(
      'a stored value that is not a JSON list falls back to the default '
      'suggestions',
      () async {
        SharedPreferences.setMockInitialValues({'test.reminders': '{}'});
        expect((await store.load()).reminders, kDefaultReminders);
      },
    );

    test('the prefix keeps two apps apart on one device', () async {
      const other = SharedPreferencesSettingsStore(prefix: 'other');
      await store.saveThemeMode(ThemeModeSetting.dark);
      expect((await other.load()).themeMode, ThemeModeSetting.system);
    });

    test('defaults the prefix to the app storage prefix', () {
      expect(
        const SharedPreferencesSettingsStore().prefix,
        AppConfig.storagePrefix,
      );
    });
  });
}
