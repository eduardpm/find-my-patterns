import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diary/diary_providers.dart';
import '../../core/diary/topic.dart';
import '../../core/diary/topics_api.dart';
import '../../core/network/api_error.dart';

/// The topics list, together with the most recent failure that has not yet
/// been shown.
///
/// A plain record rather than a bespoke class: [TopicsController] already
/// does the state bookkeeping an [AsyncNotifier] gives for free, so there is
/// nothing here worth a hand-rolled `copyWith` for two fields.
typedef TopicsState = ({List<TopicDetail> topics, String? errorMessage});

/// Loads the topic list and applies the alias edits the Topics screen
/// offers.
///
/// Topic normalisation has a half the backend cannot decide alone. The
/// canonical list handles what is true for everyone — a project review is
/// work — and this controller handles what is true for one person: "gym
/// session" is exercise in most diaries and something else entirely in a
/// physiotherapist's. The alternative was asking a model whether two phrases
/// mean the same thing, which is exactly the judgement this project keeps it
/// out of. Everything added through [addAlias] and removed through
/// [removeAlias] takes effect on the next recompute — no model runs, and no
/// entry changes.
class TopicsController extends AsyncNotifier<TopicsState> {
  @override
  Future<TopicsState> build() => _fetch(ref.watch(topicsApiProvider));

  Future<TopicsState> _fetch(TopicsApi api) async {
    try {
      final topics = await api.list();
      return (topics: topics, errorMessage: null);
    } on ApiError catch (error) {
      return (topics: const <TopicDetail>[], errorMessage: _messageFor(error));
    }
  }

  /// Reloads the list from the backend.
  ///
  /// Called after every successful add or remove so counts and badges never
  /// drift from what the backend actually holds.
  Future<void> refresh() async {
    state = await AsyncValue.guard(() => _fetch(ref.read(topicsApiProvider)));
  }

  /// Teaches [topicId] a new spelling, [alias].
  ///
  /// Returns whether the write succeeded, so the caller can decide whether to
  /// clear its draft field — a rejected alias should stay on screen for the
  /// user to fix, not vanish along with what they typed.
  Future<bool> addAlias(String topicId, String alias) async {
    try {
      await ref.read(topicsApiProvider).addAlias(topicId, alias);
      await refresh();
      return true;
    } on ApiError catch (error) {
      _fail(error);
      return false;
    }
  }

  /// Forgets [alias] on [topicId].
  Future<void> removeAlias(String topicId, String alias) async {
    try {
      await ref.read(topicsApiProvider).removeAlias(topicId, alias);
      await refresh();
    } on ApiError catch (error) {
      _fail(error);
    }
  }

  /// Clears the current error message once the screen has shown it, so a
  /// rebuild does not show the same `SnackBar` again.
  void dismissError() {
    final current = state.value;
    if (current == null || current.errorMessage == null) return;
    state = AsyncData((topics: current.topics, errorMessage: null));
  }

  void _fail(ApiError error) {
    final current =
        state.value ?? (topics: const <TopicDetail>[], errorMessage: null);
    state = AsyncData((
      topics: current.topics,
      errorMessage: _messageFor(error),
    ));
  }

  static String _messageFor(ApiError error) => switch (error) {
    BackendNotConfigured() => 'Set your server address in Settings.',
    NetworkFailure() => 'Could not reach the server.',
    Unauthorized() => 'Please sign in again.',
    HttpFailure(:final statusCode) => 'Server error ($statusCode).',
  };
}

/// The Topics screen's state.
final topicsControllerProvider =
    AsyncNotifierProvider<TopicsController, TopicsState>(TopicsController.new);
