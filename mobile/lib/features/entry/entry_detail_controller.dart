import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diary/diary_providers.dart';
import '../../core/diary/entries_api.dart';
import '../../core/diary/entry.dart';
import '../../core/diary/feeling.dart';
import '../../core/diary/pattern.dart';
import '../../core/network/api_error.dart';

/// A save or delete refused because this screen's copy was out of date.
///
/// `mine` is what the user had written and tried to save. It is retained
/// deliberately: losing what someone just typed into a diary is the worst
/// failure this app can have, so the text survives the rejection and only
/// ever leaves the screen because the user said so — see
/// [EntryDetailController]'s `discardMine`. `current` is the entry as it is
/// actually stored, read from the conflict response itself rather than a
/// second round trip.
typedef EntryConflict = ({
  String mine,
  List<Feeling> myFeelings,
  Entry current,
});

/// Everything the entry-detail screen renders.
///
/// [isEditing] starts false: the screen used to open straight into a text
/// field, which made reading back what you wrote the same act as being one
/// stray tap away from changing it. Reading is now the default; editing is
/// entered and left deliberately.
///
/// [conflict] is set only when a save or delete was refused as stale.
/// Holding both sides here — rather than resolving anything automatically —
/// is the one rule this whole screen exists to enforce; see
/// [EntryDetailController].
class const EntryDetailState({
  final Entry? entry,
  final String editedText = '',
  final List<Feeling> editedFeelings = const [],

  /// The optional rating on each chosen feeling, as edited on this screen.
  final Map<String, int> editedIntensities = const {},
  final bool isEditing = false,

  /// The backend-served vocabulary; empty until it has loaded.
  final List<FeelingGroup> feelingGroups = const [],

  /// The engine's thresholds, including the intensity scale. Backend-owned;
  /// this placeholder never itself appears as a fact on screen.
  final EngineConstants constants = EngineConstants.placeholder,

  /// What the diary already says about this entry's topics, once it has
  /// been saved.
  final List<PatternEcho> echoes = const [],
  final bool hasLoaded = false,
  final bool isSaving = false,
  final String? errorMessage,
  final bool deleted = false,

  /// Set for exactly as long as it takes to show one confirmation, then
  /// cleared by the screen. Saving used to do nothing visible at all: the
  /// button said "Saving…" for an instant and the screen stayed exactly as
  /// it was, indistinguishable from a save that silently failed.
  final String? savedMessage,
  final EntryConflict? conflict,
}) {
  /// Distinguishes "leave this field alone" from "clear it" in [copyWith].
  static const Object _unset = Object();

  /// A copy of this state with the given fields replaced.
  ///
  /// Pass `errorMessage`/`savedMessage`/`conflict: null` to explicitly
  /// clear one of them; omit it to leave the current value alone.
  EntryDetailState copyWith({
    Entry? entry,
    String? editedText,
    List<Feeling>? editedFeelings,
    Map<String, int>? editedIntensities,
    bool? isEditing,
    List<FeelingGroup>? feelingGroups,
    EngineConstants? constants,
    List<PatternEcho>? echoes,
    bool? hasLoaded,
    bool? isSaving,
    Object? errorMessage = _unset,
    bool? deleted,
    Object? savedMessage = _unset,
    Object? conflict = _unset,
  }) => EntryDetailState(
    entry: entry ?? this.entry,
    editedText: editedText ?? this.editedText,
    editedFeelings: editedFeelings ?? this.editedFeelings,
    editedIntensities: editedIntensities ?? this.editedIntensities,
    isEditing: isEditing ?? this.isEditing,
    feelingGroups: feelingGroups ?? this.feelingGroups,
    constants: constants ?? this.constants,
    echoes: echoes ?? this.echoes,
    hasLoaded: hasLoaded ?? this.hasLoaded,
    isSaving: isSaving ?? this.isSaving,
    errorMessage: identical(errorMessage, _unset)
        ? this.errorMessage
        : errorMessage as String?,
    deleted: deleted ?? this.deleted,
    savedMessage: identical(savedMessage, _unset)
        ? this.savedMessage
        : savedMessage as String?,
    conflict: identical(conflict, _unset)
        ? this.conflict
        : conflict as EntryConflict?,
  );
}

/// Reads, edits and deletes one entry — and holds the line on what happens
/// when another device has moved it on since this screen loaded.
///
/// A save or delete refused with [EntryOutOfDate] means the user has a
/// decision to make, and their words are held on screen until they make it:
/// see [save], [delete] and the three resolutions, [retryWithCurrentVersion],
/// [discardMine] and [carryMineAcross]. There is deliberately no fourth
/// option that merges the two copies — combining them would produce text
/// the user never wrote, which in a diary is worse than either version
/// winning outright. A conflict is never resolved automatically.
class EntryDetailController extends Notifier<EntryDetailState> {
  /// Creates the controller for entry [entryId].
  ///
  /// Fetches through `GET /entries/{id}` — one request for the one entry
  /// this screen shows, rather than the whole day's list filtered down to
  /// it.
  EntryDetailController(this.entryId);

