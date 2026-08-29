import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diary/diary_providers.dart';
import '../../core/diary/entries_api.dart';
import '../../core/diary/entry.dart';
import '../../core/diary/feeling.dart';
import '../../core/diary/guiding_question.dart';
import '../../core/diary/pattern.dart';
import '../../core/network/api_error.dart';

/// Which step of the "new entry" flow is currently showing.
sealed class const ComposerStage();

/// Answering the guided questions, one at a time.
final class const GuidedStage() extends ComposerStage;

/// Writing freely in one text field.
final class const FreeformStage() extends ComposerStage;

/// The entry at [entry] is stored; the reader is choosing how it felt.
final class const ConfirmFeelingStage(final Entry entry) extends ComposerStage;

/// What the diary already had to say about the topics in the entry just
/// stored.
///
/// A stage rather than a toast: it is an observation worth reading, and it
/// is reachable only *after* the entry is fully saved and its feelings
/// confirmed — an app that echoed a pattern back while someone was still
/// describing it would be shaping the evidence it then counts.
final class const EchoStage(final List<PatternEcho> echoes)
    extends ComposerStage;

/// Everything the entry composer needs to render, gathered across four
/// backend calls and however far the user has got through writing.
///
/// [guidedAnswers], [guidedStepIndex] and [freeformText] live here rather
/// than inside the guided or freeform widgets themselves, because switching
/// between modes swaps those widgets out — state that lived in them used to
/// be destroyed on every switch, discarding half-written answers and
/// resetting the guided flow to its first step. Half a written entry is not
/// something a mode toggle is allowed to throw away.
class const ComposerState({
  final ComposerStage stage = const GuidedStage(),
  final List<GuidingQuestion> guidingQuestions = const [],
  final List<FeelingGroup> feelingGroups = const [],

  /// The engine's thresholds, including the intensity scale. A placeholder
  /// until the first read lands, so the confirm step can lay itself out
  /// without branching on null — nothing from the placeholder is ever shown
  /// as a fact.
  final EngineConstants constants = EngineConstants.placeholder,
  final Map<String, String> guidedAnswers = const {},
  final int guidedStepIndex = 0,
  final String freeformText = '',
  final bool isSaving = false,

  /// True while [ConfirmFeelingStage] is waiting on a background poll for
  /// the analyser's verdict on the entry it holds.
  ///
  /// Distinct from the entry's own `analysisPending` (`Entry.analysisPending`):
  /// that field is a snapshot from whichever response last carried it, and
  /// would otherwise leave the "Reading your entry…" banner stuck forever
  /// once the poll gives up — this flag is explicitly cleared when the poll
  /// settles, whether that is because a verdict arrived or because it timed
  /// out, so the manual picker is never gated on it.
  final bool isPollingSuggestions = false,
  final String? errorMessage,
}) {
  /// A sentinel distinguishing "leave [errorMessage] alone" from "clear
  /// it" in [copyWith] — a plain `errorMessage ?? this.errorMessage` can
  /// never null the field back out once set.
  static const Object _unset = Object();

  /// A copy of this state with the given fields replaced.
  ///
  /// Pass `errorMessage: null` to explicitly clear it; omit it to leave the
  /// current value alone.
  ComposerState copyWith({
    ComposerStage? stage,
    List<GuidingQuestion>? guidingQuestions,
    List<FeelingGroup>? feelingGroups,
    EngineConstants? constants,
    Map<String, String>? guidedAnswers,
    int? guidedStepIndex,
    String? freeformText,
    bool? isSaving,
    bool? isPollingSuggestions,
    Object? errorMessage = _unset,
  }) => ComposerState(
    stage: stage ?? this.stage,
    guidingQuestions: guidingQuestions ?? this.guidingQuestions,
    feelingGroups: feelingGroups ?? this.feelingGroups,
    constants: constants ?? this.constants,
    guidedAnswers: guidedAnswers ?? this.guidedAnswers,
    guidedStepIndex: guidedStepIndex ?? this.guidedStepIndex,
    freeformText: freeformText ?? this.freeformText,
    isSaving: isSaving ?? this.isSaving,
    isPollingSuggestions: isPollingSuggestions ?? this.isPollingSuggestions,
    errorMessage: identical(errorMessage, _unset)
        ? this.errorMessage
        : errorMessage as String?,
  );
}

