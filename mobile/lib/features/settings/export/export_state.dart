/// The Export flow's state — what the "Export my diary" row and its format
/// sheet show while a download and share are underway.
///
/// Sealed so a widget switching over it handles every case: nothing to show
/// beyond the row itself ([ExportIdle]), a spinner and a disabled row
/// ([ExportInProgress]), or a message with a way to try again ([ExportError]).
sealed class ExportState {
  const ExportState();
}

/// Nothing in progress. The row is tappable.
class ExportIdle extends ExportState {
  /// Creates the idle state.
  const ExportIdle();
}

/// A download and hand-off to the share sheet are underway.
class ExportInProgress extends ExportState {
  /// Creates the in-progress state.
  const ExportInProgress();
}

/// The last attempt failed. [message] is shown so the user knows whether to
/// retry (a network hiccup) or fix something first (no server configured).
class ExportError extends ExportState {
  /// Creates the error state, carrying [message].
  const ExportError(this.message);

  /// A description of what went wrong, suitable for showing directly.
  final String message;
}
