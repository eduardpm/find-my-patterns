import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/network/network_providers.dart';
import 'core/network/retry_policy.dart';

/// Starts the app.
///
/// Three things happen before the first frame: the binding is initialised, the
/// error handlers are installed, and the persistent cookie jar is opened so a
/// session left by an earlier run is available to `AuthController.restore`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installErrorHandlers();
  final cookieJar = await createPersistentCookieJar();
  runApp(
    ProviderScope(
      overrides: [cookieJarProvider.overrideWithValue(cookieJar)],
      // One retry policy for the whole app, rather than each screen deciding.
      // See [apiRetryPolicy] for why the framework's default is wrong here.
      retry: apiRetryPolicy,
      child: const FindMyPatternsApp(),
    ),
  );
}

/// Routes every uncaught error to [reportError].
///
/// Without this, an error thrown outside a widget build — in a `Future` that
/// nobody awaited, or on a platform channel — is swallowed in release builds
/// and the app simply misbehaves with no trace.
void installErrorHandlers() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    reportError(details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    reportError(error, stack);
    return true;
  };
}

/// Records an uncaught [error].
///
/// Deliberately just a debug print: each app forked from this base swaps in
/// whatever crash reporter it uses, in this one place.
void reportError(Object error, StackTrace? stack) {
  debugPrint('Uncaught error: $error');
  if (stack != null) debugPrintStack(stackTrace: stack);
}
