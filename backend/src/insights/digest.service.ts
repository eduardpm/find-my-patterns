import { Injectable } from '@nestjs/common';
import { decodeDate, serializeDate, todayLocal, type PlainDate } from '../db/codecs';
import { EntriesRepository } from '../entries/entries.repository';
import { addDays, digestHighlightSentenceFor, movementSentenceFor, weekStart } from './analysis';
import { CONFIRMED_FEELING_SOURCES } from './constants';
import { PatternsService, type PatternOut, type RecommendationOut } from './patterns.service';

/**
 * [R-2] Weekly digest — "one pattern, one recommendation, one movement", read fresh on every
 * request rather than stored (same C-06 shape as `series.service.ts`/`when.service.ts`: a pure
 * read, never a second place the engine runs). A client fetches this when the digest sheet opens,
 * not when the reminder fires — see the controller's doc comment for why the notification itself
 * carries no content.
 */

/** One entry standing behind the week's highlighted pattern, this week only (R-2-02). */
export interface DigestHighlightOut {
  pattern_ref: string;
  kind: 'forward' | 'inverse';
  topic: string;
  feeling: string;
  /** Entries *this week* carrying this pattern's evidence — not `PatternOut.occurrence_count`,
   *  which is windowed over `RECENCY_WINDOW_DAYS`, not a calendar week. */
  week_count: number;
  lift: number;
  sentence: string;
}

export interface DigestMovementOut {
  feeling: string;
  current_count: number;
  previous_count: number;
  direction: 'up' | 'down' | 'flat';
  sentence: string;
}

/** The empty-week shape (task 1's own words): nothing else is computed, so nothing else is sent. */
export interface DigestEmptyOut {
  empty: true;
  entry_count: 0;
}

export interface DigestOut {
  empty: false;
  /** The Monday that starts the digested week, `YYYY-MM-DD` (`analysis.ts#weekStart`'s convention). */
  week: string;
  entry_count: number;
  /** Omitted, never `null` — a client that has never heard of a part should not have to decode one
   *  it cannot render, the same additive contract `PatternOut.recommendation` documents for R-1. */
  highlight?: DigestHighlightOut;
  recommendation?: RecommendationOut;
  movement?: DigestMovementOut;
}

export type DigestResponse = DigestEmptyOut | DigestOut;

/** A malformed `week` query parameter. The controller maps this to the API's validation status. */
export class InvalidDigestWeekError extends Error {}

@Injectable()
export class DigestService {
  constructor(
    private readonly patterns: PatternsService,
    private readonly entries: EntriesRepository,
  ) {}

