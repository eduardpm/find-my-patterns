import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diary/diary_providers.dart';
import '../../core/diary/experiment.dart';
import '../../core/network/api_error.dart';

/// Reads and abandons one experiment's results (R-3b).
///
/// Family-keyed on the experiment id, the same shape
/// `entryDetailControllerProvider` uses for one entry: the results screen
/// is reached from the active-experiment banner and from a pattern card
/// alike, both of which already know the id, so this fetches through
/// `GET /experiments/{id}/results` for exactly that one experiment rather
/// than filtering a list down to it.
class ExperimentResultsController extends AsyncNotifier<ExperimentResults> {
  /// Creates the controller for experiment [experimentId].
  ExperimentResultsController(this.experimentId);

  /// The experiment this screen shows.
  final String experimentId;

  @override
  Future<ExperimentResults> build() =>
      ref.watch(experimentsApiProvider).results(experimentId);

  /// Refetches the results -- reachable via pull-to-refresh, and while an
  /// experiment is still running this simply reads a little further into
  /// its "so far" window each time.
  Future<void> refresh() async {
    ref.invalidateSelf();
    try {
      await future;
    } on ApiError {
      // Already reflected in `state`; the screen's own listener reports it.
    }
  }

  /// Abandons the experiment this screen shows (always available while it
  /// is active -- point 4 of R-3b), then refetches so the screen reflects
  /// the now-abandoned status.
  ///
  /// Bumps [diaryWriteSignalProvider] the same way starting one does (see
  /// `ExperimentSetupSheet`'s doc comment): abandoning is not an entry
  /// write, but it is exactly the "something elsewhere may have changed"
  /// fact Today's own copy of the active experiment already listens for.
  Future<void> abandon() async {
    await ref.read(experimentsApiProvider).abandon(experimentId);
    ref.read(diaryWriteSignalProvider.notifier).bump();
    await refresh();
  }
}

/// The state behind the experiment-results screen, keyed by experiment id.
final experimentResultsControllerProvider =
    AsyncNotifierProvider.family<
      ExperimentResultsController,
      ExperimentResults,
      String
    >(ExperimentResultsController.new);
