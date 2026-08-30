import { Inject, Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import {
  decodeDate,
  decodeDateTime,
  decodeJson,
  encodeDate,
  encodeDateTime,
  encodeJson,
  nowUtc,
  serializeDate,
  serializeDateTime,
  todayLocal,
  type NaiveDateTime,
  type PlainDate,
} from '../db/codecs';
import { SCOPED_DB, type ScopedDb } from '../db/scoped-db';
import type { PatternDirection } from '../domain/types';
import { TopicsService } from '../topics/topics.service';
import {
  associationFrom,
  confounderSplit,
  contextFactorsForEntry,
  contextNarrative,
  daysBetween,
  forwardNarrative,
  historicalNote,
  invert,
  inverseNarrative,
  isMixedValence,
  isPairExcluded as pairIsExcluded,
  isStrong,
  recommendationHeadlineFor,
  recommendationSentenceFor,
  suppressedByLift,
  templateSuggestionFor,
  withinWindow,
  type Association,
  type ConfounderSplit,
} from './analysis';
import {
  CONFIRMED_FEELING_SOURCES,
  CONTEXT_FACTORS,
  MAX_CONTEXT_PATTERNS,
  MAX_INVERSE_PATTERNS,
  MAX_RECOMMENDATIONS,
  MAX_WITHDRAWAL_RECORDS,
  MIN_COMPARISON_ENTRIES,
  MIN_LIFT,
  MIN_OCCURRENCE_THRESHOLD,
  RECENCY_WINDOW_DAYS,
} from './constants';

/**
 * Deterministic pattern detection (spec 002 FR-009/FR-012, roadmap A1–A3, I1–I3).
 *
 * Two layers, kept apart exactly as the constitution's "Deterministic Core, LLM at the Edges"
 * requires:
 *
 *  1. **`analysis.ts` — pure counting.** No database, no LLM. Windows, lift, collinearity and
 *     every sentence stating a number live there and are unit-tested in isolation.
 *  2. **this file — orchestration.** It reads real rows, hands them to those functions, stores what
 *     comes back, and asks the LLM only how to *phrase* advice that deterministic code already
 *     confirmed.
 *
 * The engine's whole output is rebuilt on every recompute. That is what lets an edited entry
 * change a count, a lift and a withdrawal notice in one pass, with no incremental state that could
 * disagree with the entries it was derived from.
 */

export { MIN_OCCURRENCE_THRESHOLD, CONFIRMED_FEELING_SOURCES } from './constants';
export { templateSuggestionFor } from './analysis';

/**
 * The observation, stated with the numbers that produced it.
 *
 * Kept as a named export because it is the sentence the engine's tests assert against — the point
 * of the exercise is that the claim the user reads is reproducible from their own diary, so it has
 * to be reproducible from a test too.
 */
export function observationFor(
  feelingKey: string,
  topic: string,
  association: Association,
): string {
  return forwardNarrative(feelingKey, topic, association, RECENCY_WINDOW_DAYS);
}

/**
 * `'context'` is #21's addition: a pattern whose "present" side is a passive context factor
 * (`weekday:sunday`, `timeofday:evening`, …) rather than an extracted topic. It is deliberately a
 * third value on the same type, not a separate one — `badgeDirectionFor`/`directionFor` switch on
 * `kind`, and a context pattern must fall through their `!== 'inverse'` branch unchanged rather than
 * forking the badge logic for a third time.
 */
export type PatternKind = 'forward' | 'inverse' | 'context';
export type PatternStatus = 'active' | 'historical';
/**
 * Why a pattern stopped qualifying — a fixed set decided by data, never by a model (A2-02).
 *
 * The spec listed three. `below_lift` is a fourth, added deliberately: A3 introduced a way for a
 * pattern to be withdrawn with its evidence completely intact — the occurrences held, and the
 * *association* stopped clearing the minimum lift. Folding that into `below_threshold`, whose
 * definition is "count dropped below the minimum", produced notices that read
 * "below the minimum of 3" beside a count of 12 → 12, and left clients no way to label the two
 * cases differently because they could only branch on the code.
 *
 * `excluded_unpaired` is a fifth, added by #109 (E-1d). #26 (E-1b) taught the engine to exclude a
 * mixed-valence entry's unconfirmed combinations from a pair's count; the very next recompute after
 * that landed then withdrew every pair whose count depended entirely on now-excluded entries — and
 * mislabelled all of them `no_longer_confirmed`, which claims the entries carry no feeling the user
 * confirmed. That is false: the entries carry a confirmed feeling, they simply never confirmed
 * *this pairing* of it. `excluded_unpaired` is the honest label for that specific cause, kept
 * distinct from `no_longer_confirmed`'s genuine case — an entry with no confirmed feeling at all,
 * which is a different diary fact and must go on reaching its own label undisturbed.
 */
export type WithdrawalReason =
  'below_threshold' | 'below_lift' | 'no_longer_confirmed' | 'topic_merged' | 'excluded_unpaired';

/** One entry standing behind a pattern (A1-01). */
export interface EvidenceOut {
  entry_id: string;
  entry_date: string;
  raw_text: string;
  feeling_keys: string[];
  feeling_source: string;
}

export interface ConfounderOut {
  topic: string;
  co_occurrence_rate: number;
  both_count: number;
  only_this_count: number;
  only_other_count: number;
  neither_count: number;
  inseparable: boolean;
  note: string;
}

/**
 * R-1: a "Worth trying" card, attached to the pattern it was derived from.
 *
 * `action_topic` is the bare topic name (e.g. `exercise`) — useful for a client that wants to key
 * off it (analytics, de-duplication), but deliberately not the only thing a client has to build a
 * headline from. `headline` and `sentence` are sent fully composed, in the exact wording
 * `mobile/CLAUDE.md`'s "the backend owns the logic" requires: a client that turned `action_topic`
 * back into "More exercise days" itself would be re-deriving copy this file already decided, the
 * same mistake that rule exists to rule out for every count and rate elsewhere in this payload.
 *
 * `pattern_ref` is the owning `PatternOut.id` — not a new identifier — so "tap through to the
 * pattern" is "find the card already in `patterns` whose `id` matches this", never a second lookup
 * the client has to reconcile against the first.
 */
export interface RecommendationOut {
  action_topic: string;
  headline: string;
  sentence: string;
  pattern_ref: string;
}

export interface PatternOut {
  id: string;
  kind: PatternKind;
  topic: string;
  feeling: string;
  /** The **windowed** count — the number the card shows, and the length of `evidence` (A1-02). */
  occurrence_count: number;
  lifetime_count: number;
  status: PatternStatus;
  /** The badge this card shows — see `badgeDirectionFor`, computed fresh on every read. */
  direction: PatternDirection;
  narrative_text: string;
  suggestion_text: string;
  present_count: number;
  present_total: number;
  absent_count: number;
  absent_total: number;
  present_rate: number | null;
  absent_rate: number | null;
  base_rate: number;
  lift: number | null;
  comparison_reason: string | null;
  comparison_note: string | null;
  is_strong: boolean;
  last_occurrence_date: string | null;
  days_since_last_occurrence: number | null;
  historical_note: string | null;
  confounders: ConfounderOut[];
  evidence: EvidenceOut[];
  last_updated_at: string;
  /**
   * R-1: `null` for almost every pattern — only the top `MAX_RECOMMENDATIONS` by lift among those
   * whose `direction` is `'keep'` carry one (see `listPatterns`'s recommendation pass). Additive:
   * an older client that has never heard of this field ignores it exactly as it already ignores any
   * other key it does not decode (`mobile/lib/core/diary/pattern.dart`'s null-tolerant casts, and
   * likewise on `web/`).
   */
  recommendation: RecommendationOut | null;
}

/**
 * A passive context pattern (#21) — deliberately a leaner shape than `PatternOut`. There is no
 * `suggestion_text` (nothing is phrased by the LLM for these — the worker never sees them),
 * no `confounders` (that annotation is about topic entanglement, and context factors are never
 * paired with each other or checked for entanglement — task 4's flooding guard), and no
 * `last_updated_at` (nothing here is stored, so there is no "last changed" moment to report — every
 * field is recomputed fresh on every `GET /insights`, same as `WhenInsights`).
 */
export interface ContextPatternOut {
  /** Deterministic, not random (contrast `PatternOut.id`) — the same `factor`+`feeling` always
   *  produces the same id, because nothing persists this row for a client to key off instead. */
  id: string;
  kind: 'context';
  /** e.g. `weekday:sunday`, `timeofday:evening` — see `CONTEXT_FACTORS` for the full set. */
  factor: string;
  factor_category: 'weekday' | 'daytype' | 'timeofday' | 'season';
  /** e.g. `Sunday`, `Evening` — the display label from `CONTEXT_FACTORS`. */
  factor_label: string;
  feeling: string;
  occurrence_count: number;
  lifetime_count: number;
  status: PatternStatus;
  direction: PatternDirection;
  narrative_text: string;
  present_count: number;
  present_total: number;
  absent_count: number;
  absent_total: number;
  present_rate: number | null;
  absent_rate: number | null;
  base_rate: number;
  lift: number | null;
  comparison_reason: string | null;
  comparison_note: string | null;
  is_strong: boolean;
  evidence: EvidenceOut[];
}

export interface WithdrawalOut {
  id: string;
  topic: string;
  feeling: string;
  kind: PatternKind;
  previous_count: number;
  new_count: number;
  reason: WithdrawalReason;
  detail_text: string;
  withdrawn_at: string;
  is_new: boolean;
}

/**
 * Pure: count `(topicId, feelingKey)` occurrences and return only those meeting the threshold.
 *
 * Still the minimum-occurrence rule in its entirety (FR-008). Lift filters and ranks on top of it;
 * it does not replace it (A3-09).
 */
export function qualifyingPairs(
  occurrences: Array<[string, string]>,
  threshold: number = MIN_OCCURRENCE_THRESHOLD,
): Map<string, number> {
  const counts = new Map<string, number>();
  for (const [topicId, feelingKey] of occurrences) {
    const key = `${topicId} ${feelingKey}`;
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  const qualifying = new Map<string, number>();
  for (const [key, count] of counts) {
    if (count >= threshold) qualifying.set(key, count);
  }
  return qualifying;
}

/**
 * Which badge a pattern card shows (P0-2) — the single function this decision is made by, so a
 * card and its neighbour covering the same topic can never disagree about it.
 *
 * FR-011 for forward pairs: a positive feeling is worth keeping, a negative one prompts a change.
 * A neutral feeling has no positive signal to reinforce and no negative one to discourage — it is
 * not "leaning change", it is nothing to advise, so it gets `'none'` rather than being folded into
 * "change" the way it used to be. A card that read "you felt calm around walking — consider
 * changing it" was that fold showing through.
 *
 * I1-05 extends the forward/inverse split to the inverse card, and the extension is not a mirror.
 * An inverse pattern says the feeling is likelier *without* the topic. When that feeling is a bad
 * one, the topic's absence is what coincides with feeling bad, so the topic itself is the thing
 * worth keeping.
 *
 * P0-6: a `lift` that could not be computed (division by zero on either side, so `null`) or that
 * fell below `minLift` earns no badge either, checked in an early return ahead of the kind/valence
 * switch below. A card that prints "LIFT —" and still says "consider changing" is advice built on
 * the one number the card itself says it cannot state — exactly the claim-with-no-number the rest
 * of this engine refuses to make. The callers below (and the client) go on reading whatever this
 * function returns without change; only the input they already had — the lift — is new.
 */
export function badgeDirectionFor(
  kind: PatternKind,
  valence: string,
  lift: number | null,
  minLift: number = MIN_LIFT,
): PatternDirection {
  if (lift === null || lift < minLift) return 'none';
  if (valence !== 'positive' && valence !== 'negative') return 'none';
  if (kind === 'inverse') return valence === 'negative' ? 'keep' : 'change';
  return valence === 'positive' ? 'keep' : 'change';
}

/**
 * The two-valued direction persisted per pattern (FR-011, I1-05) — distinct from the badge
 * (`badgeDirectionFor`) that reads the same kind and valence.
 *
 * This one feeds `inference/worker.ts`'s suggestion-phrasing prompt and is validated by
 * `db/compatibility.ts` on every startup, `['keep', 'change'].includes(...)` and nothing else.
 * Neither has a "no opinion" state to spend, so unlike the badge, a neutral-valence pattern here
 * still collapses to `'change'` — exactly what it did before the badge grew a `'none'` state, and
 * changing it would mean teaching both of those a third state they have no use for. For the same
 * reason it is unaffected by P0-6's lift check: it is evaluated as if the lift always cleared the
 * minimum, so only kind and valence ever decide it.
 */
export function directionFor(kind: PatternKind, valence: string): 'keep' | 'change' {
  const badge = badgeDirectionFor(kind, valence, Number.POSITIVE_INFINITY);
  return badge === 'none' ? 'change' : badge;
}

/** The sentence a missing lift is replaced by — never a number (A3-02, A3-05). */
export function comparisonNoteFor(
  reason: string | null,
  topic: string,
  kind: PatternKind,
): string | null {
  const otherSide = kind === 'forward' ? `without ${topic}` : `mentioning ${topic}`;
  switch (reason) {
    case 'insufficient_comparison':
      return `Not enough entries ${otherSide} to compare — this is an observation, not yet evidence.`;
    case 'no_absent_occurrences':
      return `This feeling does not appear in any entry ${otherSide}, so there is no ratio to state.`;
    case 'no_window_evidence':
      return `Nothing in the last ${RECENCY_WINDOW_DAYS} days to compare — this pattern is historical.`;
    default:
      return null;
  }
}

/**
 * `comparisonNoteFor`'s counterpart for a context pattern (#21).
 *
 * Not a fork of the same wording with a topic swapped in: `comparisonNoteFor`'s phrasing depends on
 * `kind` to say "without work" vs "mentioning work", and neither reads naturally for a context
 * factor ("without Sundays"). The reason codes and their meaning are identical — this only changes
 * how each is put into words.
 */
export function contextComparisonNoteFor(reason: string | null): string | null {
  switch (reason) {
    case 'insufficient_comparison':
      return 'Not enough other entries to compare — this is an observation, not yet evidence.';
    case 'no_absent_occurrences':
      return 'This feeling does not appear in any other entry, so there is no ratio to state.';
    case 'no_window_evidence':
      return `Nothing in the last ${RECENCY_WINDOW_DAYS} days to compare — this pattern is historical.`;
    default:
      return null;
  }
}

interface LoadedEntry {
  id: string;
  entryDate: PlainDate;
  rawText: string;
  feelingKeys: string[];
  feelingSource: string;
  topicIds: string[];
  /**
   * E-1b: this entry's own confirmed topic↔feeling pairings, as `${topicId} ${feelingKey}` keys.
   *
   * Sourced only from `CONFIRMED_FEELING_SOURCES` rows in `entry_topic_feelings` — a `suggested`
   * row is the worker's guess (`inference/worker.ts`'s `INSERT OR IGNORE ... 'suggested'`), never a
   * user confirmation, and counting it as one would reintroduce exactly the contamination this
   * rule exists to remove. Empty for an entry the user never opened the pairing step on, which is
   * indistinguishable here from one where every pairing was left unlinked — both read as "nothing
   * confirmed for this pair" to the counting rule below, which is the conservative behaviour rule 2
   * asks for.
   */
  confirmedPairs: Set<string>;
}

interface Candidate {
  key: string;
  kind: PatternKind;
  topicId: string;
  topicName: string;
  feelingKey: string;
  windowCount: number;
  lifetimeCount: number;
  lastOccurrence: PlainDate | null;
  association: Association;
  baseRate: number;
  evidenceIds: string[];
  confounders: ConfounderSplit[];
}

/** #21: what `contextPatterns` needs from an entry — no topics, no raw text, no side effects. */
interface ContextLoadedEntry {
  id: string;
  entryDate: PlainDate;
  createdAt: NaiveDateTime;
  feelingKeys: string[];
}

/** #21: one `(contextFactor, feelingKey)` candidate, before the lift cap and the top-N-by-lift cut. */
interface ContextCandidate {
  factor: string;
  feelingKey: string;
  lifetimeCount: number;
  association: Association;
  baseRate: number;
  evidenceIds: string[];
}

@Injectable()
export class PatternsService {
  constructor(
    @Inject(SCOPED_DB) private readonly db: ScopedDb,
    private readonly topics: TopicsService,
  ) {}

  // -------------------------------------------------------------------------------------------
  // Loading
  // -------------------------------------------------------------------------------------------

  /**
   * Every entry that counts as evidence, with its feelings and its topics.
   *
   * `CONFIRMED_FEELING_SOURCES` is applied in the SQL rather than afterwards, so there is no path
   * through this file on which a `suggested` or `imported` entry could reach a count (C-04).
   */
  private loadEvidenceEntries(userId: string): LoadedEntry[] {
    const handle = this.db.forUser(userId);
    const placeholders = CONFIRMED_FEELING_SOURCES.map(() => '?').join(', ');
    const rows = handle
      .prepare(
        `SELECT e.id, e.entry_date, e.raw_text, e.feeling_source, ef.feeling_key
         FROM diary_entries e
         JOIN entry_feelings ef ON ef.entry_id = e.id
         WHERE e.user_id = ? AND e.feeling_source IN (${placeholders})
         ORDER BY e.entry_date, e.id, ef.position`,
      )
      .all(userId, ...CONFIRMED_FEELING_SOURCES) as Array<{
      id: string;
      entry_date: string;
      raw_text: string;
      feeling_source: string;
      feeling_key: string;
    }>;

    const byEntry = new Map<string, LoadedEntry>();
    for (const row of rows) {
      let entry = byEntry.get(row.id);
      if (!entry) {
        entry = {
          id: row.id,
          entryDate: decodeDate(row.entry_date),
          rawText: row.raw_text,
          feelingKeys: [],
          feelingSource: row.feeling_source,
          topicIds: [],
          confirmedPairs: new Set(),
        };
        byEntry.set(row.id, entry);
      }
      entry.feelingKeys.push(row.feeling_key);
    }

    // E-1b: every confirmed pairing, loaded once alongside the entries themselves rather than
    // per pair inside `buildCandidates` — `recomputePatterns` already runs over the whole diary in
    // one pass (C-06), and a per-pair lookup would turn that one pass into a round trip per
    // candidate pair. A row for an entry not in `byEntry` (its own feelings were never confirmed)
    // is simply not attached to anything; such an entry contributes no evidence at all already.
    const pairingPlaceholders = CONFIRMED_FEELING_SOURCES.map(() => '?').join(', ');
    for (const row of handle
      .prepare(
        `SELECT entry_id, topic_id, feeling_key FROM entry_topic_feelings
         WHERE user_id = ? AND source IN (${pairingPlaceholders})`,
      )
      .all(userId, ...CONFIRMED_FEELING_SOURCES) as Array<{
      entry_id: string;
      topic_id: string;
      feeling_key: string;
    }>) {
      byEntry.get(row.entry_id)?.confirmedPairs.add(`${row.topic_id} ${row.feeling_key}`);
    }

    // Re-scan every eligible entry. Keyword links are derived data: remove the previous extraction
    // first, so editing "coffee" out of an entry also removes its support from the coffee pattern.
    // Merely inserting newly found links leaves patterns permanently stale. Done once per entry,
    // not once per (entry, feeling) — re-extracting per feeling would delete the links the
    // previous pass had just written.
    for (const entry of byEntry.values()) {
      handle
        .prepare(
          "DELETE FROM entry_topics WHERE user_id = ? AND entry_id = ? AND extracted_by = 'keyword'",
        )
        .run(userId, entry.id);
      this.topics.extractAndLinkTopics(userId, entry.id, entry.rawText);
      entry.topicIds = this.topics.topicsForEntry(userId, entry.id).map((topic) => topic.id);
    }

    return [...byEntry.values()];
  }

  // -------------------------------------------------------------------------------------------
  // Recompute
  // -------------------------------------------------------------------------------------------

  async recomputePatterns(userId: string): Promise<{ excludedUnpaired: number }> {
    // Consolidation first, so the counting that follows sees one row per idea rather than three
    // fragments of it, and so a user's alias edit takes effect on this read (A4-04/A4-05).
    this.topics.mergeFragmentedTopics(userId);

    const entries = this.loadEvidenceEntries(userId);
    const today = todayLocal();
    const topicNames = new Map(
      (
        this.db
          .forUser(userId)
          .prepare('SELECT id, name FROM topics WHERE user_id = ?')
          .all(userId) as Array<{ id: string; name: string }>
      ).map((row) => [row.id, row.name]),
    );

    const inWindow = entries.filter((entry) =>
      withinWindow(entry.entryDate, today, RECENCY_WINDOW_DAYS),
    );

    const valences = this.feelingValences(userId);
    const { candidates, excludedUnpaired, excludedFromThreshold, windowCounts } =
      this.buildCandidates(entries, inWindow, topicNames, valences);
    this.storeCandidates(
      userId,
      candidates,
      topicNames,
      valences,
      excludedUnpaired,
      excludedFromThreshold,
      windowCounts,
    );
    return { excludedUnpaired };
  }

  /** Everything the engine decided this pass, before a single row is written. */
  private buildCandidates(
    entries: LoadedEntry[],
    inWindow: LoadedEntry[],
    topicNames: Map<string, string>,
    valences: Map<string, string>,
  ): {
    candidates: Candidate[];
    excludedUnpaired: number;
    /** [E-1d, #109] Forward `"${topicId} ${feelingKey}"` keys rule 2's exclusion, not a lack of
     *  evidence, dropped below the threshold — `recordWithdrawal`'s only source for telling
     *  `excluded_unpaired` apart from a pair that genuinely never had enough confirmed evidence. */
    excludedFromThreshold: Set<string>;
    /** [E-1d, #109] `"${topicId} ${feelingKey}"` → the windowed, exclusion-aware count for every
     *  pair a confirmed entry forms — `recordWithdrawal`'s source for a forward withdrawal's
     *  `new_count`, so the number a notice states is never blind to the exclusion that may be the
     *  entire reason it is being withdrawn. */
    windowCounts: Map<string, number>;
  } {
    const windowTotal = inWindow.length;

    // Entry-level sets. An entry is either in a set or not, however many feelings it carries — a
    // verbose entry must not outvote a quiet week.
    //
    // E-1b: deliberately built from *every* in-window entry, contaminated or not. `entriesWithFeeling`
    // feeds `baseRateFor` — an excluded entry still counts toward feeling base rates per the issue's
    // rule 2 — and `entriesWithTopic` feeds `confoundersFor` (I2's collinearity annotation), which is
    // a different question (does another topic travel with this one?) that the pairing rule has no
    // opinion on. The pairing exclusion is applied surgically, per pair, only inside `association`
    // below — not by shrinking these two marginal sets.
    const entriesWithTopic = new Map<string, Set<string>>();
    const entriesWithFeeling = new Map<string, Set<string>>();
    for (const entry of inWindow) {
      for (const topicId of entry.topicIds) {
        if (!entriesWithTopic.has(topicId)) entriesWithTopic.set(topicId, new Set());
        entriesWithTopic.get(topicId)!.add(entry.id);
      }
      for (const feelingKey of entry.feelingKeys) {
        if (!entriesWithFeeling.has(feelingKey)) entriesWithFeeling.set(feelingKey, new Set());
        entriesWithFeeling.get(feelingKey)!.add(entry.id);
      }
    }

    // E-1b rule 1/4: whether each entry's own feelings span both valence signs — computed once per
    // entry (it depends only on the entry's own feelings, never on which topic or pair is being
    // asked about) and covering every entry, not just the ones in the window, because `lifetimeCounts`
    // below needs the same test applied to the whole diary.
    const isMixedByEntry = new Map<string, boolean>(
      entries.map((entry) => [
        entry.id,
        isMixedValence(entry.feelingKeys, (key) => valences.get(key)),
      ]),
    );

    // E-1b rules 2/3: an entry is excluded from one specific (topicId, feelingKey) pair's counting
    // when it is mixed-valence *and* that exact pair is not among its own confirmed pairings —
    // whether because the user left it unlinked while confirming others, or skipped the pairing step
    // for the whole entry (an empty `confirmedPairs` reads as "nothing confirmed" for every pair the
    // entry could otherwise form, which is rule 2's conservative default). Single-valence entries are
    // never excluded from anything — rule 1's "no behaviour change" for the common case.
    const isPairExcluded = (entry: LoadedEntry, topicId: string, feelingKey: string): boolean =>
      pairIsExcluded(
        isMixedByEntry.get(entry.id) ?? false,
        entry.confirmedPairs,
        topicId,
        feelingKey,
      );

    // Lifetime pair evidence, which is what decides whether a pattern exists at all; the window
    // decides whether it is active (I3-03).
    //
    // E-1b: run over the whole diary, not just the window, so a pattern built entirely out of
    // contaminated occurrences never reaches `MIN_OCCURRENCE_THRESHOLD` in the first place — the
    // bug this ticket exists to fix. An excluded occurrence updates neither the count nor
    // `lastOccurrence`; as far as this pair is concerned, the entry never happened.
    const lifetimeCounts = new Map<string, number>();
    const lastOccurrence = new Map<string, PlainDate>();
    for (const entry of entries) {
      for (const topicId of entry.topicIds) {
        for (const feelingKey of entry.feelingKeys) {
          if (isPairExcluded(entry, topicId, feelingKey)) continue;
          const key = `${topicId} ${feelingKey}`;
          lifetimeCounts.set(key, (lifetimeCounts.get(key) ?? 0) + 1);
          const previous = lastOccurrence.get(key);
          if (!previous || daysBetween(previous, entry.entryDate) > 0) {
            lastOccurrence.set(key, entry.entryDate);
          }
        }
      }
    }

    // [E-1d, #109] The same tally as `lifetimeCounts` above, but *without* `isPairExcluded` — every
    // confirmed entry counts, mixed-valence or not. The gap between this map and `lifetimeCounts`
    // is exactly the evidence rule 2 removed, which is what lets `recordWithdrawal` tell "this pair
    // fell because #26 excluded its entries" (`excluded_unpaired`) apart from "this pair genuinely
    // never had enough confirmed evidence" (`below_threshold`) — the confusion #109 was filed over.
    // Both maps are keyed on CONFIRMED_FEELING_SOURCES entries only (`entries` already is), so
    // neither can be confused with `no_longer_confirmed`'s question, which is about *unconfirmed*
    // entries instead.
    const rawLifetimeCounts = new Map<string, number>();
    for (const entry of entries) {
      for (const topicId of entry.topicIds) {
        for (const feelingKey of entry.feelingKeys) {
          const key = `${topicId} ${feelingKey}`;
          rawLifetimeCounts.set(key, (rawLifetimeCounts.get(key) ?? 0) + 1);
        }
      }
    }

    // [E-1d, #109] A pair belongs here when its confirmed evidence would have cleared
    // `MIN_OCCURRENCE_THRESHOLD` were it not for rule 2's exclusion, and only then — a pair that
    // never had enough evidence in the first place (even before exclusion) is `below_threshold`
    // instead, and the exclusion had nothing to do with why it left. Forward-only: rule 2 never
    // touches an inverse pattern's absent side (see `association` below), so an inverse pair can
    // never land here.
    const excludedFromThreshold = new Set<string>();
    for (const [key, raw] of rawLifetimeCounts) {
      if (raw < MIN_OCCURRENCE_THRESHOLD) continue;
      if ((lifetimeCounts.get(key) ?? 0) < MIN_OCCURRENCE_THRESHOLD) excludedFromThreshold.add(key);
    }

    // [E-1d, #109] The windowed counterpart of `lifetimeCounts`, kept for every pair a confirmed
    // entry ever forms — not only the ones that become candidates — so a *withdrawn* pair's notice
    // can state a `new_count` that actually reflects rule 2, the same way `association` below
    // already does for a pair still active. Recomputing it via a second loop rather than reading
    // `association(topicId, feelingKey).presentCount` for every candidate: `association` is a
    // closure over `entriesWithTopic`/`entriesWithFeeling`, cheap for the handful of forward
    // candidates it is already called for, but this map is looked up for pairs that never became a
    // candidate at all — every existing pattern the recompute is about to consider withdrawing.
    const windowCounts = new Map<string, number>();
    for (const entry of inWindow) {
      for (const topicId of entry.topicIds) {
        for (const feelingKey of entry.feelingKeys) {
          if (isPairExcluded(entry, topicId, feelingKey)) continue;
          const key = `${topicId} ${feelingKey}`;
          windowCounts.set(key, (windowCounts.get(key) ?? 0) + 1);
        }
      }
    }

    // E-1b: the same exclusion, tallied per pair and scoped to the window, so `association` below
    // can shrink one pair's table without touching the marginal sets above. Only entries that
    // actually carry *both* topicId and feelingKey can ever be excluded from that pair (see
    // `isPairExcluded`), so this only ever needs entries the double loop below already visits.
    const excludedInWindowByPair = new Map<string, number>();
    for (const entry of inWindow) {
      if (!(isMixedByEntry.get(entry.id) ?? false)) continue;
      for (const topicId of entry.topicIds) {
        for (const feelingKey of entry.feelingKeys) {
          const key = `${topicId} ${feelingKey}`;
          if (entry.confirmedPairs.has(key)) continue;
          excludedInWindowByPair.set(key, (excludedInWindowByPair.get(key) ?? 0) + 1);
        }
      }
    }

    // Acceptance criterion 5's `excludedUnpaired`: entries the pairing step was skipped for
    // *entirely* — zero confirmed pairing rows — not entries that confirmed some pairs and left a
    // cross combination unlinked. The §11.7 example is the reason for that distinction: an entry
    // that confirmed (exercise, disappointed) and (family, happy) has permanently and deliberately
    // excluded (exercise, happy) — pairing it "some more" changes nothing, because there is nothing
    // left unresolved. Only an entry with no confirmed pairing rows at all is one where confirming
    // *anything* would move it from counting toward nothing to counting toward whatever it
    // confirms, which is the literal claim "not counted until you pair them" makes. An entry with
    // no topics at all has nothing to pair and is correctly never counted here either.
    const excludedUnpaired = inWindow.filter(
      (entry) =>
        (isMixedByEntry.get(entry.id) ?? false) &&
        entry.confirmedPairs.size === 0 &&
        entry.topicIds.length > 0,
    ).length;

    const association = (topicId: string, feelingKey: string): Association => {
      const withTopic = entriesWithTopic.get(topicId) ?? new Set<string>();
      const withFeeling = entriesWithFeeling.get(feelingKey) ?? new Set<string>();
      let rawPresentCount = 0;
      for (const id of withTopic) if (withFeeling.has(id)) rawPresentCount += 1;
      // E-1b: computed from the *raw*, unexcluded sets, before the pair's own exclusions are
      // subtracted below. An excluded entry always carries topicId (that is what makes it eligible
      // for exclusion from this pair in the first place — see `isPairExcluded`), so it can never be
      // part of the "without topicId" group; the absent side is therefore unaffected by this pair's
      // exclusions and must not be computed from the adjusted present numbers, or an excluded entry
      // would be silently reclassified onto the absent side instead of removed from the table.
      const absentTotal = windowTotal - withTopic.size;
      const absentCount = withFeeling.size - rawPresentCount;

      // The pair's own table shrinks by exactly the entries excluded from it: both `presentCount`
      // and `presentTotal` drop by the same amount, so the pair's effective denominator
      // (`presentTotal + absentTotal`, asserted by the property test) is `windowTotal` minus this
      // pair's exclusions — never `windowTotal` itself once anything has been excluded, and never
      // `windowTotal` plus the exclusion (which is what computing `absentTotal` from the *adjusted*
      // `presentTotal` would produce instead).
      const excluded = excludedInWindowByPair.get(`${topicId} ${feelingKey}`) ?? 0;
      const presentCount = rawPresentCount - excluded;
      const presentTotal = withTopic.size - excluded;

      return associationFrom(presentCount, presentTotal, absentCount, absentTotal);
    };

    const baseRateFor = (feelingKey: string): number =>
      windowTotal === 0 ? 0 : (entriesWithFeeling.get(feelingKey)?.size ?? 0) / windowTotal;

    const evidenceIn = (predicate: (entry: LoadedEntry) => boolean): string[] =>
      inWindow
        .filter(predicate)
        // A1-04: oldest first, ties broken by id, so two clients never disagree about the order
        // of two entries written on the same day.
        .sort(
          (a, b) =>
            daysBetween(b.entryDate, a.entryDate) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0),
        )
        .map((entry) => entry.id);

    const candidates: Candidate[] = [];

    // --- Forward patterns (A3, I3) --------------------------------------------------------------
    for (const [key, lifetimeCount] of lifetimeCounts) {
      if (lifetimeCount < MIN_OCCURRENCE_THRESHOLD) continue;
      const [topicId, feelingKey] = key.split(' ');
      const topicName = topicNames.get(topicId);
      if (!topicName) continue;

      const assoc = association(topicId, feelingKey);
      // A3-04. Only a lift that was actually computed can suppress: an un-computable one is not a
      // weak one, and treating it as weak would delete the diary's cleanest evidence.
      if (suppressedByLift(assoc)) continue;

      candidates.push({
        key: `forward ${key}`,
        kind: 'forward',
        topicId,
        topicName,
        feelingKey,
        windowCount: assoc.presentCount,
        lifetimeCount,
        lastOccurrence: lastOccurrence.get(key) ?? null,
        association: assoc,
        baseRate: baseRateFor(feelingKey),
        // E-1b: the evidence trail must name exactly the entries `assoc.presentCount` counted, so a
        // contaminated occurrence excluded from the count above is excluded from the list too — a
        // card that said "3 entries" beside a fourth, unpaired one would be showing evidence for a
        // number it did not use.
        evidenceIds: evidenceIn(
          (entry) =>
            entry.topicIds.includes(topicId) &&
            entry.feelingKeys.includes(feelingKey) &&
            !isPairExcluded(entry, topicId, feelingKey),
        ),
        confounders: [],
      });
    }

    // --- Inverse patterns (I1) ------------------------------------------------------------------
    // Enumerated over the cross product rather than over co-occurrences, because the strongest
    // inverse pattern is the one where the topic and the feeling never appear together at all —
    // and a co-occurrence scan cannot see a pair that never co-occurs.
    //
    // E-1b: this calls the same `association(topicId, feelingKey)` the forward loop uses, so it
    // inherits the pairing exclusion with no separate code path. That is also why it needs none of
    // its own: `invert()` only swaps the four already-adjusted numbers, and the entries this loop's
    // own `evidenceIn` predicate selects (those *without* topicId) can never be the ones excluded
    // from this pair — `isPairExcluded` only ever removes an entry that carries both topicId and
    // feelingKey, which by definition is on the forward side, not this one.
    const inverses: Candidate[] = [];
    for (const [topicId, topicEntries] of entriesWithTopic) {
      const topicName = topicNames.get(topicId);
      if (!topicName) continue;
      // I1-08 / A3-05: the comparison side here is the *present* side, and it is held to the same
      // minimum as any other comparison group.
      if (topicEntries.size < MIN_COMPARISON_ENTRIES) continue;

      for (const [feelingKey, feelingEntries] of entriesWithFeeling) {
        if (feelingEntries.size < MIN_OCCURRENCE_THRESHOLD) continue;
        const inverseAssoc = invert(association(topicId, feelingKey));
        if (inverseAssoc.presentCount < MIN_OCCURRENCE_THRESHOLD) continue;
        if (suppressedByLift(inverseAssoc)) continue;
        // The same rule the forward side uses, and for the same reason. `no_absent_occurrences`
        // means the feeling never once appeared alongside the topic — the strongest inverse
        // pattern a diary can hold — and rejecting it for having too clean a table would delete
        // exactly the finding I1 exists to surface. What is rejected is a comparison group too
        // small to conclude anything from (I1-08).
        if (
          inverseAssoc.comparisonReason === 'insufficient_comparison' ||
          inverseAssoc.comparisonReason === 'no_window_evidence'
        ) {
          continue;
        }

        inverses.push({
          key: `inverse ${topicId} ${feelingKey}`,
          kind: 'inverse',
          topicId,
          topicName,
          feelingKey,
          windowCount: inverseAssoc.presentCount,
          lifetimeCount: inverseAssoc.presentCount,
          lastOccurrence: null,
          association: inverseAssoc,
          baseRate: baseRateFor(feelingKey),
          evidenceIds: evidenceIn(
            (entry) => !entry.topicIds.includes(topicId) && entry.feelingKeys.includes(feelingKey),
          ),
          confounders: [],
        });
      }
    }
    // I1-06: ranked by strength and capped, so the "what helps" half never floods the list it
    // shares with forward patterns.
    // A pattern with no counter-example ranks above every measurable lift, which is what an
    // unbounded ratio means — not what a zero would mean.
    const strength = (candidate: Candidate): number =>
      candidate.association.lift ?? Number.POSITIVE_INFINITY;
    // The final tiebreak is the topic *name* and the feeling, never the pattern key: the key
    // carries a topic's UUID, so ranking on it made which five inverse patterns survived the cap
    // depend on random identifiers — a different five on each diary, and two clients disagreeing
    // about the same data (C-02). Ties are common here precisely because an unbounded lift is the
    // normal case for an inverse pattern.
    const rank = (candidate: Candidate): string => `${candidate.topicName} ${candidate.feelingKey}`;
    inverses.sort(
      (a, b) =>
        strength(b) - strength(a) ||
        b.windowCount - a.windowCount ||
        rank(a).localeCompare(rank(b)),
    );
    candidates.push(...inverses.slice(0, MAX_INVERSE_PATTERNS));

    // --- Confounder annotations (I2) ------------------------------------------------------------
    for (const candidate of candidates) {
      if (candidate.kind !== 'forward') continue;
      candidate.confounders = this.confoundersFor(
        candidate.topicId,
        candidate.topicName,
        entriesWithTopic,
        topicNames,
        windowTotal,
      );
    }

    // E-1b acceptance criterion 5: reported top-level (not per-pattern), computed above, because
    // the issue's own phrasing, "n entries not counted until you pair them", is a fact about the
    // diary as a whole, not about any one card — and a per-pattern figure would have nowhere
    // sensible to live on a pattern that never reaches the occurrence threshold in the first place,
    // which a top-level count still accounts for correctly.
    return { candidates, excludedUnpaired, excludedFromThreshold, windowCounts };
  }

  /**
   * Which other topics travel closely enough with this one to muddy its pattern (I2).
   *
   * Annotation only. A pattern is never hidden because of a confounder — withholding the evidence
   * would contradict the product's own explainability principle (I2-07). Topics that A4 already
   * merged cannot appear here, because by then they are the same row (I2-06).
   */
  private confoundersFor(
    topicId: string,
    topicName: string,
    entriesWithTopic: Map<string, Set<string>>,
    topicNames: Map<string, string>,
    windowTotal: number,
  ): ConfounderSplit[] {
    const mine = entriesWithTopic.get(topicId) ?? new Set<string>();
    const found: ConfounderSplit[] = [];

    for (const [otherId, otherEntries] of entriesWithTopic) {
      if (otherId === topicId) continue;
      const otherName = topicNames.get(otherId);
      if (!otherName) continue;

      let both = 0;
      for (const id of mine) if (otherEntries.has(id)) both += 1;
      if (both === 0) continue;
      const onlyThis = mine.size - both;
      const onlyOther = otherEntries.size - both;
      const neither = windowTotal - both - onlyThis - onlyOther;

      const split = confounderSplit(topicName, otherName, both, onlyThis, onlyOther, neither);
      if (split) found.push(split);
    }

    // Strongest entanglement first; the topic name breaks ties so the order is reproducible.
    found.sort((a, b) => b.coOccurrenceRate - a.coOccurrenceRate || a.topic.localeCompare(b.topic));
    return found;
  }

  // -------------------------------------------------------------------------------------------
  // Context patterns (#21)
  // -------------------------------------------------------------------------------------------

  /**
   * Every confirmed entry's date and time, with nothing else loaded — no topic extraction, no raw
   * text. Unlike `loadEvidenceEntries`, this has no side effect on the database: context factors are
   * derived, not extracted, so there is nothing here to re-scan on every call.
   */
  private loadContextEntries(userId: string): ContextLoadedEntry[] {
    const placeholders = CONFIRMED_FEELING_SOURCES.map(() => '?').join(', ');
    const rows = this.db
      .forUser(userId)
      .prepare(
        `SELECT e.id, e.entry_date, e.created_at, ef.feeling_key
         FROM diary_entries e
         JOIN entry_feelings ef ON ef.entry_id = e.id
         WHERE e.user_id = ? AND e.feeling_source IN (${placeholders})
         ORDER BY e.entry_date, e.id, ef.position`,
      )
      .all(userId, ...CONFIRMED_FEELING_SOURCES) as Array<{
      id: string;
      entry_date: string;
      created_at: string;
      feeling_key: string;
    }>;

    const byEntry = new Map<string, ContextLoadedEntry>();
    for (const row of rows) {
      let entry = byEntry.get(row.id);
      if (!entry) {
        entry = {
          id: row.id,
          entryDate: decodeDate(row.entry_date),
          createdAt: decodeDateTime(row.created_at),
          feelingKeys: [],
        };
        byEntry.set(row.id, entry);
      }
      entry.feelingKeys.push(row.feeling_key);
    }
    return [...byEntry.values()];
  }

  /**
   * `key → valence`, shared by `buildCandidates` and `storeCandidates` (via one call in
   * `recomputePatterns`, so both act on the same snapshot) and by `contextPatterns` (its own
   * separate call — it never runs through `recomputePatterns`, C-06). E-1b added the first of
   * these: `buildCandidates` needs it to decide whether an entry's own feelings are mixed-valence,
   * the same map `directionFor`'s valence lookups already used further down the pipeline.
   */
  private feelingValences(userId: string): Map<string, string> {
    // `feelings` is shared reference vocabulary — no `user_id` column exists on it — but reading it
    // still goes through `forUser(userId)` because that is the only way this class can obtain a
    // handle at all (M-1b, #46): `ScopedDb`'s guard never fires here since the query names no table
    // in `USER_DATA_TABLES`, so this is exactly as unscoped in practice as it always was.
    return new Map(
      (
        this.db.forUser(userId).prepare('SELECT "key", valence FROM feelings').all() as Array<{
          key: string;
          valence: string;
        }>
      ).map((row) => [row.key, row.valence]),
    );
  }

  /**
   * Task 1–4 of #21: weekday/day-type/time-of-day/season, run through the exact same 2×2 + lift
   * machinery `buildCandidates` uses for topics — `associationFrom`, `suppressedByLift`,
   * `MIN_OCCURRENCE_THRESHOLD`, `MIN_LIFT`, all imported unchanged from `analysis.ts`/`constants.ts`.
   *
   * Two differences from the topic side, both deliberate:
   *
   *  - **Forward-only.** There is no context "inverse" here (I1's absent-side view) and no
   *    confounder annotation (I2's entanglement check) — a context factor's absence is a fact about
   *    every *other* factor in its category at once (an entry not on Sunday is on one of six other
   *    days), which is not the single well-defined complement a topic's absence is. Extending both
   *    is explicitly future work, not attempted here.
   *  - **Never stored.** Nothing here touches `patterns`, `pattern_entries` or
   *    `pattern_withdrawals` — recomputed whole on every call, so there is no persisted state a
   *    pattern could be "withdrawn" from. A context pattern that no longer qualifies simply does not
   *    appear in the next response; that *is* this feature's withdrawal semantics (task 2).
   *
   * M-3 (#48): unlike `listPatterns`, this method computes its windowed evidence live on every
   * call rather than reading a value `recomputePatterns` fixed at write time — so, unlike there,
   * `windowDays` here is a genuine parameter, not a two-valued switch over a precomputed status.
   * `null` (premium, "full range") means every entry counts as "in window", which is the correct
   * generalisation: a context pattern's `lifetimeCount` already comes from the unfiltered `entries`
   * below regardless of `windowDays` (the same lifetime-decides-existence split `buildCandidates`
   * makes for topics, I3-03), so widening `inWindow` to the whole diary for premium changes only
   * which of those already-existing candidates clear `association`'s lift/comparison bar, never
   * which pairs are eligible to be considered at all.
   *
   * Defaults to `null` — the pre-M-3 behaviour (`RECENCY_WINDOW_DAYS` was always applied, since it
   * was a hardcoded local, not a parameter) is "no *additional* cap beyond the engine's own", i.e.
   * this method's one production caller, `InsightsController#get`, is also the only one that ever
   * needs to say otherwise.
   */
  contextPatterns(userId: string, windowDays: number | null = null): ContextPatternOut[] {
    const entries = this.loadContextEntries(userId);
    const today = todayLocal();
    const inWindow =
      windowDays === null
        ? entries
        : entries.filter((entry) => withinWindow(entry.entryDate, today, windowDays));
    const windowTotal = inWindow.length;

    // Entry-level sets, exactly as `buildCandidates` keeps them for topics — an entry with three
    // feelings must not outvote a quiet week any more here than it does there.
    const entriesWithFactor = new Map<string, Set<string>>();
    const entriesWithFeeling = new Map<string, Set<string>>();
    for (const entry of inWindow) {
      for (const factor of contextFactorsForEntry(entry.entryDate, entry.createdAt)) {
        if (!entriesWithFactor.has(factor)) entriesWithFactor.set(factor, new Set());
        entriesWithFactor.get(factor)!.add(entry.id);
      }
      for (const feelingKey of entry.feelingKeys) {
        if (!entriesWithFeeling.has(feelingKey)) entriesWithFeeling.set(feelingKey, new Set());
        entriesWithFeeling.get(feelingKey)!.add(entry.id);
      }
    }

    // Lifetime counts decide whether a pattern exists at all; the window decides whether it is
    // active — the same split `buildCandidates` makes for topics (I3-03).
    const lifetimeCounts = new Map<string, number>();
    for (const entry of entries) {
      for (const factor of contextFactorsForEntry(entry.entryDate, entry.createdAt)) {
        for (const feelingKey of entry.feelingKeys) {
          const key = `${factor} ${feelingKey}`;
          lifetimeCounts.set(key, (lifetimeCounts.get(key) ?? 0) + 1);
        }
      }
    }

    const association = (factor: string, feelingKey: string): Association => {
      const withFactor = entriesWithFactor.get(factor) ?? new Set<string>();
      const withFeeling = entriesWithFeeling.get(feelingKey) ?? new Set<string>();
      let presentCount = 0;
      for (const id of withFactor) if (withFeeling.has(id)) presentCount += 1;
      const presentTotal = withFactor.size;
      const absentTotal = windowTotal - presentTotal;
      const absentCount = withFeeling.size - presentCount;
      return associationFrom(presentCount, presentTotal, absentCount, absentTotal);
    };

    const baseRateFor = (feelingKey: string): number =>
      windowTotal === 0 ? 0 : (entriesWithFeeling.get(feelingKey)?.size ?? 0) / windowTotal;

    const evidenceIn = (predicate: (entry: ContextLoadedEntry) => boolean): string[] =>
      inWindow
        .filter(predicate)
        // A1-04, applied here too: oldest first, ties broken by id.
        .sort(
          (a, b) =>
            daysBetween(b.entryDate, a.entryDate) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0),
        )
        .map((entry) => entry.id);

    const candidates: ContextCandidate[] = [];
    for (const [key, lifetimeCount] of lifetimeCounts) {
      if (lifetimeCount < MIN_OCCURRENCE_THRESHOLD) continue;
      const [factor, feelingKey] = key.split(' ');
      const assoc = association(factor, feelingKey);
      // A3-04, unchanged: only a computed lift can suppress a candidate.
      if (suppressedByLift(assoc)) continue;

      candidates.push({
        factor,
        feelingKey,
        lifetimeCount,
        association: assoc,
        baseRate: baseRateFor(feelingKey),
        evidenceIds: evidenceIn(
          (entry) =>
            contextFactorsForEntry(entry.entryDate, entry.createdAt).includes(factor) &&
            entry.feelingKeys.includes(feelingKey),
        ),
      });
    }

    // Task 4's flooding guard: ranked by lift and cut to `MAX_CONTEXT_PATTERNS`, the same shape
    // I1-06 already uses for inverse patterns — except a null lift here sorts *last*, not first.
    // An inverse pattern's null lift means "no counter-example at all", the strongest finding a
    // diary can hold; a context factor's null lift usually just means too few entries outside a
    // 30-day window to compare against (`insufficient_comparison`), which is weaker evidence, not
    // stronger, and ranking it above a computed 4× lift would flood the cap with exactly the
    // candidates it exists to hold back.
    const rank = (candidate: ContextCandidate): string =>
      `${candidate.factor} ${candidate.feelingKey}`;
    candidates.sort(
      (a, b) =>
        (b.association.lift ?? Number.NEGATIVE_INFINITY) -
          (a.association.lift ?? Number.NEGATIVE_INFINITY) ||
        b.association.presentCount - a.association.presentCount ||
        rank(a).localeCompare(rank(b)),
    );

    const valences = this.feelingValences(userId);
    const factorInfo = new Map(CONTEXT_FACTORS.map((factor) => [factor.key, factor]));

    return candidates.slice(0, MAX_CONTEXT_PATTERNS).map((candidate): ContextPatternOut => {
      const info = factorInfo.get(candidate.factor)!;
      const assoc = candidate.association;
      const kind: PatternKind = 'context';
      const status: PatternStatus =
        assoc.presentCount >= MIN_OCCURRENCE_THRESHOLD ? 'active' : 'historical';

      return {
        id: `context:${candidate.factor}:${candidate.feelingKey}`,
        kind,
        factor: candidate.factor,
        factor_category: info.category,
        factor_label: info.label,
        feeling: candidate.feelingKey,
        occurrence_count: assoc.presentCount,
        lifetime_count: candidate.lifetimeCount,
        status,
        // #21's explicit instruction: go through the one function the badge is decided by, not a
        // fork of it. `kind: 'context'` falls through its `!== 'inverse'` branch, unchanged.
        direction: badgeDirectionFor(
          kind,
          valences.get(candidate.feelingKey) ?? 'neutral',
          assoc.lift,
        ),
        narrative_text: contextNarrative(candidate.feelingKey, info.phrase, assoc),
        present_count: assoc.presentCount,
        present_total: assoc.presentTotal,
        absent_count: assoc.absentCount,
        absent_total: assoc.absentTotal,
        present_rate: assoc.presentRate,
        absent_rate: assoc.absentRate,
        base_rate: candidate.baseRate,
        lift: assoc.lift,
        comparison_reason: assoc.comparisonReason,
        comparison_note: contextComparisonNoteFor(assoc.comparisonReason),
        is_strong: isStrong(assoc, assoc.presentCount),
        evidence: this.evidenceRows(userId, candidate.evidenceIds),
      };
    });
  }

  /** The evidence trail for a set of entry ids, in the shape `PatternOut`/`ContextPatternOut` share. */
  private evidenceRows(userId: string, entryIds: string[]): EvidenceOut[] {
    if (entryIds.length === 0) return [];
    const handle = this.db.forUser(userId);
    const placeholders = entryIds.map(() => '?').join(', ');
    const rows = handle
      .prepare(
        `SELECT e.id, e.entry_date, e.raw_text, e.feeling_source
         FROM diary_entries e WHERE e.user_id = ? AND e.id IN (${placeholders})`,
      )
      .all(userId, ...entryIds) as Array<{
      id: string;
      entry_date: string;
      raw_text: string;
      feeling_source: string;
    }>;

    const feelingsByEntry = new Map<string, string[]>();
    if (rows.length > 0) {
      for (const row of handle
        .prepare(
          `SELECT entry_id, feeling_key FROM entry_feelings
           WHERE user_id = ? AND entry_id IN (${placeholders})
           ORDER BY entry_id, position`,
        )
        .all(userId, ...entryIds) as Array<{ entry_id: string; feeling_key: string }>) {
        if (!feelingsByEntry.has(row.entry_id)) feelingsByEntry.set(row.entry_id, []);
        feelingsByEntry.get(row.entry_id)!.push(row.feeling_key);
      }
    }

    const byId = new Map(rows.map((row) => [row.id, row]));
    // Preserve the caller's order (`evidenceIn`'s oldest-first sort) rather than the SQL's.
    return entryIds
      .map((id) => byId.get(id))
      .filter((row): row is (typeof rows)[number] => row !== undefined)
      .map((row) => ({
        entry_id: row.id,
        entry_date: serializeDate(decodeDate(row.entry_date)),
        raw_text: row.raw_text,
        feeling_keys: feelingsByEntry.get(row.id) ?? [],
        feeling_source: row.feeling_source,
      }));
  }

  // -------------------------------------------------------------------------------------------
  // Storage
  // -------------------------------------------------------------------------------------------

  private storeCandidates(
    userId: string,
    candidates: Candidate[],
    topicNames: Map<string, string>,
    valences: Map<string, string>,
    excludedUnpaired: number,
    excludedFromThreshold: Set<string>,
    windowCounts: Map<string, number>,
  ): void {
    const handle = this.db.forUser(userId);
    const existing = new Map<
      string,
      {
        id: string;
        topic_id: string;
        feeling_key: string;
        kind: string;
        occurrence_count: number;
        narrative_text: string;
        suggestion_text: string;
        direction: string;
        status: string;
        narration_attempts: number;
        narration_next_attempt_at: string | null;
      }
    >();
    for (const row of handle
      .prepare(
        `SELECT id, topic_id, feeling_key, kind, occurrence_count, narrative_text, suggestion_text,
                direction, status, narration_attempts, narration_next_attempt_at FROM patterns
         WHERE user_id = ?`,
      )
      .all(userId) as Array<{
      id: string;
      topic_id: string;
      feeling_key: string;
      kind: string;
      occurrence_count: number;
      narrative_text: string;
      suggestion_text: string;
      direction: string;
      status: string;
      narration_attempts: number;
      narration_next_attempt_at: string | null;
    }>) {
      existing.set(`${row.kind} ${row.topic_id} ${row.feeling_key}`, row);
    }

    const seen = new Set<string>();
    const now = encodeDateTime(nowUtc());
    const today = todayLocal();

    for (const candidate of candidates) {
      seen.add(candidate.key);
      const previous = existing.get(candidate.key);
      const status: PatternStatus =
        candidate.windowCount >= MIN_OCCURRENCE_THRESHOLD ? 'active' : 'historical';
      const direction = directionFor(
        candidate.kind,
        valences.get(candidate.feelingKey) ?? 'neutral',
      );
      const narrative =
        candidate.kind === 'forward'
          ? forwardNarrative(candidate.feelingKey, candidate.topicName, candidate.association)
          : inverseNarrative(candidate.feelingKey, candidate.topicName, candidate.association);

      // "Still the template" is the whole definition of un-narrated, and it is why the suggestion
      // is reset whenever the numbers move: a reworded suggestion written for a count of 8 should
      // not survive that count becoming 3. The worker picks the pattern up again on its next pass.
      const narrationStale =
        previous === undefined ||
        previous.narrative_text !== narrative ||
        Number(previous.occurrence_count) !== candidate.windowCount;
      const suggestion = narrationStale
        ? templateSuggestionFor(candidate.feelingKey, candidate.topicName)
        : previous.suggestion_text;

      // #88: a pattern whose suggestion just reverted to the template gets a clean slate of
      // narration attempts, the same way its suggestion itself does just above — a pattern that
      // exhausted its retries under an old count must not stay permanently un-narratable once the
      // count that made it eligible again changes. When the suggestion is untouched, the attempt
      // state is carried over unchanged rather than reset on every recompute.
      const narrationAttempts = narrationStale ? 0 : (previous?.narration_attempts ?? 0);
      const narrationNextAttemptAt = narrationStale
        ? null
        : (previous?.narration_next_attempt_at ?? null);

      // Stamped only when the pattern actually changed. An unconditional stamp made this field
      // mean "when insights were last viewed" and made two clients receive different payloads for
      // unchanged data — fixed during feature 003, and it must not come back.
      const changed =
        previous === undefined ||
        narrationStale ||
        previous.direction !== direction ||
        previous.status !== status;

      const assoc = candidate.association;
      const values = [
        candidate.windowCount,
        narrative,
        suggestion,
        direction,
        candidate.kind,
        candidate.lifetimeCount,
        status,
        candidate.lastOccurrence ? encodeDate(candidate.lastOccurrence) : null,
        assoc.presentCount,
        assoc.presentTotal,
        assoc.absentCount,
        assoc.absentTotal,
        assoc.lift,
        assoc.comparisonReason,
        candidate.baseRate,
        isStrong(assoc, candidate.windowCount) ? 1 : 0,
        encodeJson(candidate.confounders),
        narrationAttempts,
        narrationNextAttemptAt,
      ];

      let patternId: string;
      if (previous === undefined) {
        patternId = randomUUID();
        handle
          .prepare(
            `INSERT INTO patterns (id, user_id, topic_id, feeling_key, first_detected_at,
             last_updated_at, occurrence_count, narrative_text, suggestion_text, direction, kind,
             lifetime_count, status, last_occurrence_date, present_count, present_total,
             absent_count, absent_total, lift, comparison_reason, base_rate, is_strong,
             confounders, narration_attempts, narration_next_attempt_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          )
          .run(
            patternId,
            userId,
            candidate.topicId,
            candidate.feelingKey,
            now,
            now,
            ...values,
          );
      } else {
        patternId = previous.id;
        handle
          .prepare(
            `UPDATE patterns SET occurrence_count = ?, narrative_text = ?, suggestion_text = ?,
             direction = ?, kind = ?, lifetime_count = ?, status = ?, last_occurrence_date = ?,
             present_count = ?, present_total = ?, absent_count = ?, absent_total = ?, lift = ?,
             comparison_reason = ?, base_rate = ?, is_strong = ?, confounders = ?,
             narration_attempts = ?, narration_next_attempt_at = ?${
               changed ? ', last_updated_at = ?' : ''
             } WHERE id = ? AND user_id = ?`,
          )
          .run(...values, ...(changed ? [now] : []), patternId, userId);
      }

      handle.prepare('DELETE FROM pattern_entries WHERE user_id = ? AND pattern_id = ?').run(userId, patternId);
      const insertLink = handle.prepare(
        'INSERT INTO pattern_entries (pattern_id, entry_id, user_id) VALUES (?, ?, ?)',
      );
      for (const entryId of candidate.evidenceIds) insertLink.run(patternId, entryId, userId);

      // A2-05: the pattern is back, so any standing withdrawal notice for it is superseded. The
      // user is never told "withdrawn" and "active" about the same pattern at once.
      handle
        .prepare(
          `UPDATE pattern_withdrawals SET superseded_at = ?
           WHERE user_id = ? AND pattern_key = ? AND superseded_at IS NULL`,
        )
        .run(now, userId, candidate.key);
    }

    // --- Withdrawals (A2) -----------------------------------------------------------------------
    for (const [key, pattern] of existing) {
      if (seen.has(key)) continue;
      this.recordWithdrawal(
        userId,
        key,
        pattern,
        topicNames,
        now,
        today,
        excludedUnpaired,
        excludedFromThreshold,
        windowCounts,
      );
      handle.prepare('DELETE FROM pattern_entries WHERE user_id = ? AND pattern_id = ?').run(userId, pattern.id);
      handle.prepare('DELETE FROM patterns WHERE id = ? AND user_id = ?').run(pattern.id, userId);
    }

    this.pruneWithdrawals(userId);
  }

  /**
   * Say why a pattern went away, in numbers, before deleting it.
   *
   * The reason comes from a fixed set decided by data (A2-02) — never from a model, and never from
   * "whatever happened last". Each branch is a different thing to have happened to the user's
   * diary, and each is worth a different sentence.
   */
  private recordWithdrawal(
    userId: string,
    key: string,
    pattern: {
      id: string;
      topic_id: string;
      feeling_key: string;
      kind: string;
      occurrence_count: number;
    },
    topicNames: Map<string, string>,
    now: string,
    today: PlainDate,
    excludedUnpaired: number,
    excludedFromThreshold: Set<string>,
    windowCounts: Map<string, number>,
  ): void {
    const handle = this.db.forUser(userId);
    const topicName = topicNames.get(pattern.topic_id);
    const previousCount = Number(pattern.occurrence_count);
    const pairKey = `${pattern.topic_id} ${pattern.feeling_key}`;

    // How much of the pair survives, ignoring whether the feeling was confirmed. It is the one
    // question that separates "the user rewrote the entry" from "the user un-confirmed it".
    const anySource = handle
      .prepare(
        `SELECT COUNT(*) AS n FROM entry_topics et
         JOIN entry_feelings ef ON ef.entry_id = et.entry_id
         JOIN diary_entries e ON e.id = et.entry_id
         WHERE et.user_id = ? AND et.topic_id = ? AND ef.feeling_key = ?`,
      )
      .get(userId, pattern.topic_id, pattern.feeling_key) as { n: number };

    const kind: PatternKind = pattern.kind === 'inverse' ? 'inverse' : 'forward';
    // [E-1d, #109] Forward reads its windowed count from `windowCounts` — `buildCandidates`'s own
    // exclusion-aware tally — rather than the SQL below, which knows nothing about rule 2 and would
    // report the same number before and after an exclusion caused the withdrawal (the "2 → 2" a
    // notice must never show beside "was withdrawn"). Inverse never has an exclusion to be blind
    // to (see `buildCandidates`'s `association`), so it keeps reading `currentWindowCount` — and
    // that query's own `membership` branch is the only place that knows how to count it.
    const newCount =
      kind === 'forward'
        ? (windowCounts.get(pairKey) ?? 0)
        : this.currentWindowCount(userId, pattern.topic_id, pattern.feeling_key, today, kind);

    // Ordered so each branch is the *only* thing that can have happened, and so the count is known
    // before the reason is chosen — deciding "below threshold" without looking at the count is how
    // the notice ended up contradicting its own numbers.
    //
    // [E-1d, #109] `excludedFromThreshold` is checked before `anySource` deliberately: an excluded
    // pair's entries still carry the feeling in `entry_feelings` (that is what makes them evidence
    // at all), so `anySource` is true of them too — checking it first would put every
    // `excluded_unpaired` case right back through `no_longer_confirmed`, reintroducing the bug this
    // reason exists to fix. `excludedFromThreshold` is forward-only and empty for a pair that was
    // ever genuinely short on confirmed evidence, so it can never fire for a `no_longer_confirmed`
    // or `below_threshold` case instead.
    let reason: WithdrawalReason;
    if (topicName === undefined) {
      reason = 'topic_merged';
    } else if (newCount >= MIN_OCCURRENCE_THRESHOLD) {
      // The confirmed, windowed evidence still clears the minimum, so the count is not what
      // changed. What changed is the association: lift fell below `MIN_LIFT` (A3-04).
      reason = 'below_lift';
    } else if (kind === 'forward' && excludedFromThreshold.has(pairKey)) {
      reason = 'excluded_unpaired';
    } else if (Number(anySource.n) >= MIN_OCCURRENCE_THRESHOLD) {
      reason = 'no_longer_confirmed';
    } else {
      reason = 'below_threshold';
    }
    // An inverse pattern was never a claim about entries mentioning the topic, so its notice must
    // not read like one. "reading → anxious, now 0" is true of the forward pair and says nothing
    // about the pattern that was actually withdrawn.
    const subject = topicName ?? 'a merged topic';
    const label = `${kind === 'inverse' ? `without ${subject}` : subject} → ${pattern.feeling_key}`;
    // One sentence per reason, and each states the threshold that actually failed.
    const occurrences = (count: number): string =>
      `${count} ${count === 1 ? 'occurrence' : 'occurrences'}`;
    const entriesWord = (count: number): string => `${count} ${count === 1 ? 'entry' : 'entries'}`;
    const detail = {
      topic_merged: `${label} was withdrawn: its topic was merged into another, so its evidence now counts under the merged name.`,
      no_longer_confirmed: `${label} was withdrawn: entries still mention it, but none of them carries a feeling you confirmed.`,
      // [E-1d, #109] Deliberately never says "unconfirmed" or "missing" — the feeling is confirmed;
      // what is missing is a confirmed link between this exact topic and this exact feeling on
      // those entries. `excludedUnpaired` is the top-level, diary-wide count (`InsightsOut`'s own
      // field), not a number scoped to this one pair — the same number `no_longer_confirmed` and
      // `below_threshold` above do not cite, because unlike them this reason is a diary-wide event
      // (one engine change reclassifying many pairs at once), not a fact about this pair alone.
      excluded_unpaired: `${label} was withdrawn: its entries carry a feeling you confirmed, but never a confirmed pairing between the two — ${entriesWord(excludedUnpaired)} diary-wide are excluded from counting until they are paired.`,
      below_lift: `${label} was withdrawn: still ${occurrences(newCount)}, but the association is no longer stronger than your usual rate by the minimum of ${MIN_LIFT}×.`,
      below_threshold: `${label} was withdrawn: ${occurrences(previousCount)}, now ${newCount} — below the minimum of ${MIN_OCCURRENCE_THRESHOLD}.`,
    }[reason];

    handle
      .prepare(
        `INSERT INTO pattern_withdrawals (id, user_id, pattern_key, topic_id, topic_name,
         feeling_key, kind, previous_count, new_count, reason, detail_text, withdrawn_at,
         superseded_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)`,
      )
      .run(
        randomUUID(),
        userId,
        key,
        pattern.topic_id,
        topicName ?? '(merged)',
        pattern.feeling_key,
        pattern.kind,
        previousCount,
        newCount,
        reason,
        detail,
        now,
      );
  }

  /**
   * What the pattern counts *now*, inside the window — the "3 → 2" the notice states.
   *
   * Using the forward count for both kinds would make every inverse withdrawal report zero, which
   * is true of a pair the user was never shown and false of the one that went away.
   */
  private currentWindowCount(
    userId: string,
    topicId: string,
    feelingKey: string,
    today: PlainDate,
    kind: PatternKind,
  ): number {
    const placeholders = CONFIRMED_FEELING_SOURCES.map(() => '?').join(', ');
    // The side matters. A forward pattern counts entries that mention the topic and carry the
    // feeling; an inverse one counts entries that carry the feeling and do *not* mention it.
    const membership = kind === 'inverse' ? 'NOT IN' : 'IN';
    const rows = this.db
      .forUser(userId)
      .prepare(
        `SELECT e.entry_date FROM diary_entries e
         JOIN entry_feelings ef ON ef.entry_id = e.id
         WHERE e.user_id = ? AND ef.feeling_key = ? AND e.feeling_source IN (${placeholders})
           AND e.id ${membership} (
             SELECT entry_id FROM entry_topics WHERE user_id = ? AND topic_id = ?
           )`,
      )
      .all(userId, feelingKey, ...CONFIRMED_FEELING_SOURCES, userId, topicId) as Array<{
      entry_date: string;
    }>;
    return rows.filter((row) =>
      withinWindow(decodeDate(row.entry_date), today, RECENCY_WINDOW_DAYS),
    ).length;
  }

  /** A2-06: a notice board, not an archive. Superseded notices go first, then the oldest. */
  private pruneWithdrawals(userId: string): void {
    this.db
      .forUser(userId)
      .prepare(
        `DELETE FROM pattern_withdrawals WHERE user_id = ? AND id NOT IN (
           SELECT id FROM pattern_withdrawals WHERE user_id = ?
           ORDER BY (superseded_at IS NOT NULL), withdrawn_at DESC, id
           LIMIT ?
         )`,
      )
      .run(userId, userId, MAX_WITHDRAWAL_RECORDS);
  }

  // -------------------------------------------------------------------------------------------
  // Reading
  // -------------------------------------------------------------------------------------------

  /**
   * How many topic×feeling patterns are currently stored — #37 (L-2)'s gate for the insight
   * progress surface ("hide once the diary has ≥3 surfaced patterns").
   *
   * A row count on `patterns`, not `listPatterns().length`: this is asked from the save path
   * (`ProgressService`, alongside the echo), where paying for `listPatterns()`'s narrative text,
   * confounder decoding and recommendation pass just to throw away everything but a number would be
   * exactly the kind of engine work `EchoService`'s doc comment already rules out for that path. Both
   * `active` and `historical` rows count — a pattern that already surfaced once and later went
   * quiet is still a pattern this diary has found, and the progress surface's job ends the moment
   * the cold start does, not the moment every pattern happens to be in-window. Context patterns
   * (#21) are deliberately not part of this count: they are never persisted (see `ContextPatternOut`'s
   * doc comment), and the progress surface is specifically about the topic×feeling pairs a saved
   * entry can move — a context factor is a fact about the calendar, not something an entry "gets
   * closer to" by being written.
   */
  surfacedPatternCount(userId: string): number {
    return (
      this.db
        .forUser(userId)
        .prepare('SELECT COUNT(*) AS n FROM patterns WHERE user_id = ?')
        .get(userId) as { n: number }
    ).n;
  }

  /**
   * M-3 (#48): how many days ago the diary's very first entry was written, `null` on an empty
   * diary. Added for the mobile locked state (issue task 2): a free reader's `GET /insights` never
   * returns a `'historical'` pattern (`listPatterns` above), which is deliberate — but it leaves the
   * client with no honest number to put in a locked card ("Patterns across your full 14 months —
   * Premium"). The issue is explicit that this must be a *real* number, not an invented one, and
   * this is the smallest true fact available: not a pattern count (that would leak how many
   * patterns exist behind the paywall, which is exactly the content this ticket hides) and not a
   * pattern's own `lifetime_count` (that describes one pair, not the diary). A plain date range
   * over every entry the user wrote is neither — the diary's date span is the same fact
   * `GET /entries` already lets a free reader discover for themselves one day at a time, so
   * surfacing it as one number here reveals nothing a free account could not already see.
   *
   * Deliberately every entry (`diary_entries`, unfiltered by `feeling_source`), not only confirmed
   * evidence (`CONFIRMED_FEELING_SOURCES`) — this answers "how long have you been journaling", a
   * fact about the diary, not "how much evidence exists", a fact about the engine that the rest of
   * this file is careful to keep separate (see `loadEvidenceEntries`'s own doc comment).
   *
   * Tier-independent on purpose (`InsightsController#get` calls this unconditionally): the fact
   * itself is never gated, only the pattern content the locked state's copy refers to.
   */
  historySpanDays(userId: string): number | null {
    const row = this.db
      .forUser(userId)
      .prepare('SELECT MIN(entry_date) AS earliest FROM diary_entries WHERE user_id = ?')
      .get(userId) as {
      earliest: string | null;
    };
    if (!row.earliest) return null;
    return daysBetween(decodeDate(row.earliest), todayLocal());
  }

  /**
   * M-3 (#48): `windowDays` is the free/paid boundary, applied here rather than in
   * `recomputePatterns`/`storeCandidates`. Those two still compute and store exactly one pattern
   * set, using the engine's own fixed `RECENCY_WINDOW_DAYS` (I3-03's split of `lifetimeCounts`
   * deciding existence from a windowed count deciding activity) — that split is the engine's
   * ground truth about the diary and does not change with who is asking. What changes by tier is
   * only which rows of that one stored set a response is allowed to carry: free serves the
   * already-computed `status === 'active'` rows only (the recency machinery's own 30-day
   * definition of "active" — see `constants.ts`), premium (`windowDays === null`) serves
   * everything, including `'historical'` rows, which is "full-history patterns" (the issue's
   * phrase) in practice: today's behaviour, unchanged, for every caller before this ticket.
   *
   * `windowDays` is deliberately not threaded into a fresh recompute of "is this pattern active at
   * some *other* window" — a value other than `RECENCY_WINDOW_DAYS` or `null` would silently lie,
   * since `status` was fixed at write time against the one constant. The only two values any
   * caller passes today are those two (`InsightsController#get`), which is exactly the free/paid
   * boundary this ticket draws.
   *
   * Defaults to `null` (no restriction), not `RECENCY_WINDOW_DAYS` — every caller that predates
   * this ticket (`ExperimentsService`, `DigestService`, `EchoService`) reads the full lifetime list
   * for its own, unrelated purpose (matching a named pattern, picking a digest candidate, matching
   * an echo) and must keep doing so unchanged; only `InsightsController`, the one place tier is
   * actually known, ever passes an explicit value. A default of `RECENCY_WINDOW_DAYS` here would
   * have silently narrowed all three the moment this parameter was added, with no call site
   * telling a reader that was happening.
   */
  listPatterns(userId: string, windowDays: number | null = null): PatternOut[] {
    const rows = this.db
      .forUser(userId)
      .prepare(
        `SELECT p.id, t.name AS topic, p.feeling_key, p.occurrence_count,
                p.narrative_text, p.suggestion_text, p.last_updated_at, p.kind, p.lifetime_count,
                p.status, p.last_occurrence_date, p.present_count, p.present_total, p.absent_count,
                p.absent_total, p.lift, p.comparison_reason, p.base_rate, p.is_strong, p.confounders,
                f.valence
         FROM patterns p
         JOIN topics t ON t.id = p.topic_id
         JOIN feelings f ON f.key = p.feeling_key
         WHERE p.user_id = ?`,
      )
      .all(userId) as Array<Record<string, unknown>>;

    const today = todayLocal();
    const evidence = this.evidenceByPattern(userId);

    const patterns = rows.map((r): PatternOut => {
      const presentTotal = Number(r.present_total);
      const absentTotal = Number(r.absent_total);
      const presentCount = Number(r.present_count);
      const absentCount = Number(r.absent_count);
      const kind = String(r.kind) as PatternKind;
      const topic = String(r.topic);
      const lastOccurrence = r.last_occurrence_date
        ? decodeDate(String(r.last_occurrence_date))
        : null;
      const daysSince = lastOccurrence ? daysBetween(lastOccurrence, today) : null;
      const status = String(r.status) as PatternStatus;
      // Read once and reused below: the badge (P0-6) and the card's own "LIFT —" figure must be
      // the same fact, so there is exactly one place that decides what a stored `NULL` becomes.
      const lift = r.lift === null || r.lift === undefined ? null : Number(r.lift);

      return {
        id: String(r.id),
        kind,
        topic,
        feeling: String(r.feeling_key),
        occurrence_count: Number(r.occurrence_count),
        lifetime_count: Number(r.lifetime_count),
        status,
        // Computed fresh from kind + valence + lift on every read, not echoed from the persisted
        // `direction` column — that column is a different, two-valued concept (see
        // `directionFor`'s doc comment) and re-serving it here is the exact bug P0-2 fixed. P0-6
        // adds `lift` to the inputs so a card whose ratio is undefined or too weak never carries
        // advice it cannot back with a number.
        direction: badgeDirectionFor(kind, String(r.valence), lift),
        narrative_text: String(r.narrative_text),
        suggestion_text: String(r.suggestion_text),
        present_count: presentCount,
        present_total: presentTotal,
        absent_count: absentCount,
        absent_total: absentTotal,
        present_rate: presentTotal > 0 ? presentCount / presentTotal : null,
        absent_rate: absentTotal > 0 ? absentCount / absentTotal : null,
        base_rate: Number(r.base_rate),
        lift,
        comparison_reason: r.comparison_reason === null ? null : String(r.comparison_reason),
        comparison_note: comparisonNoteFor(
          r.comparison_reason === null ? null : String(r.comparison_reason),
          topic,
          kind,
        ),
        is_strong: Boolean(Number(r.is_strong)),
        last_occurrence_date: lastOccurrence ? serializeDate(lastOccurrence) : null,
        days_since_last_occurrence: daysSince,
        historical_note:
          status === 'historical' && daysSince !== null
            ? historicalNote(Number(r.lifetime_count), daysSince)
            : null,
        confounders: decodeJson<ConfounderSplit[]>(String(r.confounders ?? '[]')).map((split) => ({
          topic: split.topic,
          co_occurrence_rate: split.coOccurrenceRate,
          both_count: split.bothCount,
          only_this_count: split.onlyThisCount,
          only_other_count: split.onlyOtherCount,
          neither_count: split.neitherCount,
          inseparable: split.inseparable,
          note: split.note,
        })),
        evidence: evidence.get(String(r.id)) ?? [],
        last_updated_at: serializeDateTime(decodeDateTime(String(r.last_updated_at))),
        // Filled in below, for the handful of patterns that qualify — never persisted (task 4):
        // computed fresh from this same row on every read, so a pattern that withdraws takes its
        // recommendation with it with no separate cleanup step.
        recommendation: null,
      };
    });

    this.attachRecommendations(patterns);

    // Active first, then strongest, then most evidence — and `id` last, always. Patterns written
    // in one recompute share a timestamp to the microsecond, and any sort without a total order
    // lets the two clients render the same data in different orders (C-02).
    patterns.sort(
      (a, b) =>
        Number(a.status === 'historical') - Number(b.status === 'historical') ||
        (b.lift ?? 0) - (a.lift ?? 0) ||
        b.occurrence_count - a.occurrence_count ||
        (a.id < b.id ? -1 : a.id > b.id ? 1 : 0),
    );

    // M-3: `attachRecommendations` runs over the full set first (so a recommendation is never
    // decided by which rows a free reader happens to be allowed), then the free-tier cut removes
    // historical rows from what is actually returned.
    if (windowDays === null) return patterns;
    return patterns.filter((pattern) => pattern.status === 'active');
  }

  /**
   * R-1: mutate the top `MAX_RECOMMENDATIONS` qualifying patterns in place, attaching the "Worth
   * trying" card each one earns.
   *
   * "Qualifying" is deliberately not a second rule re-derived here: a pattern qualifies exactly
   * when its own `direction` — already decided by `badgeDirectionFor` a few lines above, the one
   * place P0-2/P0-6 make that call — reads `'keep'`. That is precisely the issue's two cases at
   * once: an inverse pattern whose feeling is negative (the topic's absence coincides with feeling
   * bad, so the topic is protective) and a forward pattern whose feeling is positive (the topic
   * coincides with feeling good, so it is worth continuing) — see `badgeDirectionFor`'s doc comment
   * for why those are not mirrors of each other. `'keep'` also guarantees `lift` is a defined number
   * at or above `MIN_LIFT` (P0-6's early return), which is what makes it safe to hand to
   * `recommendationSentenceFor` — a function that takes `lift: number`, not `number | null`, because
   * a caller that got here with an undefined lift already has a bug.
   *
   * Ranked and capped with the exact same tiebreak `buildCandidates` uses for the inverse-pattern
   * cap (C-02): lift first, then window count, then topic name + feeling — never `id`, which carries
   * a random UUID that would make two clients disagree about which three patterns are "the" top
   * three on the same diary.
   */
  private attachRecommendations(patterns: PatternOut[]): void {
    const qualifying = patterns.filter(
      (pattern): pattern is PatternOut & { kind: 'forward' | 'inverse'; lift: number } =>
        pattern.direction === 'keep' &&
        (pattern.kind === 'forward' || pattern.kind === 'inverse') &&
        pattern.lift !== null,
    );
    qualifying.sort(
      (a, b) =>
        b.lift - a.lift ||
        b.occurrence_count - a.occurrence_count ||
        `${a.topic} ${a.feeling}`.localeCompare(`${b.topic} ${b.feeling}`),
    );
    for (const pattern of qualifying.slice(0, MAX_RECOMMENDATIONS)) {
      pattern.recommendation = {
        action_topic: pattern.topic,
        headline: recommendationHeadlineFor(pattern.kind, pattern.topic),
        sentence: recommendationSentenceFor(
          pattern.kind,
          pattern.feeling,
          pattern.topic,
          pattern.lift,
          pattern.present_count,
          pattern.present_total,
          pattern.absent_count,
          pattern.absent_total,
        ),
        pattern_ref: pattern.id,
      };
    }
  }

  /**
   * The evidence trail, read straight out of `pattern_entries` (A1-08).
   *
   * Loaded for every pattern in one pass rather than per card: the alternative is a query per
   * pattern per read, and Insights recomputes on every open.
   */
  private evidenceByPattern(userId: string): Map<string, EvidenceOut[]> {
    const handle = this.db.forUser(userId);
    const rows = handle
      .prepare(
        `SELECT pe.pattern_id, e.id, e.entry_date, e.raw_text, e.feeling_source
         FROM pattern_entries pe JOIN diary_entries e ON e.id = pe.entry_id
         WHERE pe.user_id = ?
         ORDER BY e.entry_date, e.id`,
      )
      .all(userId) as Array<{
      pattern_id: string;
      id: string;
      entry_date: string;
      raw_text: string;
      feeling_source: string;
    }>;

    const feelingsByEntry = new Map<string, string[]>();
    for (const row of handle
      .prepare(
        'SELECT entry_id, feeling_key FROM entry_feelings WHERE user_id = ? ORDER BY entry_id, position',
      )
      .all(userId) as Array<{ entry_id: string; feeling_key: string }>) {
      if (!feelingsByEntry.has(row.entry_id)) feelingsByEntry.set(row.entry_id, []);
      feelingsByEntry.get(row.entry_id)!.push(row.feeling_key);
    }

    const byPattern = new Map<string, EvidenceOut[]>();
    for (const row of rows) {
      if (!byPattern.has(row.pattern_id)) byPattern.set(row.pattern_id, []);
      byPattern.get(row.pattern_id)!.push({
        entry_id: row.id,
        entry_date: serializeDate(decodeDate(row.entry_date)),
        raw_text: row.raw_text,
        feeling_keys: feelingsByEntry.get(row.id) ?? [],
        feeling_source: row.feeling_source,
      });
    }
    return byPattern;
  }

  /**
   * Withdrawal notices, newest first, with the ones the user has not acknowledged marked (A2-07).
   *
   * Superseded notices are not returned at all: the pattern is active again, and showing both
   * states of the same pattern at once is precisely what A2-05 forbids.
   *
   * The ordering is a total one on the pattern's *identity*, not on its id: every withdrawal in a
   * single recompute shares a timestamp to the microsecond, and breaking that tie on a random UUID
   * put the same notices in a different order on each client (C-02).
   */
  listWithdrawals(userId: string): WithdrawalOut[] {
    const lastSeen = this.readMeta(userId, 'withdrawals_acknowledged_at');
    return (
      this.db
        .forUser(userId)
        .prepare(
          `SELECT id, topic_name, feeling_key, kind, previous_count, new_count, reason, detail_text,
                  withdrawn_at
           FROM pattern_withdrawals WHERE user_id = ? AND superseded_at IS NULL
           ORDER BY withdrawn_at DESC, topic_name, feeling_key, kind, id`,
        )
        .all(userId) as Array<Record<string, unknown>>
    ).map((r) => {
      const withdrawnAt = String(r.withdrawn_at);
      return {
        id: String(r.id),
        topic: String(r.topic_name),
        feeling: String(r.feeling_key),
        kind: String(r.kind) as PatternKind,
        previous_count: Number(r.previous_count),
        new_count: Number(r.new_count),
        reason: String(r.reason) as WithdrawalReason,
        detail_text: String(r.detail_text),
        withdrawn_at: serializeDateTime(decodeDateTime(withdrawnAt)),
        // String comparison is safe and exact here: stored datetimes are fixed-width and
        // zero-padded, so lexical order is chronological order.
        is_new: lastSeen === null || withdrawnAt > lastSeen,
      };
    });
  }

  /**
   * Mark the current withdrawal notices as seen.
   *
   * Deliberately an explicit action rather than a side effect of reading Insights. If opening the
   * screen cleared the flag, whichever client opened it first would clear it for the other, and
   * the two would show different numbers for the same diary (C-02).
   */
  acknowledgeWithdrawals(userId: string): void {
    this.writeMeta(userId, 'withdrawals_acknowledged_at', encodeDateTime(nowUtc()));
  }

  private readMeta(userId: string, key: string): string | null {
    const row = this.db
      .forUser(userId)
      .prepare('SELECT value FROM diary_meta WHERE user_id = ? AND "key" = ?')
      .get(userId, key) as { value: string } | undefined;
    return row?.value ?? null;
  }

  private writeMeta(userId: string, key: string, value: string): void {
    const handle = this.db.forUser(userId);
    const updated = handle
      .prepare('UPDATE diary_meta SET value = ? WHERE user_id = ? AND "key" = ?')
      .run(value, userId, key);
    if (updated.changes === 0) {
      handle
        .prepare('INSERT INTO diary_meta (user_id, "key", value) VALUES (?, ?, ?)')
        .run(userId, key, value);
    }
  }
}
