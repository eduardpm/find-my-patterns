import 'package:find_my_patterns/features/compose/first_pattern_notified_store.dart';

/// An in-memory [FirstPatternNotifiedStore] -- the same shape
/// `FakeBackdateNudgeStore` has for `BackdateNudgeStore`.
class FakeFirstPatternNotifiedStore implements FirstPatternNotifiedStore {
  /// Creates a store that starts already notified or not.
  ///
  /// Defaults to already notified: most of this suite has nothing to do
  /// with the first-pattern celebration (#38), and a pre-notified store
  /// makes `EntryComposerController._checkFirstPattern` short-circuit
  /// before ever fetching insights, so every confirm-feelings test that
  /// predates this feature keeps seeing exactly the HTTP replies it always
  /// scripted. A test exercising the celebration itself constructs one
  /// with `notified: false`.
  // ignore: prefer_initializing_formals
  FakeFirstPatternNotifiedStore({bool notified = true}) : _notified = notified;

  bool _notified;

  /// How many times [markNotified] was called.
  int markNotifiedCallCount = 0;

  @override
  Future<bool> hasNotified() async => _notified;

  @override
  Future<void> markNotified() async {
    markNotifiedCallCount++;
    _notified = true;
  }
}
