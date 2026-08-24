import { Inject, Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { decodeDateTime, encodeDateTime, nowUtc, serializeDateTime } from '../db/codecs';
import { DIARY_DB } from '../db/database.provider';
import type { DiaryDatabase } from '../db/database';
import { TopicsService } from '../topics/topics.service';

/**
 * Deterministic pattern detection (spec 002 FR-009/FR-012).
 *
 * Two layers, kept apart exactly as the constitution's "Deterministic Core, LLM at the Edges"
 * requires:
 *
 *  1. `qualifyingPairs` — pure counting. No database, no LLM. This is the whole of the
 *     minimum-occurrence rule (FR-008) and is unit-tested in isolation.
 *  2. `recomputePatterns` — the orchestration that reads real data, applies the rule, and asks the
 *     LLM only how to *phrase* a pattern deterministic code already confirmed.
 */

export const MIN_OCCURRENCE_THRESHOLD = 3;

/** Only a feeling the user acted on is evidence — a mere suggestion is not a fact (FR-012). */
export const CONFIRMED_FEELING_SOURCES = ['confirmed', 'overridden'];

export interface PatternOut {
  id: string;
  topic: string;
  feeling: string;
  occurrence_count: number;
  direction: string;
  narrative_text: string;
  suggestion_text: string;
  last_updated_at: string;
}

/**
 * Pure: count `(topicId, feelingKey)` occurrences and return only those meeting the threshold.
 * Everything else in this file is plumbing around this function.
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
 * FR-011 direction: a positive feeling is worth keeping; anything else prompts a change. Neutral
 * is grouped with "change" because there is no positive signal to reinforce — the spec defines no
 * third bucket.
 */
export function directionForValence(valence: string): 'keep' | 'change' {
  return valence === 'positive' ? 'keep' : 'change';
}

@Injectable()
export class PatternsService {
  constructor(
    @Inject(DIARY_DB) private readonly db: DiaryDatabase,
    private readonly topics: TopicsService,
  ) {}

  async recomputePatterns(): Promise<void> {
    const entries = this.db
      .prepare(
        `SELECT id, raw_text, feeling_key FROM diary_entries
         WHERE feeling_source IN (${CONFIRMED_FEELING_SOURCES.map(() => '?').join(', ')})
           AND feeling_key IS NOT NULL`,
      )
      .all(...CONFIRMED_FEELING_SOURCES) as Array<{
      id: string;
      raw_text: string;
      feeling_key: string;
    }>;

    // Re-scan every eligible entry. Idempotent, so repeated runs are
    // harmless re-confirmation rather than duplication. Keyword links are derived data: remove the
    // previous extraction first so editing "coffee" out of an entry also removes its support from
    // the coffee pattern. Merely inserting newly found links leaves patterns permanently stale.
    for (const entry of entries) {
      this.db
        .prepare("DELETE FROM entry_topics WHERE entry_id = ? AND extracted_by = 'keyword'")
        .run(entry.id);
      this.topics.extractAndLinkTopics(entry.id, entry.raw_text);
    }

    const occurrences: Array<[string, string]> = [];
    const supportingEntryIds = new Map<string, string[]>();
    const topicNames = new Map<string, string>();

    for (const entry of entries) {
      for (const topic of this.topics.topicsForEntry(entry.id)) {
        const key = `${topic.id} ${entry.feeling_key}`;
        occurrences.push([topic.id, entry.feeling_key]);
        if (!supportingEntryIds.has(key)) supportingEntryIds.set(key, []);
        supportingEntryIds.get(key)!.push(entry.id);
        topicNames.set(topic.id, topic.name);
      }
    }

    const qualifying = qualifyingPairs(occurrences);
    const existing = new Map<
      string,
      {
        id: string;
        occurrence_count: number;
        narrative_text: string;
        suggestion_text: string;
        direction: string;
      }
    >();
    for (const row of this.db
      .prepare(
        'SELECT id, topic_id, feeling_key, occurrence_count, narrative_text, suggestion_text, direction FROM patterns',
      )
      .all() as Array<{
      id: string;
      topic_id: string;
      feeling_key: string;
      occurrence_count: number;
      narrative_text: string;
      suggestion_text: string;
      direction: string;
    }>) {
      existing.set(`${row.topic_id} ${row.feeling_key}`, row);
    }

    const seen = new Set<string>();

    for (const [key, count] of qualifying) {
      seen.add(key);
      const [topicId, feelingKey] = key.split(' ');
      const pattern = existing.get(key);

      const needsNarration =
        pattern === undefined ||
        Number(pattern.occurrence_count) !== count ||
        !pattern.narrative_text;

      let narrativeText: string;
      let suggestionText: string;
      if (needsNarration) {
        const topic = topicNames.get(topicId)!;
        narrativeText = `You felt ${feelingKey} in ${count} recent entries mentioning ${topic}.`;
        suggestionText = `Pay attention to how ${topic} affects your ${feelingKey} feeling.`;
      } else {
        narrativeText = pattern.narrative_text;
        suggestionText = pattern.suggestion_text;
      }

      const feeling = this.db
        .prepare('SELECT valence FROM feelings WHERE "key" = ?')
        .get(feelingKey) as { valence: string } | undefined;
      const direction = directionForValence(feeling?.valence ?? 'neutral');

      const isNew = pattern === undefined;
      // Stamped only when the pattern actually changed. An unconditional stamp made this field mean
      // "when insights were last viewed" and made two clients receive different payloads for
      // unchanged data — fixed during feature 003, and the port must not reintroduce it.
      const changed = isNew || needsNarration || pattern!.direction !== direction;
      const now = encodeDateTime(nowUtc());

      let patternId: string;
      if (isNew) {
        patternId = randomUUID();
        this.db
          .prepare(
            `INSERT INTO patterns (id, topic_id, feeling_key, occurrence_count, narrative_text,
             suggestion_text, direction, first_detected_at, last_updated_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          )
          .run(
            patternId,
            topicId,
            feelingKey,
            count,
            narrativeText,
            suggestionText,
            direction,
            now,
            now,
          );
      } else {
        patternId = pattern!.id;
        if (changed) {
          this.db
            .prepare(
              `UPDATE patterns SET occurrence_count = ?, narrative_text = ?, suggestion_text = ?,
               direction = ?, last_updated_at = ? WHERE id = ?`,
            )
            .run(count, narrativeText, suggestionText, direction, now, patternId);
        } else {
          this.db
            .prepare(
              `UPDATE patterns SET occurrence_count = ?, narrative_text = ?, suggestion_text = ?,
               direction = ? WHERE id = ?`,
            )
            .run(count, narrativeText, suggestionText, direction, patternId);
        }
      }

      this.db.prepare('DELETE FROM pattern_entries WHERE pattern_id = ?').run(patternId);
      const insertLink = this.db.prepare(
        'INSERT INTO pattern_entries (pattern_id, entry_id) VALUES (?, ?)',
      );
      for (const entryId of supportingEntryIds.get(key) ?? []) {
        insertLink.run(patternId, entryId);
      }
    }

    // Drop patterns that no longer meet the threshold — e.g. after a supporting entry was edited
    // or deleted (spec Edge Cases).
    for (const [key, pattern] of existing) {
      if (!seen.has(key)) {
        this.db.prepare('DELETE FROM pattern_entries WHERE pattern_id = ?').run(pattern.id);
        this.db.prepare('DELETE FROM patterns WHERE id = ?').run(pattern.id);
      }
    }
  }

  listPatterns(): PatternOut[] {
    // `id` is a tiebreaker, not decoration: patterns written in the same recompute share a
    // `last_updated_at` to the microsecond, and ordering by that alone leaves ties in whatever
    // order the database returns — which let the two clients show different orders.
    const rows = this.db
      .prepare(
        `SELECT p.id, t.name AS topic, p.feeling_key, p.occurrence_count, p.direction,
                p.narrative_text, p.suggestion_text, p.last_updated_at
         FROM patterns p JOIN topics t ON t.id = p.topic_id
         ORDER BY p.last_updated_at DESC, p.id`,
      )
      .all() as Array<{
      id: string;
      topic: string;
      feeling_key: string;
      occurrence_count: number;
      direction: string;
      narrative_text: string;
      suggestion_text: string;
      last_updated_at: string;
    }>;

    return rows.map((r) => ({
      id: r.id,
      topic: r.topic,
      feeling: r.feeling_key,
      occurrence_count: Number(r.occurrence_count),
      direction: r.direction,
      narrative_text: r.narrative_text,
      suggestion_text: r.suggestion_text,
      last_updated_at: serializeDateTime(decodeDateTime(r.last_updated_at)),
    }));
  }
}
