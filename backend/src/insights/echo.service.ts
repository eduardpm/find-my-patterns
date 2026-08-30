import { Inject, Injectable } from '@nestjs/common';
import { decodeJson, encodeDate, encodeJson, todayLocal } from '../db/codecs';
import { SCOPED_DB, type ScopedDb } from '../db/scoped-db';
import { isMixedValence } from './analysis';
import { CONFIRMED_FEELING_SOURCES } from './constants';
import { TopicsService } from '../topics/topics.service';
import { PatternsService } from './patterns.service';

/**
 * The pattern echo (I4): what the diary already says about what was just written.
 *
 * Three properties do all the work, and each is a restriction rather than a feature:
 *
 *  - **After, never during.** The echo is served for a *stored* entry, so there is no request the
 *    composer could make that would put a statistic in front of someone mid-sentence. An app that
 *    told you "you usually feel anxious about meetings" while you were still describing the meeting
 *    would be shaping the evidence it then counts (I4-02).
 *  - **Observation only.** The numbers are the pattern card's own numbers, unchanged. Nothing here
 *    predicts, advises, or says anything about how the user feels today (I4-03).
 *  - **It reads; it never recomputes.** Recomputation stays on `GET /insights` (C-06), so saving an
 *    entry never pays for the engine.
 */

export interface EchoOut {
  pattern_id: string;
  topic: string;
  feeling: string;
  kind: string;
  status: string;
  occurrence_count: number;
  present_count: number;
  present_total: number;
  lift: number | null;
  /** The pattern's own sentence, verbatim — the echo states nothing the card does not. */
  narrative_text: string;
}

const ECHO_LOG_KEY = 'pattern_echo_log';

@Injectable()
export class EchoService {
  constructor(
    @Inject(SCOPED_DB) private readonly db: ScopedDb,
    private readonly patterns: PatternsService,
    private readonly topics: TopicsService,
  ) {}

