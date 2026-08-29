import 'dart:ui' show ErrorCallback, PlatformDispatcher;

import 'package:find_my_patterns/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('installErrorHandlers', () {
    late FlutterExceptionHandler? previousOnError;
    late ErrorCallback? previousPlatformOnError;

    setUp(() {
      previousOnError = FlutterError.onError;
      previousPlatformOnError = PlatformDispatcher.instance.onError;
    });

    tearDown(() {
      FlutterError.onError = previousOnError;
      PlatformDispatcher.instance.onError = previousPlatformOnError;
    });

    test('installs a handler for framework errors', () {
      installErrorHandlers();
      expect(FlutterError.onError, isNotNull);

      final logs = <String>[];
      _capturePrints(logs, () {
        FlutterError.onError!(
          FlutterErrorDetails(
            exception: StateError('widget went wrong'),
            stack: StackTrace.current,
          ),
        );
      });

      expect(logs.join('\n'), contains('widget went wrong'));
    });

    test('installs a handler for uncaught async errors', () {
      installErrorHandlers();
      expect(PlatformDispatcher.instance.onError, isNotNull);

      final logs = <String>[];
      late bool handled;
      _capturePrints(logs, () {
        handled = PlatformDispatcher.instance.onError!(
          StateError('future went wrong'),
          StackTrace.current,
        );
      });

      // Returning true stops the error from tearing down the isolate.
      expect(handled, isTrue);
      expect(logs.join('\n'), contains('future went wrong'));
    });
  });

  group('reportError', () {
    test('logs the error', () {
      final logs = <String>[];
      _capturePrints(logs, () => reportError(StateError('boom'), null));
      expect(logs.join('\n'), contains('boom'));
    });

    test('logs the stack when there is one', () {
      final logs = <String>[];
      _capturePrints(
        logs,
        () => reportError(StateError('boom'), StackTrace.current),
      );
      expect(logs.length, greaterThan(1));
    });
  });
}

/// Runs [body] with `debugPrint` collected into [logs].
void _capturePrints(List<String> logs, void Function() body) {
  final previous = debugPrint;
  debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
  try {
    body();
  } finally {
    debugPrint = previous;
  }
}
