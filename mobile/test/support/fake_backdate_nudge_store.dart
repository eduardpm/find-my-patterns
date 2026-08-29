import 'package:find_my_patterns/features/today/backdate_nudge_store.dart';

/// An in-memory [BackdateNudgeStore] -- the same shape
/// `FakeComposerDraftStore` has for `ComposerDraftStore`.
class FakeBackdateNudgeStore implements BackdateNudgeStore {
  /// Creates a store that starts already dismissed or not.
  ///
  /// A named parameter (`dismissed:`), not the positional initializing
  /// formal `FakeComposerDraftStore` uses for its own single field: the
  /// field behind it is private, and a positional initializing formal
  /// would make this constructor's argument unlabelled at every call site,
  /// reading as a bare `true`/`false` rather than what it means.
  // ignore: prefer_initializing_formals
  FakeBackdateNudgeStore({bool dismissed = false}) : _dismissed = dismissed;

  bool _dismissed;

  /// How many times [dismiss] was called.
  int dismissCount = 0;

  @override
  Future<bool> isDismissed() async => _dismissed;

  @override
  Future<void> dismiss() async {
    dismissCount++;
    _dismissed = true;
  }
}
