import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../../core/diary/calendar_date.dart';
import '../../core/network/api_client.dart';

/// Which flow a saved draft was written in.
///
/// Stored as a stable id rather than an enum index or name, the same way
/// `BackendScheme` and `ThemeModeSetting` are -- an id changes only when
/// someone changes it on purpose.
enum ComposerDraftMode {
  /// The guided-question flow.
  guided('guided'),

  /// Freeform writing.
  freeform('freeform');

  const ComposerDraftMode(this.id);

  /// The value written to device storage.
  final String id;

  /// The mode with the given [id], or null if unrecognised -- an
  /// unreadable draft is discarded rather than guessed at.
  static ComposerDraftMode? fromId(String? id) =>
      ComposerDraftMode.values.where((mode) => mode.id == id).firstOrNull;
}

/// Whether a composition with these fields has anything in it worth
/// restoring, warning about losing, or bothering to persist.
///
/// A step reached past the first counts even when its own field is
/// currently blank: reaching it required a mandatory answer earlier in the
/// guided flow, and that answer may since have been cleared without the
/// step going backwards. Shared between [ComposerDraft.hasContent] and
/// `ComposerState.hasUnsavedComposition` so the dismiss guard, the
/// autosave, and the draft's own idea of "empty" can never drift apart.
bool composerDraftHasContent({
  required ComposerDraftMode mode,
  required int guidedStepIndex,
  required Map<String, String> guidedAnswers,
  required String freeformText,
}) =>
    guidedAnswers.values.any((answer) => answer.trim().isNotEmpty) ||
    freeformText.trim().isNotEmpty ||
    (mode == ComposerDraftMode.guided && guidedStepIndex > 0);

/// An in-progress "new entry" composition, saved so it survives the app
/// being killed mid-write.
///
/// Mirrors the fields `ComposerState` owns for whichever of `ComposerStage`
/// is currently `GuidedStage` or `FreeformStage` -- the only two stages a
/// draft is ever written from. `ConfirmFeelingStage` and `EchoStage` only
/// exist once the entry is already stored server-side, and
/// `EntryComposerController._enterConfirmStage` clears the draft on the way
/// in, so there is never a draft to describe either of those stages.
class const ComposerDraft({
  required final ComposerDraftMode mode,
  final int guidedStepIndex = 0,
  final Map<String, String> guidedAnswers = const {},
  final String freeformText = '',

  /// The calendar day this draft was being written for (#36) -- null for a
  /// draft written before backdating existed, which was always for today.
  ///
  /// Carried alongside the rest of the composition on purpose: this store
  /// holds exactly one draft regardless of how many days a diary spans, so
  /// without this field a draft started for a past day would be
  /// indistinguishable from one started for today, and restoring it into
  /// whichever composer opened first would silently move it onto the wrong
  /// day. `EntryComposerController._restoreDraft` reads this back and
  /// restores a draft only into the composer session for the same day.
  final CalendarDate? entryDate,
  required final DateTime savedAt,
}) {
  /// Whether this draft is worth restoring -- see [composerDraftHasContent].
  bool get hasContent => composerDraftHasContent(
    mode: mode,
    guidedStepIndex: guidedStepIndex,
    guidedAnswers: guidedAnswers,
    freeformText: freeformText,
  );

  /// This draft as a JSON-ready map.
  JsonObject toJson() => {
    'mode': mode.id,
    'guided_step_index': guidedStepIndex,
    'guided_answers': guidedAnswers,
    'freeform_text': freeformText,
    if (entryDate != null) 'entry_date': entryDate.toString(),
    'saved_at': savedAt.toUtc().toIso8601String(),
  };

  /// Reconstructs a draft from [json], or null if the shape is not one this
  /// build recognises -- a draft written by a future or older build is
  /// discarded rather than guessed at.
  static ComposerDraft? fromJson(JsonObject json) {
    final mode = ComposerDraftMode.fromId(json['mode'] as String?);
    if (mode == null) return null;
    final savedAtRaw = json['saved_at'];
    final savedAt = savedAtRaw is String ? DateTime.tryParse(savedAtRaw) : null;
    if (savedAt == null) return null;
    final rawAnswers = json['guided_answers'];
    return ComposerDraft(
      mode: mode,
      guidedStepIndex: (json['guided_step_index'] as num?)?.toInt() ?? 0,
      guidedAnswers: rawAnswers is Map
          ? {
              for (final entry in rawAnswers.entries)
                '${entry.key}': '${entry.value}',
            }
          : const {},
      freeformText: json['freeform_text'] as String? ?? '',
      entryDate: CalendarDate.tryParse(json['entry_date'] as String?),
      savedAt: savedAt.toUtc(),
    );
  }
}

/// Reads and writes the in-progress "new entry" draft.
///
/// An interface rather than a singleton so tests, and any app that outgrows
/// `SharedPreferences`, can substitute their own implementation through
/// `composerDraftStoreProvider` -- the same shape `SettingsStore` has.
abstract interface class ComposerDraftStore {
  /// Reads the saved draft, or null if there is none, or it could not be
  /// read.
  Future<ComposerDraft?> load();

  /// Persists [draft], replacing whatever was saved before.
  Future<void> save(ComposerDraft draft);

  /// Deletes the saved draft, if any.
  Future<void> clear();
}

/// The default [ComposerDraftStore], backed by `SharedPreferences`.
///
/// Plain unencrypted storage is deliberate, the same way it is for
/// `SharedPreferencesSettingsStore`: an in-progress diary entry never
/// leaves the device through this path, and nothing here is more sensitive
/// than what is already typed into the app.
class SharedPreferencesComposerDraftStore implements ComposerDraftStore {
  /// Creates a store that writes a key prefixed with [prefix].
  const SharedPreferencesComposerDraftStore({
    this.prefix = AppConfig.storagePrefix,
  });

  /// The prefix applied to the key this store touches.
  final String prefix;

  String get _key => '$prefix.composer_draft';

  @override
  Future<ComposerDraft?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is JsonObject ? ComposerDraft.fromJson(decoded) : null;
    } on FormatException {
      // A draft this build cannot parse (corrupted, or written by an
      // incompatible build) is no different from there being none.
      return null;
    }
  }

  @override
  Future<void> save(ComposerDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(draft.toJson()));
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
