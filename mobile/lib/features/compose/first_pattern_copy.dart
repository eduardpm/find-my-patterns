import '../../core/diary/pattern.dart';

/// The first-pattern celebration's title (L-3/#38), shared by the inline
/// `FirstPatternCard` (`first_pattern_card.dart`) and
/// `ReminderService.showFirstPatternNotification` so the two surfaces
/// never drift apart.
///
/// Deliberately modest and fixed, per the ticket: "the tone is 'the
/// evidence is ready', ... no streak-app confetti."
const String firstPatternNotificationTitle = 'Your first pattern is ready';

/// The inline celebration card's one line of copy.
///
/// Carries no number, unlike [firstPatternNotificationBody]: the card sits
/// directly above [PatternEcho]/pattern evidence already on screen, so
/// repeating a count here would just be noise next to numbers the reader
/// can already see.
const String firstPatternCardText =
    'Your first pattern is ready — see the evidence.';

/// The first-pattern notification's body, e.g. "3 entries point the same
/// way. See the evidence."
///
/// [Pattern.occurrenceCount] is real evidence read off [pattern] itself --
/// this repo's rule that a claim never shows a plausible-looking constant
/// applies here as much as anywhere else, so the "3" in the ticket's own
/// example copy is illustrative, not a literal this function is allowed to
/// hardcode.
///
/// Falls back to a copy naming no number at all when [pattern] cannot
/// honestly back one (an occurrence count of zero or less -- never
/// expected from a backend that only reports a pattern once it has crossed
/// its minimum-occurrence threshold, but this is the diary's very first
/// celebration and must not overstate what a malformed payload would
/// otherwise be dressed up as).
String firstPatternNotificationBody(Pattern pattern) {
  final count = pattern.occurrenceCount;
  if (count <= 0) return 'The evidence is ready. See what the diary found.';
  final phrase = count == 1 ? '1 entry points' : '$count entries point';
  return '$phrase the same way. See the evidence.';
}