  /**
   * `weekRaw`, when given, is any `YYYY-MM-DD` date inside the target week — not necessarily the
   * Monday — normalised through `weekStart()` the same way `series.service.ts` normalises a chart
   * period. That is what acceptance criterion 1 ("same data + week → same digest") needs: the
   * caller supplies the date instead of this service reading `todayLocal()` itself, so a test can
   * pin a Tuesday and a Sunday to the same week and get back the same digest. Omit it and this
   * defaults to the week containing today's server-local date — the live, unpinned path a real
   * client's digest sheet actually calls.
   */
  get(userId: string, weekRaw?: string): DigestResponse {
    const anchor = weekRaw === undefined ? todayLocal() : parseDigestWeek(weekRaw);
    const monday = weekStart(anchor);
    const sunday = addDays(monday, 6);
    const previousMonday = addDays(monday, -7);
    const previousSunday = addDays(monday, -1);

    // Every entry written this week, drafts excluded — `findInDateRange` already applies the same
    // `GUIDED_DRAFT_SENTINEL` filter `EntriesRepository`'s other reads use. Unlike the feeling-level
    // counts below, this is not restricted to confirmed feelings: "you wrote n entries this week" is
    // a claim about writing, not about what was later confirmed, and it is the one number the empty
    // case still owes the user (task 1).
    const weekEntries = this.entries.findInDateRange(userId, monday, sunday);
    if (weekEntries.length === 0) {
      return { empty: true, entry_count: 0 };
    }

    const mondayStr = serializeDate(monday);
    const sundayStr = serializeDate(sunday);
    const patterns = this.patterns.listPatterns(userId);

    // R-2-02: "strongest active pattern with activity this week." `PatternOut.evidence` already
    // carries every contributing entry's date (`patterns.service.ts#evidenceByPattern`), so no
    // second query is needed to learn which patterns fired this week — only a filter over data this
    // same read already loaded. Context patterns (`kind: 'context'`) never reach `listPatterns()`
    // (they live behind their own `contextPatterns()` read, C-06) so the kind guard below is
    // defensive, matching `attachRecommendations`'s own belt-and-suspenders check.
    //
    // `direction !== 'none'` (rather than merely `lift !== null`) is deliberate: `badgeDirectionFor`
    // already decided a neutral-valence pattern, or one whose lift is defined but below `MIN_LIFT`,
    // has "nothing to advise" (see its own doc comment). A digest highlight is exactly that kind of
    // claim — "your week, in one pattern" — so the same rule that withholds a badge for a
    // meaningless direction withholds the highlight slot for one too. This also guarantees `lift` is
    // a defined number, the same way `attachRecommendations`'s `'keep'` filter does.
    const highlightCandidates = patterns
      .filter(
        (pattern): pattern is PatternOut & { kind: 'forward' | 'inverse'; lift: number } =>
          pattern.status === 'active' &&
          (pattern.kind === 'forward' || pattern.kind === 'inverse') &&
          pattern.direction !== 'none' &&
          pattern.lift !== null,
      )
      .map((pattern) => ({
        pattern,
        weekCount: pattern.evidence.filter(
          (evidence) => evidence.entry_date >= mondayStr && evidence.entry_date <= sundayStr,
        ).length,
      }))
      .filter((candidate) => candidate.weekCount > 0);

    // Same tiebreak family as `attachRecommendations`/`buildCandidates` (C-02): the strongest
    // measured effect first, then the count that actually varies week to week, then a name — never
    // `id`, a random UUID two clients could disagree about.
    highlightCandidates.sort(
      (a, b) =>
        b.pattern.lift - a.pattern.lift ||
        b.weekCount - a.weekCount ||
        `${a.pattern.topic} ${a.pattern.feeling}`.localeCompare(
          `${b.pattern.topic} ${b.pattern.feeling}`,
        ),
    );
    const highlightPick = highlightCandidates[0];
    const highlight: DigestHighlightOut | undefined = highlightPick
      ? {
          pattern_ref: highlightPick.pattern.id,
          kind: highlightPick.pattern.kind,
          topic: highlightPick.pattern.topic,
          feeling: highlightPick.pattern.feeling,
          week_count: highlightPick.weekCount,
          lift: highlightPick.pattern.lift,
          sentence: digestHighlightSentenceFor(
            highlightPick.pattern.topic,
            highlightPick.weekCount,
            highlightPick.pattern.narrative_text,
          ),
        }
      : undefined;

    // "Recommendation = R-1's top card" (the ticket's own words) — reused, not re-derived. Every
    // pattern with a non-null `recommendation` is already one of `attachRecommendations`'s top
    // `MAX_RECOMMENDATIONS` by lift; re-applying that exact tiebreak over just those (at most three)
    // patterns recovers the same #1 that function ranked first before it ever sliced the array, with
    // no second selection rule to keep in sync with R-1's. Deliberately not scoped to this week — R-1
    // never was, and scoping it here would make "the top card" two different things depending on
    // which endpoint asked for it.
    const recommendationCandidates = patterns.filter((pattern) => pattern.recommendation !== null);
    recommendationCandidates.sort(
      (a, b) =>
        (b.lift ?? 0) - (a.lift ?? 0) ||
        b.occurrence_count - a.occurrence_count ||
        `${a.topic} ${a.feeling}`.localeCompare(`${b.topic} ${b.feeling}`),
    );
    const recommendation = recommendationCandidates[0]?.recommendation ?? undefined;

    // R-2-03: movement tracks the highlighted pattern's *feeling*, counted at entry granularity from
    // `entry_feelings` directly (the same table `when.service.ts` reads) — never the topic×feeling
    // *pair* `patterns.service.ts` counts. That choice is deliberate, not an oversight: #26/#109
    // taught the pair-counting rule to exclude a mixed-valence entry's unconfirmed combinations
    // (`excluded_unpaired`), and re-deriving pair counting here for a single week-over-week delta
    // would (a) duplicate a rule this file has no business restating and (b) make the movement
    // figure's honesty depend on a pairing-exclusion edge case the user has no reason to expect from
    // a sentence about a *feeling*. "Anxious appeared in 3 entries" is unambiguous however the
    // entry's topics were paired; that is the fact this number states. With no highlight this week
    // there is no feeling to track movement for, so `movement` is omitted along with it.
    let movement: DigestMovementOut | undefined;
    if (highlight !== undefined) {
      const feeling = highlight.feeling;
      const currentCount = countConfirmedFeeling(weekEntries, feeling);
      const previousEntries = this.entries.findInDateRange(userId, previousMonday, previousSunday);
      const previousCount = countConfirmedFeeling(previousEntries, feeling);
      const direction: DigestMovementOut['direction'] =
        currentCount === previousCount ? 'flat' : currentCount > previousCount ? 'up' : 'down';
      movement = {
        feeling,
        current_count: currentCount,
        previous_count: previousCount,
        direction,
        sentence: movementSentenceFor(feeling, currentCount, previousCount),
      };
    }

    return {
      empty: false,
      week: mondayStr,
      entry_count: weekEntries.length,
      ...(highlight !== undefined ? { highlight } : {}),
      ...(recommendation !== undefined ? { recommendation } : {}),
      ...(movement !== undefined ? { movement } : {}),
    };
  }
}

/** Entries in `pool` whose *confirmed* feelings include `feelingKey` — I5-07's rule again: an
 *  unconfirmed suggestion is not evidence a movement figure may cite. */
function countConfirmedFeeling(
  pool: Array<{ feelingKeys: string[]; feelingSource: string }>,
  feelingKey: string,
): number {
  return pool.filter(
    (entry) =>
      CONFIRMED_FEELING_SOURCES.includes(entry.feelingSource) &&
      entry.feelingKeys.includes(feelingKey),
  ).length;
}

function parseDigestWeek(value: string): PlainDate {
  try {
    return decodeDate(value);
  } catch {
    throw new InvalidDigestWeekError(`Invalid 'week' date: '${value}', expected format YYYY-MM-DD`);
  }
}