  /**
   * The echoes for one saved entry.
   *
   * Empty is the normal answer, not a failure: an entry whose topics carry no active pattern gets
   * nothing at all, because inventing a "maybe this matters" line would be the app talking rather
   * than the diary (I4-09).
   */
  forEntry(userId: string, entryId: string): EchoOut[] {
    const handle = this.db.forUser(userId);
    const entry = handle
      .prepare(
        'SELECT id, entry_date, raw_text, feeling_source FROM diary_entries WHERE id = ? AND user_id = ?',
      )
      .get(entryId, userId) as
      { id: string; entry_date: string; raw_text: string; feeling_source: string } | undefined;
    if (!entry) return [];

    // I4-01: the entry's topics are computed here rather than read from `entry_topics`, because
    // those links are written by the recompute and an entry saved a second ago has none yet. The
    // computation is the same deterministic keyword match, minus the writes.
    const topicIds = new Set([
      ...this.topics.topicsForEntry(userId, entryId).map((topic) => topic.id),
      ...this.topics.matchExistingTopics(userId, entry.raw_text).map((topic) => topic.id),
    ]);
    if (topicIds.size === 0) return [];

    const patternTopics = new Map(
      (
        handle.prepare('SELECT p.id, p.topic_id FROM patterns p WHERE p.user_id = ?').all(
          userId,
        ) as Array<{
          id: string;
          topic_id: string;
        }>
      ).map((row) => [row.id, row.topic_id]),
    );

    // E-1b (task 3): the same mixed-valence pairing rule `PatternsService` applies while counting,
    // applied here to the one entry in hand. Read straight off the tables the engine reads, rather
    // than through `PatternsService`, because there is no per-entry query surfaced there to reuse —
    // its counting runs over the whole diary at once, never over one entry (C-06).
    //
    // Feelings are read only when the entry's own feeling assignment is a genuine confirmation
    // (`CONFIRMED_FEELING_SOURCES`, same as everywhere else this rule applies) — an entry whose
    // feelings are still `suggested` or `unset` is not evidence for anything yet, so it has no
    // feeling to test for a mix and the check below never fires for it, unchanged from before.
    const entryFeelingKeys = CONFIRMED_FEELING_SOURCES.includes(entry.feeling_source)
      ? (
          handle
            .prepare('SELECT feeling_key FROM entry_feelings WHERE user_id = ? AND entry_id = ?')
            .all(userId, entryId) as Array<{ feeling_key: string }>
        ).map((row) => row.feeling_key)
      : [];
    const valenceOf = new Map(
      (
        handle.prepare('SELECT "key", valence FROM feelings').all() as Array<{
          key: string;
          valence: string;
        }>
      ).map((row) => [row.key, row.valence]),
    );
    const entryIsMixed = isMixedValence(entryFeelingKeys, (key) => valenceOf.get(key));
    const confirmedPairingPlaceholders = CONFIRMED_FEELING_SOURCES.map(() => '?').join(', ');
    const confirmedPairs = new Set(
      (
        handle
          .prepare(
            `SELECT topic_id, feeling_key FROM entry_topic_feelings
             WHERE user_id = ? AND entry_id = ? AND source IN (${confirmedPairingPlaceholders})`,
          )
          .all(userId, entryId, ...CONFIRMED_FEELING_SOURCES) as Array<{
          topic_id: string;
          feeling_key: string;
        }>
      ).map((row) => `${row.topic_id} ${row.feeling_key}`),
    );

    // I4-05: an echo is only ever an *active* pattern, and only a forward one — "you felt X in 8 of
    // 12 entries mentioning this" is an observation about the entry in hand. An inverse pattern is
    // about the entries that do *not* mention it, so echoing it here would be a non sequitur.
    const matches = this.patterns.listPatterns(userId).filter((pattern) => {
      if (pattern.status !== 'active' || pattern.kind !== 'forward') return false;
      const topicId = patternTopics.get(pattern.id);
      if (!topicId || !topicIds.has(topicId)) return false;
      // E-1b (task 3): the entry is only disqualified from a pattern it itself would not have
      // contributed to — which requires the entry to actually carry the pattern's exact feeling.
      // An entry mentioning the topic under a *different* feeling was never evidence for this pair
      // in the first place, mixed or not, so the rule has nothing to say about it and the echo
      // proceeds exactly as before (this is the general "you usually feel X here" observation,
      // unrelated to what the user felt just now).
      if (entryIsMixed && entryFeelingKeys.includes(pattern.feeling)) {
        return confirmedPairs.has(`${topicId} ${pattern.feeling}`);
      }
      return true;
    });

    const today = encodeDate(todayLocal());
    const log = this.readLog(userId);
    const allowed = matches.filter((pattern) => {
      const seen = log[pattern.id];
      // I4-06: once per pattern per day. Re-reading the same entry's echo is deliberately still
      // allowed — a client that reloads the confirmation screen should not lose what it was shown.
      return !seen || seen.date !== today || seen.entryId === entryId;
    });

    if (allowed.length > 0) {
      for (const pattern of allowed) log[pattern.id] = { date: today, entryId };
      this.writeLog(userId, log, today);
    }

    return allowed.map((pattern) => ({
      pattern_id: pattern.id,
      topic: pattern.topic,
      feeling: pattern.feeling,
      kind: pattern.kind,
      status: pattern.status,
      occurrence_count: pattern.occurrence_count,
      present_count: pattern.present_count,
      present_total: pattern.present_total,
      lift: pattern.lift,
      narrative_text: pattern.narrative_text,
    }));
  }

  private readLog(userId: string): Record<string, { date: string; entryId: string }> {
    const row = this.db
      .forUser(userId)
      .prepare('SELECT value FROM diary_meta WHERE user_id = ? AND "key" = ?')
      .get(userId, ECHO_LOG_KEY) as { value: string } | undefined;
    if (!row) return {};
    try {
      return decodeJson<Record<string, { date: string; entryId: string }>>(row.value);
    } catch {
      // A log that cannot be read is not worth failing a save over. The worst outcome of starting
      // again is one extra echo.
      return {};
    }
  }

  /** Yesterday's entries are dropped on write, so the log stays one day wide. */
  private writeLog(
    userId: string,
    log: Record<string, { date: string; entryId: string }>,
    today: string,
  ): void {
    const pruned = Object.fromEntries(
      Object.entries(log).filter(([, seen]) => seen.date === today),
    );
    const value = encodeJson(pruned);
    const handle = this.db.forUser(userId);
    const updated = handle
      .prepare('UPDATE diary_meta SET value = ? WHERE user_id = ? AND "key" = ?')
      .run(value, userId, ECHO_LOG_KEY);
    if (updated.changes === 0) {
      handle
        .prepare('INSERT INTO diary_meta (user_id, "key", value) VALUES (?, ?, ?)')
        .run(userId, ECHO_LOG_KEY, value);
    }
  }
}
