/// The knobs this app turns: its identity, the backend contract it speaks, and
/// whether sign-in gates it at all.
///
/// Everything here is a compile-time constant on purpose. These are decisions
/// made once per app, not settings a user changes; anything the user can change
/// lives in `AppSettings` instead.
abstract final class AppConfig {
  /// The app's display name, shown on the splash and in Settings → About.
  static const String appName = 'Find My Patterns';

  /// The app's version.
  ///
  /// Must match the version in `pubspec.yaml`; a test asserts that it does, so
  /// the two cannot drift apart unnoticed.
  static const String appVersion = '1.0.0';

  /// The port suggested when no server has been configured yet.
  static const int defaultPort = 8000;

  /// The key prefix for everything this app writes to device storage.
  static const String storagePrefix = 'find_my_patterns';

  /// The health-check endpoint the Settings screen probes.
  static const String healthPath = '/health';

  /// The session resource.
  ///
  /// The diary backend keeps its own form-based sign-in for the public tunnel
  /// and leaves the local network open, so [requireAuth] is off and this path
  /// is only reachable if a fork ever turns it on.
  static const String sessionPath = '/auth/session';

  /// Whether the app is gated behind a password sign-in.
  ///
  /// The diary runs on the user's own network. The backend's optional
  /// public-hostname auth is an HTML form served to browsers, not a JSON
  /// session this client drives, so the app never shows a login screen.
  static const bool requireAuth = false;

  /// The diary-entry collection: `POST` to create, `GET` to list a day.
  static const String entriesPath = '/entries';

  /// One entry, by id: `GET`, `PATCH` and `DELETE`.
  static String entryPath(String entryId) => '$entriesPath/$entryId';

  /// The pattern echo attached to one entry.
  static String entryEchoPath(String entryId) => '${entryPath(entryId)}/echo';

  /// One entry's topic↔feeling pairing set (E-1a/E-1c): `PUT` replaces it
  /// whole.
  static String entryTopicFeelingsPath(String entryId) =>
      '${entryPath(entryId)}/topic-feelings';

  /// The feeling vocabulary the composer offers.
  static const String feelingsPath = '/feelings';

  /// The guiding-question library the guided flow walks.
  static const String guidingQuestionsPath = '/guiding-questions';

  /// The detected patterns shown on Insights.
  static const String insightsPath = '/insights';

  /// The time-of-day breakdown behind the Insights "when" panel.
  static const String insightsWhenPath = '/insights/when';

  /// The per-day mood series behind the Insights mood-trend chart, and the
  /// Today screen's writing streak (#40) -- one point per day with at least
  /// one entry, `from`/`to` inclusive.
  static const String seriesPath = '/insights/series';

  /// Acknowledges a withdrawn pattern so the notice stops being shown.
  static const String withdrawalAcknowledgePath =
      '/insights/withdrawals/acknowledge';

  /// [R-2] The week's highlight pattern, top recommendation and movement
  /// figure -- fetched when the digest sheet opens, never at the moment the
  /// scheduled notification fires.
  static const String digestPath = '/insights/digest';

  /// A month's worth of entry density, for the calendar.
  static const String monthlySummaryPath = '/monthly-summary';

  /// The canonical topics and their aliases.
  static const String topicsPath = '/topics';

  /// One topic's alias collection: `POST` to add.
  static String topicAliasesPath(String topicId) =>
      '$topicsPath/$topicId/aliases';

  /// One alias on one topic: `DELETE` to drop it.
  static String topicAliasPath(String topicId, String alias) =>
      '${topicAliasesPath(topicId)}/${Uri.encodeComponent(alias)}';

  /// The transcription-job collection: `POST` raw audio to start one.
  static const String transcriptionsPath = '/transcriptions';

  /// One transcription job, polled until it finishes.
  static String transcriptionPath(String jobId) => '$transcriptionsPath/$jobId';

  /// The whole-diary export (M-6): `GET`, streaming back either a Markdown or
  /// a JSON document of every entry.
  static String exportPath(String format) => '/export?format=$format';

  /// The N-of-1 experiment collection (R-3a/R-3b): `POST` to start one.
  static const String experimentsPath = '/experiments';

  /// The currently active experiment, if any: `GET`.
  static const String experimentActivePath = '$experimentsPath/active';

  /// Abandons one experiment: `POST`.
  static String experimentAbandonPath(String experimentId) =>
      '$experimentsPath/$experimentId/abandon';

  /// One experiment's two-window comparison and verdict: `GET`.
  static String experimentResultsPath(String experimentId) =>
      '$experimentsPath/$experimentId/results';
}
