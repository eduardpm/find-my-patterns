import 'package:find_my_patterns/features/compose/composer_draft.dart';

/// An in-memory [ComposerDraftStore] that records what it was asked to save
/// or clear -- the same shape `FakeSettingsStore` has for `SettingsStore`.
class FakeComposerDraftStore implements ComposerDraftStore {
  /// Creates a store that starts already holding [_draft], standing in for
  /// a draft a previous run of the app already wrote to disk.
  FakeComposerDraftStore([this._draft]);

  ComposerDraft? _draft;

  /// Every draft handed to [save], in order -- lets a test assert on the
  /// debounced autosave's content without waiting for [load] to read it
  /// back.
  final List<ComposerDraft> saved = [];

  /// How many times [clear] was called.
  int clearCount = 0;

  @override
  Future<ComposerDraft?> load() async => _draft;

  @override
  Future<void> save(ComposerDraft draft) async {
    saved.add(draft);
    _draft = draft;
  }

  @override
  Future<void> clear() async {
    clearCount++;
    _draft = null;
  }
}