/// Drives the four-stage "new entry" flow.
///
/// The three background loads in [build] run one after another rather than
/// concurrently: partly so a test's scripted HTTP replies land in a
/// predictable order, and partly because it means the constants load's own
/// feelings-catalog lookup almost always reuses the cache the feelings load
/// just primed, instead of racing it for a second request.
class EntryComposerController extends Notifier<ComposerState> {
  /// How long between one poll for the analyser's verdict and the next.
  static const Duration _suggestionPollInterval = Duration(seconds: 1);

  /// How many polls [_pollForSuggestions] makes before giving up. At
  /// [_suggestionPollInterval] that is ~12 seconds — inside the ~10-15s
  /// window a suggestion is expected in, and short enough that giving up
  /// never reads as a stuck app.
  static const int _maxSuggestionPollAttempts = 12;

  late Future<void> _ready;
  Future<void>? _suggestionPoll;

  /// Resolves once the three background loads in [build] have all settled
  /// (each swallows its own [ApiError], so this never throws).
  ///
  /// Exposed purely as a test seam: production code never awaits this --
  /// the whole point of firing the loads from [build] rather than blocking
  /// on them is that the composer is usable immediately. A test awaits it
  /// instead of pumping the event queue and hoping enough ticks have
  /// passed for three chained network calls to settle.
  Future<void> get ready => _ready;

  /// Resolves once a background poll for the analyser's suggestion --
  /// started after entering [ConfirmFeelingStage] for an entry whose
  /// analysis was still pending -- has settled, whether that is because a
  /// verdict arrived or because it timed out.
  ///
  /// Exposed as a test seam the same way [ready] is; production code never
  /// awaits this. Resolves immediately when no poll is running.
  Future<void> get suggestionPollSettled => _suggestionPoll ?? Future.value();

  /// Injected into the suggestion poll loop below, so a test never waits on
  /// a real clock -- mirrors `TranscriptionsApi.transcribe`'s `delay` seam.
  /// Mutable purely as a test seam; production code never touches this
  /// after construction.
  Future<void> Function(Duration) pollDelay = Future.delayed;

  @override
  ComposerState build() {
    _ready = _loadAll();
    return const ComposerState();
  }

  Future<void> _loadAll() async {
    await _loadFeelingGroups();
    await _loadGuidingQuestions();
    await _loadConstants();
  }

  Future<void> _loadGuidingQuestions() async {
    try {
      // Reads straight through the API layer's own cache rather than
      // through `guidingQuestionLibraryProvider` -- the same data either
      // way, without tying this notifier's lifecycle to a second,
      // independently-disposed provider.
      final library = await ref.read(guidingQuestionsApiProvider).library();
      if (!ref.mounted) return;
      state = state.copyWith(guidingQuestions: library);
    } on ApiError catch (error) {
      if (!ref.mounted) return;
      // Can't load the guided-question library (e.g. backend unreachable)
      // -- freeform writing still works without it.
      state = state.copyWith(
        errorMessage: error.message,
        stage: const FreeformStage(),
      );
    }
  }

  Future<void> _loadFeelingGroups() async {
    try {
      final groups = await ref.read(feelingsApiProvider).groups();
      if (!ref.mounted) return;
      state = state.copyWith(feelingGroups: groups);
    } on ApiError {
      // The feeling picker's chip row is populated by the time an entry
      // has been saved; a failure here is silent because saving the entry
      // is what matters, and the same failure will surface there.
    }
  }

  Future<void> _loadConstants() async {
    try {
      final result = await ref.read(insightsApiProvider).insights();
      if (!ref.mounted) return;
      state = state.copyWith(constants: result.constants);
    } on ApiError {
      // The placeholder stands in until the next load succeeds.
    }
  }

