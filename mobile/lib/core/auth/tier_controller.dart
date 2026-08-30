import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../network/api_error.dart';
import '../network/network_providers.dart';
import 'auth_controller.dart';
import 'tier.dart';

/// Holds the account's tier (M-3, #48), read from `GET /auth/me`.
///
/// A sibling of [AuthController] rather than a fourth [AuthStatus] value:
/// [AuthStatus] answers one question -- is there a session? -- and every
/// existing `switch` over it (the router's redirect, the splash-vs-shell
/// choice in `app.dart`) would have to grow a case for a fact that has
/// nothing to do with routing. Tier is a second, independent question --
/// *which* signed-in account this is -- so it gets its own provider instead
/// of overloading [AuthStatus] with a dimension it was never about.
///
/// [build] watches [authProvider] rather than fetching once and caching:
/// that is what makes [AuthController.logout] safe by construction rather
/// than by remembering to clear a field. Signing out moves [authProvider]
/// to [AuthStatus.signedOut], which reruns this notifier's [build] and
/// returns [Tier.free] without a fetch -- a stale premium tier cannot
/// survive a logout because there is no mutable state here for it to
/// survive *in*; every read is a fresh computation from the current auth
/// state.
///
/// [refresh] additionally lets a screen pull a tier change into a running
/// app without a restart -- the orchestrator's manual tier-flip demo
/// (`POST /billing/admin/grant`) depends on the client re-checking, not
/// only the backend recomputing on the next request.
class TierController extends AsyncNotifier<Tier> {
  @override
  Future<Tier> build() async {
    // Fetching before a session question is even settled would misreport a
    // startup race ("not signed in yet") as "free" for the wrong reason --
    // and `AppConfig.requireAuth == false`'s default config means most
    // installs sit in [AuthStatus.signedIn] almost immediately anyway, so
    // this gate costs nothing in the common case.
    if (ref.watch(authProvider) != AuthStatus.signedIn) return Tier.free;
    try {
      final me = await ref
          .read(apiClientProvider)
          .getObject(AppConfig.authMePath, meInfoFromJson);
      return me.tier;
    } on ApiError {
      // No entitlement info is a safe default -- this client never renders
      // a premium surface on a guess. A transient failure (server briefly
      // unreachable) self-heals the next time something reruns this
      // provider: [refresh], or the same lifecycle hooks Insights already
      // uses to revalidate its own state.
      return Tier.free;
    }
  }

  /// Re-checks the tier against the backend, without waiting for
  /// [authProvider] to move.
  ///
  /// Mirrors `InsightsController.refresh`'s shape: invalidate, then await
  /// the rebuilt future so a caller can `await` this and know the new value
  /// has landed, swallowing an [ApiError] because it is already reflected in
  /// [state] and this notifier has no snack bar of its own to report it
  /// through.
  Future<void> refresh() async {
    ref.invalidateSelf();
    try {
      await future;
    } on ApiError {
      // Already reflected in `state`.
    }
  }
}

/// The signed-in account's tier, `free` until proven otherwise.
final tierProvider = AsyncNotifierProvider<TierController, Tier>(
  TierController.new,
);
