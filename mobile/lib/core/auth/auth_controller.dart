import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../config/config_providers.dart';
import '../network/api_error.dart';
import '../network/network_providers.dart';
import '../settings/settings.dart';
import '../settings/settings_controller.dart';

/// Where the user stands with the backend.
enum AuthStatus {
  /// The stored session has not been checked yet; show the splash.
  loading,

  /// No valid session; show the login screen.
  signedOut,

  /// A valid session; show the app.
  signedIn,
}

/// Decides whether the user is signed in, and moves them between states.
class AuthController extends Notifier<AuthStatus> {
  @override
  AuthStatus build() => AuthStatus.loading;

  /// Settles the starting state, once, at startup.
  ///
  /// With [requireAuthProvider] off, the shell is the whole app and this
  /// resolves immediately. With it on: an unset server address means there is
  /// nothing to sign in to, otherwise the session endpoint is probed — a cookie
  /// left by an earlier run signs the user straight back in.
  Future<void> restore() async {
    if (!ref.read(requireAuthProvider)) {
      state = AuthStatus.signedIn;
      return;
    }
    final backend =
        ref.read(settingsProvider).value?.backend ?? BackendAddress.unset;
    if (!backend.isConfigured) {
      state = AuthStatus.signedOut;
      return;
    }
    try {
      await ref.read(apiClientProvider).get(AppConfig.sessionPath);
      state = AuthStatus.signedIn;
    } on ApiError {
      state = AuthStatus.signedOut;
    }
  }

  /// Signs in with [password], by creating a session on the server.
  ///
  /// The server's `Set-Cookie` is kept by the client's jar and rides along on
  /// every later request. Throws an [ApiError] the login screen can show; the
  /// state only moves to [AuthStatus.signedIn] when the server agrees.
  Future<void> login(String password) async {
    await ref
        .read(apiClientProvider)
        .post(AppConfig.sessionPath, body: {'password': password});
    state = AuthStatus.signedIn;
  }

  /// Signs out, locally no matter what.
  ///
  /// The server is told first, but an unreachable server must never trap a user
  /// in a signed-in state on their own device, so the local session is cleared
  /// either way.
  Future<void> logout() async {
    final client = ref.read(apiClientProvider);
    try {
      await client.delete(AppConfig.sessionPath);
    } on ApiError {
      // Expected when the server is unreachable; the local sign-out still runs.
    }
    await client.clearSession();
    state = AuthStatus.signedOut;
  }
}

/// Where the user stands with the backend.
final authProvider = NotifierProvider<AuthController, AuthStatus>(
  AuthController.new,
);