  /// Switch to freeform, seeding the draft with whatever the guided flow
  /// has collected so far.
  ///
  /// Only when the freeform draft is still empty: someone who has answered
  /// two prompts and then decides to write freely wants to keep writing,
  /// not to retype what they already said, but someone already mid-way
  /// through their own freeform draft should not have it overwritten by a
  /// stale guided answer. The guided answers themselves are left intact
  /// either way, so switching back is lossless.
  void switchToFreeform() {
    final carried = [
      for (final question in state.guidingQuestions)
        if ((state.guidedAnswers[question.key] ?? '').trim().isNotEmpty)
          state.guidedAnswers[question.key]!.trim(),
    ].join('\n\n').trim();
    final seeded = state.freeformText.trim().isNotEmpty
        ? state.freeformText
        : carried;
    state = state.copyWith(stage: const FreeformStage(), freeformText: seeded);
  }

  /// Switches back to the guided flow, at whatever step it was left on.
  void switchToGuided() => state = state.copyWith(stage: const GuidedStage());

  /// Records the answer to [questionKey].
  void updateGuidedAnswer(String questionKey, String text) {
    state = state.copyWith(
      guidedAnswers: {...state.guidedAnswers, questionKey: text},
    );
  }

  /// Moves the guided flow to [index].
  void updateGuidedStep(int index) =>
      state = state.copyWith(guidedStepIndex: index);

  /// Records the freeform draft.
  void updateFreeformText(String text) =>
      state = state.copyWith(freeformText: text);

