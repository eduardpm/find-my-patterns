import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diary/calendar_date.dart';
import '../../core/diary/diary_providers.dart';
import '../../core/diary/entries_api.dart';
import '../../core/diary/entry.dart';
import '../../core/diary/feeling.dart';
import '../../core/network/api_error.dart';

/// The feelings the analyser now proposes for an entry, after its text was
/// edited.
class const FeelingProposal(final String entryId, final List<Feeling> feelings);

/// How often [DayEntriesController] polls for re-analysis after a save, and
/// how long it keeps trying before giving up.
///
/// A record rather than two loose constants so both travel together through
/// one provider override — see [analysisPollConfigProvider].
typedef AnalysisPollConfig = ({Duration interval, Duration timeout});

/// The poll cadence used in production: once a second, for up to a minute.
const AnalysisPollConfig defaultAnalysisPollConfig = (
  interval: Duration(seconds: 1),
  timeout: Duration(seconds: 60),
);

/// The interval and timeout [DayEntriesController] polls `getById` with
/// after a save.
///
/// Overridden in tests with a near-zero interval and a small timeout, so a
/// test proving the wait is bounded does not have to script sixty replies
/// or actually wait sixty seconds.
final analysisPollConfigProvider = Provider<AnalysisPollConfig>(
  (ref) => defaultAnalysisPollConfig,
);

/// The delay [DayEntriesController] awaits between polls.
///
/// A plain `Future<void> Function(Duration)` — `Future<void>.delayed` in
/// production — so a test can override it with something that returns
/// immediately, keeping the wait entirely off the real clock.
final analysisPollDelayProvider = Provider<Future<void> Function(Duration)>(
  (ref) => Future<void>.delayed,
);

/// Everything the day-entries screen renders.
///
/// [isAnalysing] and [proposal] track the re-analysis triggered by a saved
/// edit: see [DayEntriesController.saveEdit].
class const DayEntriesState({
  required final CalendarDate date,
  final List<Entry> entries = const [],
  final bool hasLoaded = false,
  final String? editingId,
  final String draft = '',
  final bool isSaving = false,
  final bool isAnalysing = false,
  final FeelingProposal? proposal,
  final String? errorMessage,
}) {
  /// Distinguishes "leave this field alone" from "clear it" in [copyWith].
  static const Object _unset = Object();

  /// A copy of this state with the given fields replaced.
  ///
  /// Pass `editingId`/`proposal`/`errorMessage: null` to explicitly clear
  /// one of them; omit it to leave the current value alone.
  DayEntriesState copyWith({
    List<Entry>? entries,
    bool? hasLoaded,
    Object? editingId = _unset,
    String? draft,
    bool? isSaving,
    bool? isAnalysing,
    Object? proposal = _unset,
    Object? errorMessage = _unset,
  }) => DayEntriesState(
    date: date,
    entries: entries ?? this.entries,
    hasLoaded: hasLoaded ?? this.hasLoaded,
    editingId: identical(editingId, _unset)
        ? this.editingId
        : editingId as String?,
    draft: draft ?? this.draft,
    isSaving: isSaving ?? this.isSaving,
    isAnalysing: isAnalysing ?? this.isAnalysing,
    proposal: identical(proposal, _unset)
        ? this.proposal
        : proposal as FeelingProposal?,
    errorMessage: identical(errorMessage, _unset)
        ? this.errorMessage
        : errorMessage as String?,
  );
}

/// Everything written on one day: loads it, and edits an entry's text in
/// place.
///
/// Editing here is text-only by design. A day in the past is read to
/// remember it, and the useful edit is fixing what was said — not
/// re-running the guided prompts, which describe the moment of writing
/// rather than the day itself. Saving sends only the text: the feelings are
/// deliberately left out of the request, because changing them here would
/// silently overwrite a choice made elsewhere. What the re-analysis
/// produces after a save is offered through [DayEntriesState.proposal],
/// never applied on its own — see [acceptProposal].
class DayEntriesController extends Notifier<DayEntriesState> {
  /// Creates the controller for [date]'s entries.
  DayEntriesController(this.date);

  /// The day this controller loads and edits entries for.
  final CalendarDate date;

  @override
  DayEntriesState build() {
    Future.microtask(refresh);
    return DayEntriesState(date: date);
  }

  static String _messageFor(ApiError error) => switch (error) {
    BackendNotConfigured() => 'Set your server address in Settings.',
    NetworkFailure() => 'Could not reach the server.',
    Unauthorized() => 'Please sign in again.',
    HttpFailure(:final statusCode) => 'Server error ($statusCode).',
  };

