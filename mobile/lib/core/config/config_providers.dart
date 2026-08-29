import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_config.dart';

/// Whether sign-in gates the app.
///
/// Defaults to [AppConfig.requireAuth]. It is a provider rather than a bare
/// constant so that both modes are reachable at runtime: an app can decide late
/// (a backend that reports whether it wants a password, say), and the tests can
/// exercise the gated and ungated paths in the same run.
final requireAuthProvider = Provider<bool>((ref) => AppConfig.requireAuth);
