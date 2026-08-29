import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diary/calendar_date.dart';
import '../../core/diary/diary_providers.dart';
import '../../core/diary/entries_api.dart';
import '../../core/diary/entry.dart';
import '../../core/diary/feeling.dart';
import '../../core/diary/guiding_question.dart';
import '../../core/diary/pattern.dart';
import '../../core/network/api_error.dart';
import '../../core/notifications/reminder_providers.dart';
import 'composer_draft.dart';
import 'first_pattern_copy.dart';
import 'first_pattern_notified_store.dart';

/// The store the composer reads and writes its in-progress draft through.
///
/// Overridable so tests can substitute an in-memory fake, the same way
/// `settingsStoreProvider` works.
final composerDraftStoreProvider = Provider<ComposerDraftStore>(
  (ref) => const SharedPreferencesComposerDraftStore(),
);

/// The store `_checkFirstPattern` reads and writes the first-pattern
/// celebration's exactly-once flag through (L-3/#38).
///
/// Overridable so tests can substitute an in-memory fake, the same way
/// [composerDraftStoreProvider] does.
final firstPatternStoreProvider = Provider<FirstPatternNotifiedStore>(
  (ref) => const SharedPreferencesFirstPatternNotifiedStore(),
);

/// The clock [EntryComposerController] treats as "now" when deciding
/// whether its `targetDate` counts as backdated (#36) -- which drives both
/// the header chip and whether an explicit `entry_date` is sent on save.
///
/// Null means the real clock. Overridden in tests so that decision is
/// deterministic rather than following the real device clock, the same
/// reason `dayEntriesNowProvider` exists in `day_entries_screen.dart`.
final composerNowProvider = Provider<DateTime?>((ref) => null);

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
///
/// [celebratedPattern] rides along on the same stage rather than getting
/// one of its own (L-3/#38): the first-pattern celebration is shown on
/// exactly this "Saved" screen, alongside whatever [echoes] this entry's
/// own topics produced, not before or after it -- so this stage is reached
/// whenever there is [echoes] content, a celebration, or both, and never
/// reached (see `EntryComposerController._loadEcho`) when there is
/// neither.
final class const EchoStage(
  final List<PatternEcho> echoes, {
  final Pattern? celebratedPattern,
}) extends ComposerStage;

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
  /// The calendar day this entry will be filed under (#36) -- the day the
  /// composer was opened "for". Set once, from `EntryComposerController
  /// .targetDate`, and never changes for the life of a composer session.
  required final CalendarDate targetDate,

  /// Whether [targetDate] is a day other than today, as read from
  /// `composerNowProvider` when this state was built.
  ///
  /// Drives the quiet "Writing about…" header chip and whether [targetDate]
  /// is sent to the backend as an explicit `entry_date` on save -- the
  /// ordinary "write for today" path always omits it, so the server's own
  /// idea of today decides, exactly as before this feature existed.
  required final bool isBackdated,
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

  /// When a draft was restored on this composer session, the moment it was
  /// last autosaved -- shown in the dismissible "Continuing your draft
  /// from…" notice. Null once there is nothing to restore, or once the
  /// notice has been dismissed.
  final DateTime? restoredDraftAt,
}) {
  /// A sentinel distinguishing "leave [errorMessage] alone" from "clear
  /// it" in [copyWith] — a plain `errorMessage ?? this.errorMessage` can
  /// never null the field back out once set.
  static const Object _unset = Object();

  /// Whether dismissing the composer right now would lose something —
  /// drives both the dismiss guard and whether the autosave has anything
  /// worth persisting.
  ///
  /// Deliberately false outside [GuidedStage] and [FreeformStage]: once the
  /// flow reaches [ConfirmFeelingStage] the entry is already stored, so
  /// leaving it with no confirmed feelings is an intentional allowed state,
  /// not something to warn about.
  bool get hasUnsavedComposition {
    final mode = switch (stage) {
      GuidedStage() => ComposerDraftMode.guided,
      FreeformStage() => ComposerDraftMode.freeform,
      ConfirmFeelingStage() || EchoStage() => null,
    };
    if (mode == null) return false;
    return composerDraftHasContent(
      mode: mode,
      guidedStepIndex: guidedStepIndex,
      guidedAnswers: guidedAnswers,
      freeformText: freeformText,
    );
  }

  /// A copy of this state with the given fields replaced.
  ///
  /// Pass `errorMessage: null` to explicitly clear it; omit it to leave the
  /// current value alone. [restoredDraftAt] works the same way, through its
  /// own sentinel.
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
    Object? restoredDraftAt = _unset,
  }) => ComposerState(
    targetDate: targetDate,
    isBackdated: isBackdated,
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
    restoredDraftAt: identical(restoredDraftAt, _unset)
        ? this.restoredDraftAt
        : restoredDraftAt as DateTime?,
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
  /// Creates the controller for a composer session writing for [targetDate]
  /// (#36) -- the family key `entryComposerControllerProvider` is read
  /// through.
  EntryComposerController(this.targetDate);

  /// The calendar day this composer session writes for. See
  /// [ComposerState.targetDate].
  final CalendarDate targetDate;

  /// The day [build] read from [composerNowProvider] -- what "today" means
  /// for [ComposerState.isBackdated] and for treating a dateless (pre-#36)
  /// restored draft as having been for today. Set once, in [build].
  late final CalendarDate _today;

  /// How long between one poll for the analyser's verdict and the next.
  static const Duration _suggestionPollInterval = Duration(seconds: 1);

  /// How many polls [_pollForSuggestions] makes before giving up. At
  /// [_suggestionPollInterval] that is ~12 seconds — inside the ~10-15s
  /// window a suggestion is expected in, and short enough that giving up
  /// never reads as a stuck app.
  static const int _maxSuggestionPollAttempts = 12;

  late Future<void> _ready;
  Future<void>? _suggestionPoll;

  /// The pending debounced draft save/clear, if any -- a real `Timer`
  /// rather than a bare injected delay (contrast [pollDelay]): firing it
  /// never changes [ComposerState], so unlike the suggestion poll's timer,
  /// nothing about it would ever prompt a rebuild that lets `pumpAndSettle`
  /// notice there is still something to wait out. Explicit cancellation on
  /// every reschedule, on [discardDraft], on [_enterConfirmStage] and on
  /// disposal (see [build]) is what keeps a stale write from landing later
  /// and what keeps a test's widget tree free of a timer still ticking
  /// after teardown.
  Timer? _draftSaveTimer;
  Completer<void>? _draftSaveCompleter;

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

  /// Resolves once the most recently scheduled debounced draft save (or
  /// clear) has settled. Exposed as a test seam the same way
  /// [suggestionPollSettled] is; production code never awaits this.
  /// Resolves immediately when no save is pending.
  Future<void> get draftSaveSettled =>
      _draftSaveCompleter?.future ?? Future.value();

  /// Injected into the suggestion poll loop below, so a test never waits on
  /// a real clock -- mirrors `TranscriptionsApi.transcribe`'s `delay` seam.
  /// Mutable purely as a test seam; production code never touches this
  /// after construction.
  Future<void> Function(Duration) pollDelay = Future.delayed;

  /// How long [_scheduleDraftSave] waits after the last edit (a keystroke
  /// or a step transition) before writing the draft to disk. Long enough
  /// that a fast typist does not trigger a write per keystroke, short
  /// enough that killing the app a moment later still loses at most this
  /// much. Mutable purely as a test seam, the same way [pollDelay] is --
  /// shrinking it (typically to [Duration.zero]) lets a test drive the
  /// debounce with a plain `tester.pump` instead of waiting out the real
  /// interval.
  Duration draftSaveDebounce = const Duration(milliseconds: 500);

  /// Whether the app is currently in the foreground -- read by
  /// [_checkFirstPattern] at the moment it decides between the inline
  /// celebration card and a notification (L-3/#38), never captured
  /// earlier: the confirm-and-fetch-insights round trip this follows is
  /// long enough that the user can background the app in between.
  ///
  /// Mutable purely as a test seam, the same way [pollDelay] is: a plain
  /// `test()` over a bare `ProviderContainer` (as opposed to `testWidgets`)
  /// never initialises a `WidgetsBinding`, so reading
  /// `WidgetsBinding.instance.lifecycleState` directly in such a test would
  /// throw before the fake HTTP layer backing [confirmFeelings] ever got a
  /// chance to run.
  ///
  /// The production default treats an unreported lifecycle state (`null`
  /// -- the state before the platform's very first lifecycle callback) as
  /// foregrounded rather than backgrounded: the only way to reach this
  /// callback at all is a user tapping "Confirm" on a screen that must
  /// already be on-screen, so the common case is foreground, and only a
  /// definite `paused`/`inactive`/`hidden`/`detached` report overrides
  /// that assumption.
  bool Function() isAppForegrounded = () {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  };

  @override
  ComposerState build() {
    // Whatever is pending when this notifier goes away -- the composer was
    // closed, or a test's container was disposed -- must not fire
    // afterwards: [ref.mounted] alone does not stop a `Timer` from ticking.
    ref.onDispose(() => _draftSaveTimer?.cancel());
    _today = CalendarDate.today(now: ref.read(composerNowProvider));
    _ready = _loadAll();
    return ComposerState(
      targetDate: targetDate,
      isBackdated: targetDate != _today,
    );
  }

  Future<void> _loadAll() async {
    await _restoreDraft();
    await _loadFeelingGroups();
    await _loadGuidingQuestions();
    await _loadConstants();
  }

  /// Offers back whatever was saved by [_scheduleDraftSave] on a previous
  /// run of the app, if it still has anything in it.
  ///
  /// Read once, on [build] -- a draft written to disk after the composer
  /// has already opened is this same session's own autosave, not a second
  /// device's, so there is nothing to reconcile mid-session.
  Future<void> _restoreDraft() async {
    final draft = await ref.read(composerDraftStoreProvider).load();
    if (!ref.mounted || draft == null || !draft.hasContent) return;
    // A draft carries the day it was written for (#36; null means a draft
    // written before backdating existed, which was always for today). One
    // written for a different day belongs to whichever composer session
    // opens that day -- applying it here would silently move a backdated
    // composition onto today, or vice versa. Left on disk, untouched, for
    // its actual day's session to restore.
    if ((draft.entryDate ?? _today) != targetDate) return;
    state = state.copyWith(
      stage: draft.mode == ComposerDraftMode.guided
          ? const GuidedStage()
          : const FreeformStage(),
      guidedStepIndex: draft.guidedStepIndex,
      guidedAnswers: draft.guidedAnswers,
      freeformText: draft.freeformText,
      restoredDraftAt: draft.savedAt,
    );
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
    _scheduleDraftSave();
  }

  /// Switches back to the guided flow, at whatever step it was left on.
  void switchToGuided() {
    state = state.copyWith(stage: const GuidedStage());
    _scheduleDraftSave();
  }

  /// Records the answer to [questionKey].
  void updateGuidedAnswer(String questionKey, String text) {
    state = state.copyWith(
      guidedAnswers: {...state.guidedAnswers, questionKey: text},
    );
    _scheduleDraftSave();
  }

  /// Moves the guided flow to [index].
  void updateGuidedStep(int index) {
    state = state.copyWith(guidedStepIndex: index);
    _scheduleDraftSave();
  }

  /// Records the freeform draft.
  void updateFreeformText(String text) {
    state = state.copyWith(freeformText: text);
    _scheduleDraftSave();
  }

  /// (Re)starts the debounce timer that writes the current composition to
  /// [composerDraftStoreProvider] -- called on every text change and every
  /// step transition, per the mutating methods above.
  ///
  /// Cancelling and replacing [_draftSaveTimer] on every call is the
  /// debounce itself: only the last edit inside any [draftSaveDebounce]
  /// window ever reaches disk, exactly the way a search box's "wait for
  /// typing to pause" debounce works.
  void _scheduleDraftSave() {
    _draftSaveTimer?.cancel();
    final completer = Completer<void>();
    _draftSaveCompleter = completer;
    _draftSaveTimer = Timer(draftSaveDebounce, () {
      unawaited(_writeDraft().whenComplete(completer.complete));
    });
  }

  Future<void> _writeDraft() async {
    if (!ref.mounted) return;
    final store = ref.read(composerDraftStoreProvider);
    if (!state.hasUnsavedComposition) {
      await store.clear();
      return;
    }
    await store.save(
      ComposerDraft(
        mode: state.stage is FreeformStage
            ? ComposerDraftMode.freeform
            : ComposerDraftMode.guided,
        guidedStepIndex: state.guidedStepIndex,
        guidedAnswers: state.guidedAnswers,
        freeformText: state.freeformText,
        entryDate: targetDate,
        savedAt: DateTime.now().toUtc(),
      ),
    );
  }

  /// Hides the "Continuing your draft…" notice without discarding
  /// anything -- the restored answers and step position are left exactly
  /// as they are.
  void dismissDraftNotice() => state = state.copyWith(restoredDraftAt: null);

  /// Discards the current composition and its persisted draft, returning
  /// every guided and freeform field to its default.
  ///
  /// Shared by "Discard" on the dismiss-guard sheet and "Start fresh" on
  /// the restored-draft notice -- both mean the same thing: forget what is
  /// on screen and start blank. Cancels any debounced save already in
  /// flight first, so an edit from moments before this was tapped cannot
  /// land afterwards and resurrect what was just discarded.
  Future<void> discardDraft() async {
    _draftSaveTimer?.cancel();
    state = state.copyWith(
      guidedAnswers: const {},
      guidedStepIndex: 0,
      freeformText: '',
      restoredDraftAt: null,
    );
    await ref.read(composerDraftStoreProvider).clear();
  }

  /// Saves a guided entry from [answers]. A no-op for an empty list.
  ///
  /// The answers go up on their own with `raw_text` empty -- the backend
  /// composes the entry's prose from the prompts and answers, the same way
  /// it does for the web client, so this never joins them client-side.
  /// [targetDate] rides along as an explicit `entry_date` only while
  /// [ComposerState.isBackdated] -- see [EntriesApi.createFreeform] for why
  /// the ordinary "write for today" save omits it.
  Future<void> saveGuided(List<GuidingQuestionAnswer> answers) async {
    if (answers.isEmpty) return;
    state = state.copyWith(isSaving: true, errorMessage: null);
    try {
      final entry = await ref
          .read(entriesApiProvider)
          .createGuided(
            answers,
            entryDate: state.isBackdated ? targetDate : null,
          );
      if (!ref.mounted) return;
      _enterConfirmStage(entry);
    } on ApiError catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(isSaving: false, errorMessage: error.message);
    }
  }

  /// Saves a freeform entry from [text]. A no-op for blank text. See
  /// [saveGuided] for [targetDate].
  Future<void> saveFreeform(String text) async {
    if (text.trim().isEmpty) return;
    state = state.copyWith(isSaving: true, errorMessage: null);
    try {
      final entry = await ref
          .read(entriesApiProvider)
          .createFreeform(
            text.trim(),
            entryDate: state.isBackdated ? targetDate : null,
          );
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
  ///
  /// The entry is safely stored server-side from this point on, so the
  /// draft that was standing in for it on this device is no longer needed
  /// -- cleared immediately (not debounced) and any debounced save still in
  /// flight from an edit made moments before saving is cancelled the same
  /// way [discardDraft] cancels one, so it cannot write a stale draft back
  /// after this clears it.
  void _enterConfirmStage(Entry entry) {
    _draftSaveTimer?.cancel();
    state = state.copyWith(
      isSaving: false,
      stage: ConfirmFeelingStage(entry),
      isPollingSuggestions: entry.analysisPending,
      restoredDraftAt: null,
    );
    _suggestionPoll = entry.analysisPending
        ? _pollForSuggestions(entry.id)
        : null;
    unawaited(ref.read(composerDraftStoreProvider).clear());
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
  /// to Today: there was nothing to echo back and nothing to celebrate (see
  /// [EchoStage.celebratedPattern], L-3/#38), or the echo fetch itself
  /// failed with no celebration either (a failed echo is not worth
  /// interrupting a finished entry for). Returns `false` when
  /// [ComposerState.stage] moved to [EchoStage] instead, or when the
  /// confirmation itself failed and [ComposerState.errorMessage] now
  /// explains why.
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
          final celebrate = await _checkFirstPattern();
          if (!ref.mounted) return false;
          return await _loadEcho(entry.id, celebrate: celebrate);
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

  /// Loads this entry's own pattern echoes and moves to [EchoStage] if
  /// there is [celebrate], [echoes][EchoStage.echoes], or both to show.
  ///
  /// [celebrate] -- the pattern [_checkFirstPattern] says is the diary's
  /// first, or `null` when there is none -- can keep this on [EchoStage]
  /// even when this entry produced no echo of its own and even when the
  /// echo fetch itself fails: the celebration is not this entry's echo and
  /// must not be silently dropped just because the unrelated echo call had
  /// nothing, or failed.
  Future<bool> _loadEcho(String entryId, {required Pattern? celebrate}) async {
    try {
      final echoes = await ref.read(entriesApiProvider).echo(entryId);
      if (!ref.mounted) return false;
      if (echoes.isEmpty && celebrate == null) return true;
      state = state.copyWith(
        stage: EchoStage(echoes, celebratedPattern: celebrate),
      );
      return false;
    } on ApiError {
      // Asked for only now, with the entry stored and the feeling settled.
      // A failed echo is not worth interrupting a finished entry for --
      // unless there is still a celebration to show, which owes nothing to
      // whether this unrelated call succeeded.
      if (celebrate == null) return true;
      if (!ref.mounted) return false;
      state = state.copyWith(
        stage: EchoStage(const [], celebratedPattern: celebrate),
      );
      return false;
    }
  }

  /// Checks whether this confirm is the diary's first pattern ever
  /// surfacing (L-3/#38), and fires the celebration -- inline or as a
  /// notification -- exactly once if so.
  ///
  /// Runs on every successful confirm, but [firstPatternStoreProvider]'s
  /// flag short-circuits every call after the real one: once notified,
  /// this never fetches insights again for the rest of the diary's life.
  ///
  /// Deliberately a fresh `GET /insights` call, not
  /// [ComposerState.constants] (a snapshot from *before* this entry was
  /// saved, taken once in [_loadConstants]) and not this same confirm's own
  /// echoes (which only ever cover topics [entriesApiProvider]'s
  /// `GET /entries/{id}/echo` finds inside *this* entry's own text). A
  /// context pattern -- e.g. `weekday:sunday` (#21) -- can cross its
  /// threshold from this save without the entry mentioning any topic at
  /// all, so only a fresh, whole-diary read catches every way this save
  /// could be the first one to surface a pattern.
  ///
  /// Returns the pattern to celebrate inline when the app is in the
  /// foreground (per [isAppForegrounded]); otherwise fires the equivalent
  /// local notification through [reminderServiceProvider] and returns
  /// `null`, since there is then nothing left for [_loadEcho] to show on
  /// screen. Also returns `null`, leaving the flag untouched, when there is
  /// nothing to celebrate yet or the insights fetch itself fails -- a
  /// transient network error here must not cost the diary its one
  /// celebration; the next confirm gets another chance.
  Future<Pattern?> _checkFirstPattern() async {
    final store = ref.read(firstPatternStoreProvider);
    if (await store.hasNotified()) return null;
    if (!ref.mounted) return null;
    final InsightsResult insights;
    try {
      insights = await ref.read(insightsApiProvider).insights();
    } on ApiError {
      return null;
    }
    if (!ref.mounted || insights.patterns.isEmpty) return null;
    await store.markNotified();
    if (!ref.mounted) return null;
    final pattern = insights.patterns.first;
    if (isAppForegrounded()) return pattern;
    await ref
        .read(reminderServiceProvider)
        .showFirstPatternNotification(
          title: firstPatternNotificationTitle,
          body: firstPatternNotificationBody(pattern),
        );
    return null;
  }

  /// Clears [ComposerState.errorMessage] once it has been shown.
  void dismissError() => state = state.copyWith(errorMessage: null);
}

/// The state behind the entry composer, keyed by the day it writes for
/// (#36) -- the same `.family` shape `dayEntriesControllerProvider` uses,
/// for the same reason: the day is a parameter of the session, not a
/// mutable field of a single global one.
final entryComposerControllerProvider =
    NotifierProvider.family<
      EntryComposerController,
      ComposerState,
      CalendarDate
    >(
      EntryComposerController.new,
    );
