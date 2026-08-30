import { Inject, Injectable } from '@nestjs/common';
import { SCOPED_DB, type ScopedDb } from '../db/scoped-db';
import { isMixedValence, isPairExcluded } from './analysis';
import {
  CONFIRMED_FEELING_SOURCES,
  MIN_OCCURRENCE_THRESHOLD,
  SURFACED_PATTERN_GATE,
} from './constants';
import { TopicsService } from '../topics/topics.service';
import { PatternsService } from './patterns.service';

/**
 * The insight progress surface (#37, L-2): near-threshold counts for the "Entry saved" screen.
 *
 * Between day one and the first surfaced pattern the app has nothing to say — the empty period
 * where diary apps die. This is the counting made visible during that gap, honest about being
 * unfinished: not a pattern, not a prediction, just "2 of 3" for a pair this entry is building
 * toward. It sits beside `EchoService` and inherits its three governing properties, because a
 * near-threshold count is exactly as easy to get wrong as a surfaced one:
 *
 *  - **After, never during.** Served for a *stored* entry, same as the echo (I4-02).
 *  - **Observation only.** Counts only — no prediction, no advice, and nothing about how today's
 *    entry compares to the pattern once it forms. §11.6 rung 2 draws that line explicitly.
 *  - **It reads; it never recomputes.** No topic re-extraction, no writes, no confounder pass, no
 *    lift. Every number below comes from tables the last `GET /insights` already wrote to plus one
 *    read-only pass over the entry in hand — the same budget `EchoService.forEntry` already spends.
 *
 * The counting rule is #26/E-1b's: a mixed-valence entry only counts toward the topic×feeling pairs
 * it explicitly confirmed. `isPairExcluded` (extracted from `PatternsService#buildCandidates` into
 * `analysis.ts` for exactly this reuse) is applied identically here, so "2 of 3" here and the "3 of
 * 3" the engine would eventually report for the same pair are never allowed to disagree — the
 * dishonesty this feature would otherwise risk is promising a pattern that never arrives because the
 * count it quoted was never one the engine would actually reach.
 *
 * Staleness note: `entry_topics` (read below for every *other* entry's contribution) is written by
 * `PatternsService#loadEvidenceEntries` during the last `recomputePatterns()` call, not on save — a
 * brand-new diary with no recompute yet has no rows there at all, and any entry saved since the last
 * `GET /insights` is invisible to it. This is the identical staleness `EchoService` already accepts
 * (see its own doc comment) and `matchExistingTopics` already works around for the *current* entry;
 * `topicsTracked` below applies the same one-entry patch for the global counter.
 */

/** One topic×feeling pair this entry moved, still short of `MIN_OCCURRENCE_THRESHOLD`. */
export interface ProgressPairOut {
  topic: string;
  feeling: string;
  occurrences: number;
  /** Echoed from `engineConstants().min_occurrence_threshold` rather than left for the client to
   *  know — `mobile/CLAUDE.md`'s one rule: the backend owns every number a client would otherwise
   *  have to hardcode (see `constants.ts`'s module doc comment). */
  threshold: number;
}

export interface ProgressOut {
  topics_tracked: number;
  confirmed_entries: number;
  /**
   * Deterministic selection, nearest-to-threshold first: the top two `(topic, feeling)` pairs this
   * entry actually moved, ties broken by topic name then feeling key so two clients reading the same
   * diary never render the pairs in a different order (C-02). Empty is the normal answer for an
   * entry that touched nothing near a threshold — the mobile client renders no "closest to a
   * pattern" line for an empty list, same as `EchoService`'s "empty is not a failure" (I4-09).
   */
  pairs: ProgressPairOut[];
  /** #37 task 3's gate: `PatternsService#surfacedPatternCount()`, unchanged — see that method's doc
   *  comment for what it counts and why context patterns are excluded from it. Sent even once the
   *  gate has already tripped (see `surfaced_pattern_gate` below), because the acceptance criteria
   *  ask the *client* to evaluate both gates ("data present" and "< surfaced_pattern_gate") rather
   *  than trust a single precomputed boolean — the same "don't hand a client a threshold it cannot
   *  see" reasoning as `ProgressPairOut.threshold`, just for a different number. */
  surfaced_pattern_count: number;
  /** `SURFACED_PATTERN_GATE`, echoed for the same reason `ProgressPairOut.threshold` echoes
   *  `MIN_OCCURRENCE_THRESHOLD`: a number a client would otherwise have to hardcode to interpret
   *  `surfaced_pattern_count` against (`mobile/CLAUDE.md`'s one rule). */
  surfaced_pattern_gate: number;
}

@Injectable()
export class ProgressService {
  constructor(
    @Inject(SCOPED_DB) private readonly db: ScopedDb,
    private readonly patterns: PatternsService,
    private readonly topics: TopicsService,
  ) {}

