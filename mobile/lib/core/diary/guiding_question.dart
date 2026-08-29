/// Mirrors the backend's `GuidingQuestion.category` enum.
enum QuestionCategory {
  /// The single mandatory prompt shown first for every guided entry.
  general,

  /// A prompt about the body or the mind together.
  mindBody,

  /// A prompt about small, easy-to-miss influences on the day.
  smallInfluences,

  /// A prompt about how something turned out.
  responseOutcome,

  /// A category this build does not recognise.
  unknown;

  /// Resolves a wire category string; anything outside the closed
  /// vocabulary — including null — is [unknown]. Never throws.
  static QuestionCategory fromWire(String? raw) => switch (raw) {
    'general' => QuestionCategory.general,
    'mind_body' => QuestionCategory.mindBody,
    'small_influences' => QuestionCategory.smallInfluences,
    'response_outcome' => QuestionCategory.responseOutcome,
    _ => QuestionCategory.unknown,
  };
}

/// A predefined prompt shown during entry creation.
///
/// The whole library is fetched once via `GET /guiding-questions` and cached
/// client-side — [triggerKeywords] drives which optional prompts
/// [matchingOptionalQuestions] surfaces while the user types, with zero
/// additional network calls.
class const GuidingQuestion(
  final String key,
  final QuestionCategory category,
  final String promptText,
  final List<String> triggerKeywords,
  final bool isMandatory,
);

/// One answered prompt, ready to submit as part of `POST /entries`'
/// `guided_answers`.
class const GuidingQuestionAnswer(
  final String questionKey,
  final String answerText,
);

final RegExp _wordSplitPattern = RegExp(r"[^\p{L}\p{N}']+", unicode: true);

/// Client-side keyword matching against the draft entry text.
///
/// Decides which optional guiding questions to surface next, entirely
/// on-device and with zero network calls while the user is typing — the
/// guiding-question library itself is fetched and cached once elsewhere, so
/// this is pure, synchronous, local logic that can run on every keystroke.
///
/// Returns up to [maxCount] non-mandatory questions from [library] whose
/// [GuidingQuestion.triggerKeywords] appear in [draftText], in library
/// order. Mandatory questions (the single general prompt) are never
/// included here — the caller always shows that one first.
List<GuidingQuestion> matchingOptionalQuestions(
  String draftText,
  List<GuidingQuestion> library, {
  int maxCount = 2,
}) {
  if (draftText.trim().isEmpty || library.isEmpty) return const [];

  final lowerText = draftText.toLowerCase();
  final words = lowerText
      .split(_wordSplitPattern)
      .where((word) => word.isNotEmpty)
      .toSet();

  final matches = <GuidingQuestion>[];
  for (final question in library) {
    if (question.isMandatory) continue;
    final isMatch = question.triggerKeywords.any((keyword) {
      final lowerKeyword = keyword.toLowerCase();
      return lowerKeyword.trim().isNotEmpty &&
          (words.contains(lowerKeyword) || lowerText.contains(lowerKeyword));
    });
    if (isMatch) matches.add(question);
    if (matches.length >= maxCount) break;
  }
  return matches;
}