  /// Reloads this day's entries from the backend.
  ///
  /// Preserves whatever editing, saving or analysis state is already in
  /// progress — a refresh only ever touches [DayEntriesState.entries] and
  /// [DayEntriesState.errorMessage], so a poll or an open editor is never
  /// interrupted by the list being reloaded underneath it.
  Future<void> refresh() async {
    try {
      final entries = await ref.read(entriesApiProvider).listByDate(date);
      if (!ref.mounted) return;
      state = state.copyWith(
        entries: entries,
        hasLoaded: true,
        errorMessage: null,
      );
    } on ApiError catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(hasLoaded: true, errorMessage: _messageFor(error));
    }
  }

  /// Opens [entry] for editing, starting from exactly what is stored.
  void startEditing(Entry entry) {
    state = state.copyWith(
      editingId: entry.id,
      draft: entry.rawText,
      proposal: null,
    );
  }

  /// Records the in-progress draft text.
  void updateDraft(String text) => state = state.copyWith(draft: text);

  /// Leaves the editor without saving.
  void cancelEditing() => state = state.copyWith(editingId: null, draft: '');

  /// Clears the current error message once the screen has shown it.
  void dismissError() => state = state.copyWith(errorMessage: null);

  /// Dismisses the feeling proposal without accepting it. The entry keeps
  /// whatever feeling it already had.
  void dismissProposal() => state = state.copyWith(proposal: null);

  /// Saves the edited text, then waits for the re-analysis it triggers.
  ///
  /// A no-op when the draft is empty or unchanged, matching the composer's
  /// own "nothing to save" rule.
  Future<void> saveEdit() async {
    final entryId = state.editingId;
    if (entryId == null) return;
    final entry = state.entries.where((e) => e.id == entryId).firstOrNull;
    if (entry == null) return;
    final text = state.draft.trim();
    if (text.isEmpty || text == entry.rawText) {
      state = state.copyWith(editingId: null, draft: '');
      return;
    }

    state = state.copyWith(isSaving: true, errorMessage: null);
    try {
      final result = await ref
          .read(entriesApiProvider)
          .update(id: entryId, version: entry.version, text: text);
      if (!ref.mounted) return;
      switch (result) {
        case EntryUpdated():
          state = state.copyWith(
            isSaving: false,
            editingId: null,
            draft: '',
            isAnalysing: true,
          );
          await refresh();
          await _awaitAnalysis(entryId);
        case EntryOutOfDate():
          state = state.copyWith(
            isSaving: false,
            editingId: null,
            errorMessage:
                "This entry changed somewhere else, so your edit wasn't "
                'applied. Reopen it to see the current text.',
          );
        case EntryRemoved():
          // `update` never actually returns this -- only `deleteById`
          // does -- but `EntryMutation` is sealed and this switch must
          // stay exhaustive.
          state = state.copyWith(isSaving: false, editingId: null);
      }
    } on ApiError catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(isSaving: false, errorMessage: _messageFor(error));
    }
  }

  /// Polls the edited entry until the backend has finished re-reading it.
  ///
  /// Analysis is asynchronous — a worker process runs the model — so the
  /// verdict is not in the `PATCH` response. The wait is bounded by
  /// [analysisPollConfigProvider]: if the worker is not running or the
  /// model is slow, the edit is still saved and this simply stops waiting
  /// rather than hanging on it.
  Future<void> _awaitAnalysis(String entryId) async {
    final config = ref.read(analysisPollConfigProvider);
    final delay = ref.read(analysisPollDelayProvider);
    var waited = Duration.zero;
    while (waited < config.timeout) {
      await delay(config.interval);
      waited += config.interval;
      if (!ref.mounted) return;

      final Entry polled;
      try {
        polled = await ref.read(entriesApiProvider).getById(entryId);
      } on ApiError {
        break;
      }
      if (!ref.mounted) return;

      if (!polled.analysisPending) {
        final suggested = [
          for (final suggestion in polled.suggestedFeelings) suggestion.feeling,
        ];
        state = state.copyWith(
          isAnalysing: false,
          proposal: suggested.isEmpty
              ? null
              : FeelingProposal(entryId, suggested),
        );
        await refresh();
        return;
      }
    }
    if (!ref.mounted) return;
    state = state.copyWith(isAnalysing: false);
  }

  /// Accepts the proposed feelings. This is the only thing on this screen
  /// that changes an entry's feelings.
  Future<void> acceptProposal() async {
    final proposal = state.proposal;
    if (proposal == null) return;
    final entry = state.entries
        .where((e) => e.id == proposal.entryId)
        .firstOrNull;
    if (entry == null) return;

    state = state.copyWith(isSaving: true, proposal: null);
    String? errorMessage;
    try {
      final result = await ref
          .read(entriesApiProvider)
          .update(
            id: entry.id,
            version: entry.version,
            feelings: proposal.feelings,
          );
      // A stale confirmation is reported the same way any other failure
      // here is: this screen has no conflict panel of its own, and the
      // list is about to be refreshed with whatever is actually stored.
      if (result case EntryOutOfDate(:final message)) errorMessage = message;
    } on ApiError catch (error) {
      errorMessage = _messageFor(error);
    }
    if (!ref.mounted) return;
    state = state.copyWith(isSaving: false, errorMessage: errorMessage);
    await refresh();
  }
}

/// The state behind one day's entries screen, keyed by the date shown.
final dayEntriesControllerProvider =
    NotifierProvider.family<
      DayEntriesController,
      DayEntriesState,
      CalendarDate
    >(
      DayEntriesController.new,
    );
