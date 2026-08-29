import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'api_client.dart';

/// The jar the session cookie lives in.
///
/// Defaults to an in-memory jar, which is what tests and the widget previews
/// want. `main` overrides it with the value from [createPersistentCookieJar] so
/// that on a real device a signed-in session survives closing the app — the
/// behaviour `AuthController.restore` depends on.
final cookieJarProvider = Provider<CookieJar>((ref) => CookieJar());

/// The app's HTTP core.
final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(cookieJar: ref.watch(cookieJarProvider)),
);

/// Creates a cookie jar backed by the app's private storage directory.
///
/// Called once from `main`, before the first frame, because resolving the
/// directory is asynchronous and platform-specific.
Future<CookieJar> createPersistentCookieJar() async {
  final directory = await getApplicationDocumentsDirectory();
  return PersistCookieJar(storage: FileStorage('${directory.path}/.cookies/'));
}