  /** The progress surface for one just-saved entry, or `null` if the entry does not exist. */
  forEntry(userId: string, entryId: string): ProgressOut | null {
    const handle = this.db.forUser(userId);
    const entry = handle
      .prepare('SELECT id, raw_text, feeling_source FROM diary_entries WHERE id = ? AND user_id = ?')
      .get(entryId, userId) as { id: string; raw_text: string; feeling_source: string } | undefined;
    if (!entry) return null;

    const confirmedPlaceholders = CONFIRMED_FEELING_SOURCES.map(() => '?').join(', ');
    const confirmedEntries = (
      handle
        .prepare(
          `SELECT COUNT(*) AS n FROM diary_entries
           WHERE user_id = ? AND feeling_source IN (${confirmedPlaceholders})`,
        )
        .get(userId, ...CONFIRMED_FEELING_SOURCES) as { n: number }
    ).n;
    const surfacedPatternCount = this.patterns.surfacedPatternCount(userId);

    // I4-01's same union: `topicsForEntry` for links a prior recompute already wrote, plus the
    // read-only `matchExistingTopics` fallback for an entry that has not been through one yet. No
    // write happens on either side of this union (`extractAndLinkTopics` is never called here).
    const topicNameById = new Map<string, string>();
    for (const topic of [
      ...this.topics.topicsForEntry(userId, entryId),
      ...this.topics.matchExistingTopics(userId, entry.raw_text),
    ]) {
      topicNameById.set(topic.id, topic.name);
    }
    const entryTopicIds = [...topicNameById.keys()];

    // Global counter: `entry_topics` union this entry's own topics, so the diary's own most recent
    // save is never missing from a number shown on its own confirmation screen (see the module doc
    // comment's staleness note).
    const isConfirmedSource = CONFIRMED_FEELING_SOURCES.includes(entry.feeling_source);
    const trackedTopicIds = new Set(
      (
        handle
          .prepare(
            `SELECT DISTINCT et.topic_id FROM entry_topics et
             JOIN diary_entries e ON e.id = et.entry_id
             WHERE et.user_id = ? AND e.feeling_source IN (${confirmedPlaceholders})`,
          )
          .all(userId, ...CONFIRMED_FEELING_SOURCES) as Array<{ topic_id: string }>
      ).map((row) => row.topic_id),
    );
    if (isConfirmedSource) for (const topicId of entryTopicIds) trackedTopicIds.add(topicId);
    const topicsTracked = trackedTopicIds.size;

    const withoutPairs: ProgressOut = {
      topics_tracked: topicsTracked,
      confirmed_entries: confirmedEntries,
      pairs: [],
      surfaced_pattern_count: surfacedPatternCount,
      surfaced_pattern_gate: SURFACED_PATTERN_GATE,
    };

    // #37 task 3: once the diary already has ≥3 surfaced patterns, the cold-start job this surface
    // exists for is over and the mobile client hides the whole section — so the (more expensive)
    // pair counting below is skipped, same as every other early return here. `surfaced_pattern_count`
    // is still reported honestly rather than hidden or clamped: the acceptance criteria ask the
    // client itself to compare it against `surfaced_pattern_gate`, not to trust a boolean this file
    // decided on its behalf (see `surfaced_pattern_count`'s doc comment on `ProgressOut`).
    if (surfacedPatternCount >= SURFACED_PATTERN_GATE) return withoutPairs;
    if (entryTopicIds.length === 0 || !isConfirmedSource) return withoutPairs;

    const entryFeelingKeys = (
      handle
        .prepare('SELECT feeling_key FROM entry_feelings WHERE user_id = ? AND entry_id = ?')
        .all(userId, entryId) as Array<{ feeling_key: string }>
    ).map((row) => row.feeling_key);
    if (entryFeelingKeys.length === 0) return withoutPairs;

    const valenceOf = new Map(
      (
        handle.prepare('SELECT "key", valence FROM feelings').all() as Array<{
          key: string;
          valence: string;
        }>
      ).map((row) => [row.key, row.valence]),
    );
    const entryIsMixed = isMixedValence(entryFeelingKeys, (key) => valenceOf.get(key));
    const entryConfirmedPairs = new Set(
      (
        handle
          .prepare(
            `SELECT topic_id, feeling_key FROM entry_topic_feelings
             WHERE user_id = ? AND entry_id = ? AND source IN (${confirmedPlaceholders})`,
          )
          .all(userId, entryId, ...CONFIRMED_FEELING_SOURCES) as Array<{
          topic_id: string;
          feeling_key: string;
        }>
      ).map((row) => `${row.topic_id} ${row.feeling_key}`),
    );

    // The pairs this save actually moved: its own topics crossed with its own confirmed feelings,
    // minus any pair #26 excludes it from — an excluded pair is one this entry did not contribute an
    // occurrence to, so it is not "moving" from this entry's point of view even if it happens to sit
    // just under the threshold from other entries alone.
    const touchedKeys: string[] = [];
    for (const topicId of entryTopicIds) {
      for (const feelingKey of entryFeelingKeys) {
        if (!isPairExcluded(entryIsMixed, entryConfirmedPairs, topicId, feelingKey)) {
          touchedKeys.push(`${topicId} ${feelingKey}`);
        }
      }
    }
    if (touchedKeys.length === 0) return withoutPairs;

    // Seed with this entry's own contribution — the one occurrence `entry_topics` cannot yet know
    // about if this save has never been through a recompute.
    const lifetimeCounts = new Map<string, number>(touchedKeys.map((key) => [key, 1]));

    const topicPlaceholders = entryTopicIds.map(() => '?').join(', ');
    const otherEntryIds = (
      handle
        .prepare(
          `SELECT DISTINCT et.entry_id AS id FROM entry_topics et
           JOIN diary_entries e ON e.id = et.entry_id
           WHERE et.user_id = ? AND et.topic_id IN (${topicPlaceholders})
             AND e.feeling_source IN (${confirmedPlaceholders})
             AND et.entry_id != ?`,
        )
        .all(userId, ...entryTopicIds, ...CONFIRMED_FEELING_SOURCES, entryId) as Array<{
        id: string;
      }>
    ).map((row) => row.id);

    if (otherEntryIds.length > 0) {
      const idPlaceholders = otherEntryIds.map(() => '?').join(', ');

      const topicsByEntry = new Map<string, Set<string>>();
      for (const row of handle
        .prepare(
          `SELECT entry_id, topic_id FROM entry_topics
           WHERE user_id = ? AND entry_id IN (${idPlaceholders}) AND topic_id IN (${topicPlaceholders})`,
        )
        .all(userId, ...otherEntryIds, ...entryTopicIds) as Array<{
        entry_id: string;
        topic_id: string;
      }>) {
        if (!topicsByEntry.has(row.entry_id)) topicsByEntry.set(row.entry_id, new Set());
        topicsByEntry.get(row.entry_id)!.add(row.topic_id);
      }

      const feelingsByEntry = new Map<string, string[]>();
      for (const row of handle
        .prepare(
          `SELECT entry_id, feeling_key FROM entry_feelings
           WHERE user_id = ? AND entry_id IN (${idPlaceholders})`,
        )
        .all(userId, ...otherEntryIds) as Array<{ entry_id: string; feeling_key: string }>) {
        if (!feelingsByEntry.has(row.entry_id)) feelingsByEntry.set(row.entry_id, []);
        feelingsByEntry.get(row.entry_id)!.push(row.feeling_key);
      }

      const confirmedPairsByEntry = new Map<string, Set<string>>();
      for (const row of handle
        .prepare(
          `SELECT entry_id, topic_id, feeling_key FROM entry_topic_feelings
           WHERE user_id = ? AND entry_id IN (${idPlaceholders}) AND source IN (${confirmedPlaceholders})`,
        )
        .all(userId, ...otherEntryIds, ...CONFIRMED_FEELING_SOURCES) as Array<{
        entry_id: string;
        topic_id: string;
        feeling_key: string;
      }>) {
        if (!confirmedPairsByEntry.has(row.entry_id))
          confirmedPairsByEntry.set(row.entry_id, new Set());
        confirmedPairsByEntry.get(row.entry_id)!.add(`${row.topic_id} ${row.feeling_key}`);
      }

      const touched = new Set(touchedKeys);
      for (const [otherId, topicIds] of topicsByEntry) {
        const feelingKeys = feelingsByEntry.get(otherId) ?? [];
        const isMixed = isMixedValence(feelingKeys, (key) => valenceOf.get(key));
        const confirmedPairs = confirmedPairsByEntry.get(otherId) ?? new Set<string>();
        for (const topicId of topicIds) {
          for (const feelingKey of feelingKeys) {
            const key = `${topicId} ${feelingKey}`;
            if (!touched.has(key)) continue;
            if (isPairExcluded(isMixed, confirmedPairs, topicId, feelingKey)) continue;
            lifetimeCounts.set(key, (lifetimeCounts.get(key) ?? 0) + 1);
          }
        }
      }
    }

    const pairs: ProgressPairOut[] = [];
    for (const key of touchedKeys) {
      const occurrences = lifetimeCounts.get(key) ?? 0;
      // Reached (or somehow exceeded) the threshold: no longer "below" anything, and — once the next
      // `GET /insights` runs — a pattern in its own right, which `EchoService` will pick up from
      // then on. Not this file's job to say so a moment early off a count `patterns` has not stored
      // yet (see the module doc comment's staleness note).
      if (occurrences >= MIN_OCCURRENCE_THRESHOLD) continue;
      const [topicId, feelingKey] = key.split(' ');
      pairs.push({
        topic: topicNameById.get(topicId) ?? topicId,
        feeling: feelingKey,
        occurrences,
        threshold: MIN_OCCURRENCE_THRESHOLD,
      });
    }

    pairs.sort(
      (a, b) =>
        b.occurrences - a.occurrences ||
        a.topic.localeCompare(b.topic) ||
        a.feeling.localeCompare(b.feeling),
    );

    return {
      topics_tracked: topicsTracked,
      confirmed_entries: confirmedEntries,
      pairs: pairs.slice(0, 2),
      surfaced_pattern_count: surfacedPatternCount,
      surfaced_pattern_gate: SURFACED_PATTERN_GATE,
    };
  }
}