  /// The entry this screen shows.
  final String entryId;

  @override
  EntryDetailState build() {
    Future.microtask(_load);
    return const EntryDetailState();
  }

  static String _messageFor(ApiError error) => switch (error) {
    BackendNotConfigured() => 'Set your server address in Settings.',
    NetworkFailure() => 'Could not reach the server.',
    Unauthorized() => 'Please sign in again.',
    HttpFailure(:final statusCode) => 'Server error ($statusCode).',
  };

  Future<void> _load() async {
    try {
      final entry = await ref.read(entriesApiProvider).getById(entryId);
      if (!ref.mounted) return;
      state = state.copyWith(
        entry: entry,
        editedText: entry.rawText,
        editedFeelings: entry.feelings,
        editedIntensities: entry.feelingIntensities,
        hasLoaded: true,
      );
    } on ApiError catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(hasLoaded: true, errorMessage: _messageFor(error));
    }
    // Fetched after the entry: `getById` above already primed the shared
    // feelings-catalog cache resolving its own feeling keys, so this reuses
    // that cache rather than costing a second request.
    await _loadFeelingGroups();
    await _loadConstants();
  }

  Future<void> _loadFeelingGroups() async {
    try {
      final groups = await ref.read(feelingsApiProvider).groups();
      if (!ref.mounted) return;
      state = state.copyWith(feelingGroups: groups);
    } on ApiError {
      // The chip row is populated by the time an entry has been saved; a
      // failure here is silent because editing the text is what matters,
      // and the same failure would surface there.
    }
  }

  Future<void> _loadConstants() async {
    try {
      // The intensity scale is the backend's, like every other threshold
      // this client shows.
      final result = await ref.read(insightsApiProvider).insights();
      if (!ref.mounted) return;
      state = state.copyWith(constants: result.constants);
    } on ApiError {
      // The placeholder stands in until the next successful load.
    }
  }

  /// Records the in-progress edit to the entry's text.
  void updateText(String text) => state = state.copyWith(editedText: text);

  /// Records the in-progress edit to the entry's feelings.
  ///
  /// Unpicking a feeling drops its rating along with it — a rating belongs
  /// to its feeling, not to whichever word is chosen next.
  void updateFeelings(List<Feeling> feelings) {
    final remainingKeys = {for (final feeling in feelings) feeling.key};
    state = state.copyWith(
      editedFeelings: feelings,
      editedIntensities: {
        for (final entry in state.editedIntensities.entries)
          if (remainingKeys.contains(entry.key)) entry.key: entry.value,
      },
    );
  }

  /// Sets or clears [feeling]'s rating.
  void updateIntensity(Feeling feeling, int? intensity) {
    final updated = Map<String, int>.of(state.editedIntensities);
    if (intensity == null) {
      updated.remove(feeling.key);
    } else {
      updated[feeling.key] = intensity;
    }
    state = state.copyWith(editedIntensities: updated);
  }

  /// Opens the entry for editing, starting from exactly what is stored.
  void startEditing() {
    final entry = state.entry;
    if (entry == null) return;
    state = state.copyWith(
      isEditing: true,
      editedText: entry.rawText,
      editedFeelings: entry.feelings,
      editedIntensities: entry.feelingIntensities,
    );
  }

  /// Leaves the editor, discarding the edit. Nothing was sent, so nothing
  /// needs undoing.
  void cancelEditing() {
    final entry = state.entry;
    if (entry == null) return;
    state = state.copyWith(
      isEditing: false,
      editedText: entry.rawText,
      editedFeelings: entry.feelings,
      editedIntensities: entry.feelingIntensities,
    );
  }

  /// Clears the saved confirmation once the screen has shown it.
  void dismissSavedMessage() => state = state.copyWith(savedMessage: null);

  /// Clears the current error message once the screen has shown it.
  void dismissError() => state = state.copyWith(errorMessage: null);

  /// Dismisses the echo panel. Affects only this screen; it never touches
  /// the pattern the echo describes.
  void dismissEchoes() => state = state.copyWith(echoes: const []);

  /// Saves the edit.
  ///
  /// [version] is the version this screen loaded by default, or the one
  /// carried out of a conflict when the user chose to retry — see
  /// [retryWithCurrentVersion]. If another client has moved the entry on
  /// since then, this comes back as [EntryOutOfDate] and nothing is
  /// overwritten.
  Future<void> save({int? version}) async {
    final entry = state.entry;
    if (entry == null) return;
    state = state.copyWith(isSaving: true, errorMessage: null);
    try {
      final result = await ref
          .read(entriesApiProvider)
          .update(
            id: entry.id,
            version: version ?? entry.version,
            text: state.editedText.trim(),
            feelings: state.editedFeelings,
            intensities: state.editedIntensities,
          );
      if (!ref.mounted) return;
      switch (result) {
        case EntryUpdated(:final entry):
          // Back to reading, and say so. The editor closing is the
          // substantive confirmation; the message is what makes it
          // unambiguous rather than something inferred from the screen
          // having changed.
          state = state.copyWith(
            isSaving: false,
            entry: entry,
            conflict: null,
            isEditing: false,
            editedText: entry.rawText,
            editedFeelings: entry.feelings,
            editedIntensities: entry.feelingIntensities,
            savedMessage: 'Entry saved',
          );
          ref.read(diaryWriteSignalProvider.notifier).bump();
          await _loadEchoes(entry.id);
        case EntryOutOfDate(:final current):
          state = state.copyWith(
            isSaving: false,
            conflict: (
              mine: state.editedText,
              myFeelings: state.editedFeelings,
              current: current,
            ),
          );
        case EntryRemoved():
          // `update` never actually returns this -- only `delete` does --
          // but `EntryMutation` is sealed and this switch must stay
          // exhaustive.
          state = state.copyWith(isSaving: false);
      }
    } on ApiError catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(isSaving: false, errorMessage: _messageFor(error));
    }
  }

  Future<void> _loadEchoes(String entryId) async {
    // Asked for only once the entry is stored, never while it is being
    // written -- an app that echoed a pattern back mid-edit would be
    // shaping the evidence it then counts. A failure here is silent: the
    // edit itself already saved, which is what the user was doing.
    try {
      final echoes = await ref.read(entriesApiProvider).echo(entryId);
      if (!ref.mounted) return;
      state = state.copyWith(echoes: echoes);
    } on ApiError {
      // Silent -- see above.
    }
  }

  /// Deletes the entry. A stale delete is refused the same way a stale save
  /// is, and shows the same conflict panel — so the user can decide again
  /// with current information rather than destroying a change they never
  /// saw.
  Future<void> delete() async {
    final entry = state.entry;
    if (entry == null) return;
    state = state.copyWith(isSaving: true, errorMessage: null);
    try {
      final result = await ref
          .read(entriesApiProvider)
          .deleteById(id: entry.id, version: entry.version);
      if (!ref.mounted) return;
      switch (result) {
        case EntryRemoved():
          state = state.copyWith(isSaving: false, deleted: true);
          ref.read(diaryWriteSignalProvider.notifier).bump();
        case EntryOutOfDate(:final current):
          state = state.copyWith(
            isSaving: false,
            conflict: (
              mine: state.editedText,
              myFeelings: state.editedFeelings,
              current: current,
            ),
          );
        case EntryUpdated():
          // `delete` never actually returns this; exhaustiveness only.
          state = state.copyWith(isSaving: false);
      }
    } on ApiError catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(isSaving: false, errorMessage: _messageFor(error));
    }
  }

  /// "Keep mine (overwrite)": retries the save against the version the
  /// conflict reported, which is current by definition.
  Future<void> retryWithCurrentVersion() async {
    final conflict = state.conflict;
    if (conflict == null) return;
    state = state.copyWith(conflict: null);
    await save(version: conflict.current.version);
  }

  /// "Discard mine and use theirs": adopts what the server has and drops
  /// the local edit — only on request, never automatically.
  void discardMine() {
    final conflict = state.conflict;
    if (conflict == null) return;
    state = state.copyWith(
      conflict: null,
      entry: conflict.current,
      editedText: conflict.current.rawText,
      editedFeelings: conflict.current.feelings,
      editedIntensities: conflict.current.feelingIntensities,
    );
  }

  /// "Keep editing mine": puts the user's own words back in the editor
  /// against the now-current entry, so they can merge by hand. The two
  /// copies are never combined automatically — that would produce text the
  /// user never wrote.
  void carryMineAcross() {
    final conflict = state.conflict;
    if (conflict == null) return;
    state = state.copyWith(
      conflict: null,
      entry: conflict.current,
      editedText: conflict.mine,
      editedFeelings: conflict.myFeelings,
    );
  }
}

/// The state behind the entry-detail screen, keyed by entry id.
final entryDetailControllerProvider =
    NotifierProvider.family<EntryDetailController, EntryDetailState, String>(
      EntryDetailController.new,
    );