  /// Saves a guided entry from [answers]. A no-op for an empty list.
  ///
  /// The answers go up on their own with `raw_text` empty -- the backend
  /// composes the entry's prose from the prompts and answers, the same way
  /// it does for the web client, so this never joins them client-side.
  Future<void> saveGuided(List<GuidingQuestionAnswer> answers) async {
    if (answers.isEmpty) return;
    state = state.copyWith(isSaving: true, errorMessage: null);
    try {
      final entry = await ref.read(entriesApiProvider).createGuided(answers);
      if (!ref.mounted) return;
      _enterConfirmStage(entry);
    } on ApiError catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(isSaving: false, errorMessage: error.message);
    }
  }

  /// Saves a freeform entry from [text]. A no-op for blank text.
  Future<void> saveFreeform(String text) async {
    if (text.trim().isEmpty) return;
    state = state.copyWith(isSaving: true, errorMessage: null);
    try {
      final entry = await ref
          .read(entriesApiProvider)
          .createFreeform(text.trim());
      if (!ref.mounted) return;
      _enterConfirmStage(entry);
    } on ApiError catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(isSaving: false, errorMessage: error.message);
    }
  }

  /// Moves to [ConfirmFeelingStage] for the just-saved [entry], and -- when
  /// the backend says its analysis is still running -- starts a background
  /// poll for the analyser's verdict.
  ///
  /// The suggest/confirm flow only has something to offer if the "How did
  /// that feel?" step can see the suggestion, and the worker that produces
  /// it (a separate local-inference process) has not necessarily finished
  /// by the time the entry was saved -- often it has barely started. Rather
  /// than the step reading a stale, empty `entry.suggestedFeelings` forever,
  /// this polls `GET /entries/{id}` for a fresh copy until one arrives.
  void _enterConfirmStage(Entry entry) {
    state = state.copyWith(
      isSaving: false,
      stage: ConfirmFeelingStage(entry),
      isPollingSuggestions: entry.analysisPending,
    );
    _suggestionPoll = entry.analysisPending
        ? _pollForSuggestions(entry.id)
        : null;
  }

  /// Whether [ConfirmFeelingStage] is still showing the entry [entryId] --
  /// i.e. whether a poll for it is still worth continuing.
  ///
  /// False once the user has confirmed feelings and moved on (the stage
  /// changed) or, in principle, once a second save somehow landed a
  /// different entry in the same stage -- either way, a poll racing against
  /// a screen the user has left has nothing useful left to update.
  bool _stillWaitingOn(String entryId) {
    final stage = state.stage;
    return stage is ConfirmFeelingStage && stage.entry.id == entryId;
  }

  /// Polls `GET /entries/{entryId}` for the analyser's verdict, at most
  /// [_maxSuggestionPollAttempts] times [_suggestionPollInterval] apart.
  ///
  /// Stops as soon as the entry's analysis is no longer pending -- whether
  /// or not it ended up with a suggestion, since a "no feeling worth
  /// proposing" verdict is still a verdict -- and stops early, without
  /// touching [ComposerState], if the user has already left
  /// [ConfirmFeelingStage] for this entry. Running out of attempts or
  /// hitting a network error both degrade the same way as a real timeout:
  /// [ComposerState.isPollingSuggestions] is cleared and the manual picker,
  /// which was never blocked on this succeeding, is what is left on screen.
  /// Nothing here ever touches [ComposerState.errorMessage] -- a failed or
  /// exhausted poll is silent, not a user-facing error.
  Future<void> _pollForSuggestions(String entryId) async {
    for (var attempt = 0; attempt < _maxSuggestionPollAttempts; attempt++) {
      await pollDelay(_suggestionPollInterval);
      if (!ref.mounted || !_stillWaitingOn(entryId)) return;

      Entry updated;
      try {
        updated = await ref.read(entriesApiProvider).getById(entryId);
      } on ApiError {
        continue; // Transient failure -- try again until attempts run out.
      }
      if (!ref.mounted || !_stillWaitingOn(entryId)) return;

      if (!updated.analysisPending) {
        state = state.copyWith(
          stage: ConfirmFeelingStage(updated),
          isPollingSuggestions: false,
        );
        return;
      }
    }

    if (ref.mounted && _stillWaitingOn(entryId)) {
      state = state.copyWith(isPollingSuggestions: false);
    }
  }

  /// Confirms or overrides the analyser's proposed feelings for the entry
  /// at [entryId]/[version].
  ///
  /// Returns `true` when the flow is finished and the caller should return
  /// to Today: either there was nothing to echo back, or the echo fetch
  /// itself failed (a failed echo is not worth interrupting a finished
  /// entry for). Returns `false` when [ComposerState.stage] moved to
  /// [EchoStage] instead, or when the confirmation itself failed and
  /// [ComposerState.errorMessage] now explains why.
  Future<bool> confirmFeelings({
    required String entryId,
    required int version,
    required List<Feeling> feelings,
    required Map<String, int> intensities,
  }) async {
    state = state.copyWith(isSaving: true, errorMessage: null);
    try {
      final mutation = await ref
          .read(entriesApiProvider)
          .confirmFeelings(
            id: entryId,
            version: version,
            feelings: feelings,
            intensities: intensities,
          );
      if (!ref.mounted) return false;
      switch (mutation) {
        case EntryUpdated(:final entry):
          state = state.copyWith(isSaving: false);
          // The entry is stored for good at this point, whether or not an
          // echo panel follows -- see diaryWriteSignalProvider.
          ref.read(diaryWriteSignalProvider.notifier).bump();
          return await _loadEcho(entry.id);
        case EntryRemoved():
          state = state.copyWith(
            isSaving: false,
            errorMessage: 'This entry was deleted elsewhere.',
          );
          return false;
        case EntryOutOfDate(:final message):
          state = state.copyWith(isSaving: false, errorMessage: message);
          return false;
      }
    } on ApiError catch (error) {
      if (!ref.mounted) return false;
      state = state.copyWith(isSaving: false, errorMessage: error.message);
      return false;
    }
  }

  Future<bool> _loadEcho(String entryId) async {
    try {
      final echoes = await ref.read(entriesApiProvider).echo(entryId);
      if (!ref.mounted) return false;
      if (echoes.isEmpty) return true;
      state = state.copyWith(stage: EchoStage(echoes));
      return false;
    } on ApiError {
      // Asked for only now, with the entry stored and the feeling settled.
      // A failed echo is not worth interrupting a finished entry for.
      return true;
    }
  }

  /// Clears [ComposerState.errorMessage] once it has been shown.
  void dismissError() => state = state.copyWith(errorMessage: null);
}

/// The state behind the entry composer.
final entryComposerControllerProvider =
    NotifierProvider<EntryComposerController, ComposerState>(
      EntryComposerController.new,
    );
