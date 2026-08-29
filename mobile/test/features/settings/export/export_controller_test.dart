import 'dart:io';

import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/features/settings/export/export_controller.dart';
import 'package:find_my_patterns/features/settings/export/export_format.dart';
import 'package:find_my_patterns/features/settings/export/export_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_http.dart';
import '../../../support/harness.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('export-controller-test-');
  });
  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// Builds a container wired to [adapter], staging exports in [tempDir] and
  /// recording every call the controller makes to the share sheet in
  /// [sharedPaths]/[sharedMimeTypes] instead of touching a platform channel.
  ///
  /// The harness needs a configured backend — `Harness`'s own default
  /// (`AppSettings()`) leaves it unset, which would make every request fail
  /// with `BackendNotConfigured` before the fake adapter ever sees it.
  ProviderContainer containerFor(
    FakeHttpAdapter adapter, {
    required List<String> sharedPaths,
    required List<String> sharedMimeTypes,
    Directory? stageIn,
  }) {
    final harness = Harness(
      adapter: adapter,
      settings: const AppSettings(backend: BackendAddress(host: '10.0.2.2')),
    );
    final container = ProviderContainer(
      overrides: [
        ...harness.baseOverrides,
        exportCacheDirectoryProvider.overrideWithValue(
          () async => stageIn ?? tempDir,
        ),
        shareExportProvider.overrideWithValue((
          path, {
          required mimeType,
        }) async {
          sharedPaths.add(path);
          sharedMimeTypes.add(mimeType);
        }),
      ],
      retry: Harness.noRetry,
    );
    return container;
  }

  test('starts idle', () {
    final container = containerFor(
      FakeHttpAdapter([]),
      sharedPaths: [],
      sharedMimeTypes: [],
    );
    addTearDown(container.dispose);
    expect(container.read(exportControllerProvider), isA<ExportIdle>());
  });

  test(
    'downloads the diary, writes it to the staging directory under the '
    "server's filename, and hands the file to the share sheet",
    () async {
      final adapter = FakeHttpAdapter([
        const FakeReply.raw(
          200,
          '## 2026-08-28 — 11:11 PM\n\nQuiet day.\n',
          headers: {
            'content-disposition': [
              'attachment; filename="find-my-patterns-export-2026-08-28.md"',
            ],
          },
        ),
      ]);
      final sharedPaths = <String>[];
      final sharedMimeTypes = <String>[];
      final container = containerFor(
        adapter,
        sharedPaths: sharedPaths,
        sharedMimeTypes: sharedMimeTypes,
      );
      addTearDown(container.dispose);

      await container
          .read(exportControllerProvider.notifier)
          .export(ExportFormat.markdown);

      expect(container.read(exportControllerProvider), isA<ExportIdle>());
      expect(
        sharedPaths.single,
        '${tempDir.path}/find-my-patterns-export-2026-08-28.md',
      );
      expect(sharedMimeTypes.single, 'text/markdown');
      expect(
        File(sharedPaths.single).readAsStringSync(),
        '## 2026-08-28 — 11:11 PM\n\nQuiet day.\n',
      );
      expect(adapter.requests.single.uri.path, '/export');
      expect(adapter.requests.single.uri.queryParameters, {
        'format': 'markdown',
      });
    },
  );

  test('falls back to a default filename when the server sends none', () async {
    final adapter = FakeHttpAdapter([
      const FakeReply.raw(200, '{"schema_version":1}'),
    ]);
    final sharedPaths = <String>[];
    final container = containerFor(
      adapter,
      sharedPaths: sharedPaths,
      sharedMimeTypes: [],
    );
    addTearDown(container.dispose);

    await container
        .read(exportControllerProvider.notifier)
        .export(ExportFormat.json);

    expect(sharedPaths.single, '${tempDir.path}/find-my-patterns-export.json');
  });

  test(
    'an API failure moves the state to ExportError and never reaches the '
    'share sheet',
    () async {
      final adapter = FakeHttpAdapter([const FakeReply(503)]);
      final sharedPaths = <String>[];
      final container = containerFor(
        adapter,
        sharedPaths: sharedPaths,
        sharedMimeTypes: [],
      );
      addTearDown(container.dispose);

      await container
          .read(exportControllerProvider.notifier)
          .export(ExportFormat.json);

      final state = container.read(exportControllerProvider);
      expect(state, isA<ExportError>());
      expect((state as ExportError).message, contains('503'));
      expect(sharedPaths, isEmpty);
    },
  );

  test(
    'a filesystem failure while staging the file also becomes ExportError',
    () async {
      final adapter = FakeHttpAdapter([const FakeReply.raw(200, 'content')]);
      final sharedPaths = <String>[];
      final container = containerFor(
        adapter,
        sharedPaths: sharedPaths,
        sharedMimeTypes: [],
        // A directory that cannot exist: writing into it throws
        // FileSystemException rather than succeeding.
        stageIn: Directory('/no/such/export-staging-directory'),
      );
      addTearDown(container.dispose);

      await container
          .read(exportControllerProvider.notifier)
          .export(ExportFormat.json);

      expect(container.read(exportControllerProvider), isA<ExportError>());
      expect(sharedPaths, isEmpty);
    },
  );

  test('reset clears an error back to idle', () async {
    final adapter = FakeHttpAdapter([const FakeReply(500)]);
    final container = containerFor(
      adapter,
      sharedPaths: [],
      sharedMimeTypes: [],
    );
    addTearDown(container.dispose);

    await container
        .read(exportControllerProvider.notifier)
        .export(ExportFormat.json);
    expect(container.read(exportControllerProvider), isA<ExportError>());

    container.read(exportControllerProvider.notifier).reset();
    expect(container.read(exportControllerProvider), isA<ExportIdle>());
  });
}
