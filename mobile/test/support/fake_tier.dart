import 'package:find_my_patterns/core/auth/tier.dart';
import 'package:find_my_patterns/core/auth/tier_controller.dart';

/// A [TierController] pinned to [value], for a test that needs a specific
/// tier without driving `authProvider` through a real sign-in or scripting
/// a `/auth/me` reply through the fake HTTP adapter.
///
/// Overridden as `tierProvider.overrideWith(() => FixedTierController(...))`
/// -- `AsyncNotifierProvider.overrideWith` takes the notifier's constructor,
/// not a value, which is what a plain `overrideWithValue` cannot express
/// for a provider whose state is itself asynchronous.
class FixedTierController extends TierController {
  /// Creates a controller whose [build] resolves to [value] immediately.
  FixedTierController(this.value);

  /// The tier every read of this provider resolves to.
  final Tier value;

  @override
  Future<Tier> build() async => value;
}
