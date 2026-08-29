import { Inject, Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { decodeJson, encodeDateTime, encodeJson, nowUtc } from '../db/codecs';
import { DIARY_DB } from '../db/database.provider';
import type { DiaryDatabase } from '../db/database';
import {
  canonicalTopicName,
  findCuratedMatches,
  mentions,
  normalizeTopicName,
  type KnownTopic,
} from './canonicalization';

/**
 * Deterministic, keyword-based topic extraction and the topic rows it writes.
 *
 * The vocabulary and every matching rule live in `canonicalization.ts`, which is pure and shared
 * with the inference worker so a model-proposed topic and a keyword-extracted one land on the same
 * canonical row (A4). This file is the database half: find-or-create, link, merge, alias.
 */

// Re-exported so callers that only need the vocabulary — the worker, the suggestion guard, tests —
// keep importing it from here.
export { CURATED_TOPIC_KEYWORDS, findCuratedMatches, mentions } from './canonicalization';

interface TopicRow {
  id: string;
  name: string;
  aliases: string;
  first_seen_at: string;
  last_seen_at: string;
}

export interface Topic {
  id: string;
  name: string;
}

export interface TopicDetail {
  id: string;
  name: string;
  aliases: string[];
  entry_count: number;
}

export class TopicNotFoundError extends Error {}
export class InvalidAliasError extends Error {}

@Injectable()
export class TopicsService {
  constructor(@Inject(DIARY_DB) private readonly db: DiaryDatabase) {}

  private knownTopics(): KnownTopic[] {
    return (
      this.db.prepare('SELECT name, aliases FROM topics ORDER BY name').all() as Array<{
        name: string;
        aliases: string;
      }>
    ).map((row) => ({ name: row.name, aliases: decodeJson<string[]>(row.aliases ?? '[]') }));
  }

  private findExistingTopicMatches(textLower: string): Set<string> {
    const matches = new Set<string>();
    const rows = this.db.prepare('SELECT * FROM topics').all() as TopicRow[];
    for (const row of rows) {
      const names = [row.name, ...decodeJson<string[]>(row.aliases ?? '[]')];
      if (names.some((name) => name && mentions(textLower, name.toLowerCase()))) {
        matches.add(row.name);
      }
    }
    return matches;
  }

  private getOrCreateTopic(name: string): Topic {
    const existing = this.db.prepare('SELECT * FROM topics WHERE name = ?').get(name) as
      TopicRow | undefined;
    const now = encodeDateTime(nowUtc());

    if (existing) {
      this.db.prepare('UPDATE topics SET last_seen_at = ? WHERE id = ?').run(now, existing.id);
      return { id: existing.id, name: existing.name };
    }

    const id = randomUUID();
    this.db
      .prepare(
        'INSERT INTO topics (id, name, aliases, first_seen_at, last_seen_at) VALUES (?, ?, ?, ?, ?)',
      )
      .run(id, name, encodeJson([]), now, now);
    return { id, name };
  }

  /**
   * Find-or-create the topics mentioned in an entry and link them to it.
   *
   * Idempotent: pattern recomputation re-scans every eligible entry on each run, so this must never
   * duplicate a link or a topic row.
   */
  extractAndLinkTopics(entryId: string, rawText: string): Topic[] {
    const textLower = (rawText ?? '').toLowerCase();
    if (!textLower.trim()) return [];

    const candidates = new Set([
      ...findCuratedMatches(textLower),
      ...this.findExistingTopicMatches(textLower),
    ]);
    if (candidates.size === 0) return [];

    return this.linkTopics(entryId, [...candidates], 'keyword');
  }

  /**
   * Store a set of topic names against an entry, each under its canonical name (A4-02).
   *
   * This is the single door every proposed topic comes through, whichever half of the app found
   * it. The canonical name is resolved before the row is touched, so a fragment never gets a row
   * of its own and then has to be merged back out of one later.
   *
   * `'import'` (L-1b, #35) is a Daylio CSV activity tag, mapped through the same canonicalisation
   * every other topic goes through. It deliberately is **not** `'keyword'`:
   * `PatternsService#loadEvidenceEntries` deletes and re-derives every `'keyword'` link from
   * `raw_text` on each recompute, and an imported activity usually is not a word the note itself
   * contains — a `'keyword'` link here would vanish the moment `GET /insights` next ran. Only
   * `'keyword'` rows are ever swept that way, so `'import'` (like `'llm'`) persists untouched.
   */
  linkTopics(entryId: string, names: string[], extractedBy: 'keyword' | 'llm' | 'import'): Topic[] {
    const known = this.knownTopics();
    const canonical = new Set<string>();
    for (const name of names) {
      const resolved = canonicalTopicName(name, known);
      if (resolved) canonical.add(resolved);
    }
    if (canonical.size === 0) return [];

    const alreadyLinked = new Set(
      (
        this.db.prepare('SELECT topic_id FROM entry_topics WHERE entry_id = ?').all(entryId) as {
          topic_id: string;
        }[]
      ).map((r) => r.topic_id),
    );

    const linked: Topic[] = [];
    for (const name of canonical) {
      const topic = this.getOrCreateTopic(name);
      linked.push(topic);
      if (!alreadyLinked.has(topic.id)) {
        // `extracted_by` records how the link was found. The column is nullable but is never
        // written as NULL.
        this.db
          .prepare('INSERT INTO entry_topics (entry_id, topic_id, extracted_by) VALUES (?, ?, ?)')
          .run(entryId, topic.id, extractedBy);
      }
    }
    return linked;
  }

  /**
   * Which existing topics a piece of text mentions — read-only.
   *
   * Deliberately find-without-create: this is what the pattern echo asks (I4-01), and an echo can
   * only ever be about a topic that already carries a pattern. Creating a row here would let a
   * *read* of a saved entry quietly grow the topic table.
   */
  matchExistingTopics(rawText: string): Topic[] {
    const textLower = (rawText ?? '').toLowerCase();
    if (!textLower.trim()) return [];

    const rows = this.db
      .prepare('SELECT id, name, aliases FROM topics ORDER BY name')
      .all() as Array<{
      id: string;
      name: string;
      aliases: string;
    }>;
    const curated = findCuratedMatches(textLower);

    return rows
      .filter((row) => {
        if (curated.has(row.name)) return true;
        const names = [row.name, ...decodeJson<string[]>(row.aliases ?? '[]')];
        return names.some((name) => name && mentions(textLower, name.toLowerCase()));
      })
      .map((row) => ({ id: row.id, name: row.name }));
  }

  topicsForEntry(entryId: string): Topic[] {
    return this.db
      .prepare(
        'SELECT t.id, t.name FROM topics t JOIN entry_topics et ON et.topic_id = t.id WHERE et.entry_id = ?',
      )
      .all(entryId) as Topic[];
  }

  // -------------------------------------------------------------------------------------------
  // Consolidation (A4-05 … A4-09)
  // -------------------------------------------------------------------------------------------

  /**
   * Fold fragmented topic rows into their canonical row.
   *
   * Run at the start of every recompute rather than once, and that is deliberate: it is how a
   * user-added alias takes effect on the next read without the model running again (A4-04). It is
   * idempotent, because after one pass no row resolves to anything but itself (A4-08).
   *
   * What moves: `entry_topics` links, and the merged row's name, which is kept as an alias so the
   * word the user actually wrote still matches their entries. What never moves: an entry, an
   * `entry_feelings` row, or a confirmed feeling — this function does not contain a statement that
   * could touch one (A4-09).
   *
   * Patterns are left pointing at the row that disappeared on purpose. The next recompute finds
   * the dangling reference and withdraws that pattern with the reason `topic_merged` (A2-02),
   * which is how the user is told their pattern moved rather than vanished.
   */
  mergeFragmentedTopics(): number {
    const rows = this.db
      .prepare('SELECT id, name, aliases FROM topics ORDER BY name')
      .all() as Array<{ id: string; name: string; aliases: string }>;
    if (rows.length === 0) return 0;

    const byName = new Map(rows.map((row) => [row.name, row]));
    const merges: Array<{ from: (typeof rows)[number]; toName: string }> = [];

    for (const row of rows) {
      // Resolved against every *other* topic, so a row can never be told to merge into itself.
      const others = rows
        .filter((other) => other.id !== row.id)
        .map((other) => ({
          name: other.name,
          aliases: decodeJson<string[]>(other.aliases ?? '[]'),
        }));
      const resolved = canonicalTopicName(row.name, others);
      if (!resolved || resolved === row.name) continue;
      // Only into a row that exists, and never into one already queued to disappear — otherwise a
      // two-step chain would strand links on a deleted row.
      if (!byName.has(resolved)) continue;
      if (merges.some((merge) => merge.from.name === resolved)) continue;
      merges.push({ from: row, toName: resolved });
    }

    if (merges.length === 0) return 0;

    return this.db.transaction(() => {
      let moved = 0;
      for (const { from, toName } of merges) {
        const target = byName.get(toName)!;
        if (target.id === from.id) continue;

        // `OR IGNORE`, because an entry that mentioned both the fragment and the canonical topic
        // already has the canonical link — and counting it twice is exactly what A4-06 forbids.
        this.db
          .prepare(
            `INSERT OR IGNORE INTO entry_topics (entry_id, topic_id, extracted_by)
             SELECT entry_id, ?, extracted_by FROM entry_topics WHERE topic_id = ?`,
          )
          .run(target.id, from.id);
        this.db.prepare('DELETE FROM entry_topics WHERE topic_id = ?').run(from.id);

        const aliases = new Set(decodeJson<string[]>(target.aliases ?? '[]'));
        aliases.add(from.name);
        for (const alias of decodeJson<string[]>(from.aliases ?? '[]')) aliases.add(alias);
        aliases.delete(target.name);
        const encoded = encodeJson([...aliases].sort());
        this.db.prepare('UPDATE topics SET aliases = ? WHERE id = ?').run(encoded, target.id);
        target.aliases = encoded;

        this.db.prepare('DELETE FROM topics WHERE id = ?').run(from.id);
        moved += 1;
      }
      return moved;
    });
  }

  // -------------------------------------------------------------------------------------------
  // The alias table the user edits (A4-04)
  // -------------------------------------------------------------------------------------------

  listTopics(): TopicDetail[] {
    return (
      this.db
        .prepare(
          `SELECT t.id, t.name, t.aliases,
                  (SELECT COUNT(*) FROM entry_topics et WHERE et.topic_id = t.id) AS entry_count
           FROM topics t ORDER BY t.name`,
        )
        .all() as Array<{ id: string; name: string; aliases: string; entry_count: number }>
    ).map((row) => ({
      id: row.id,
      name: row.name,
      aliases: decodeJson<string[]>(row.aliases ?? '[]'),
      entry_count: Number(row.entry_count),
    }));
  }

  addAlias(topicId: string, alias: string): TopicDetail {
    const normalized = normalizeTopicName(alias);
    if (!normalized) throw new InvalidAliasError('An alias must contain at least one word.');
    return this.db.transaction(() => {
      const topic = this.db
        .prepare('SELECT id, name, aliases FROM topics WHERE id = ?')
        .get(topicId) as { id: string; name: string; aliases: string } | undefined;
      if (!topic) throw new TopicNotFoundError(topicId);
      if (normalizeTopicName(topic.name) === normalized) {
        throw new InvalidAliasError('That is already the topic\u2019s own name.');
      }
      // An alias that already points somewhere else would make the same phrase resolve two ways,
      // and which one won would depend on row order.
      const clash = this.knownTopics().find(
        (other) =>
          other.name !== topic.name &&
          (normalizeTopicName(other.name) === normalized ||
            other.aliases.some((existing) => normalizeTopicName(existing) === normalized)),
      );
      if (clash) {
        throw new InvalidAliasError(`\u201c${normalized}\u201d already belongs to ${clash.name}.`);
      }

      const aliases = new Set(decodeJson<string[]>(topic.aliases ?? '[]'));
      aliases.add(normalized);
      this.db
        .prepare('UPDATE topics SET aliases = ? WHERE id = ?')
        .run(encodeJson([...aliases].sort()), topicId);
      return this.listTopics().find((row) => row.id === topicId)!;
    });
  }

  removeAlias(topicId: string, alias: string): TopicDetail {
    const normalized = normalizeTopicName(alias);
    return this.db.transaction(() => {
      const topic = this.db.prepare('SELECT id, aliases FROM topics WHERE id = ?').get(topicId) as
        { id: string; aliases: string } | undefined;
      if (!topic) throw new TopicNotFoundError(topicId);
      const remaining = decodeJson<string[]>(topic.aliases ?? '[]').filter(
        (existing) => normalizeTopicName(existing) !== normalized,
      );
      this.db
        .prepare('UPDATE topics SET aliases = ? WHERE id = ?')
        .run(encodeJson(remaining.sort()), topicId);
      return this.listTopics().find((row) => row.id === topicId)!;
    });
  }
}
