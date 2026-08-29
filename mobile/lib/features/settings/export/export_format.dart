/// The two shapes `GET /export` answers in (backend M-6).
enum ExportFormat {
  /// One `##` section per entry, meant to be read.
  markdown,

  /// The whole diary as structured data, meant to be parsed by another tool
  /// (the Daylio import, eventually).
  json;

  /// The value the backend's `?format=` query parameter expects.
  String get queryValue => switch (this) {
    ExportFormat.markdown => 'markdown',
    ExportFormat.json => 'json',
  };

  /// The label shown on the format-choice sheet.
  String get label => switch (this) {
    ExportFormat.markdown => 'Markdown (.md)',
    ExportFormat.json => 'JSON (.json)',
  };

  /// The MIME type handed to the share sheet so the receiving app knows what
  /// it was given.
  String get mimeType => switch (this) {
    ExportFormat.markdown => 'text/markdown',
    ExportFormat.json => 'application/json',
  };

  /// The filename used when the server's response carries none.
  String get defaultFilename => switch (this) {
    ExportFormat.markdown => 'find-my-patterns-export.md',
    ExportFormat.json => 'find-my-patterns-export.json',
  };
}
