import { Inject, Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { decodeJson, encodeDateTime, encodeJson, nowUtc } from '../db/codecs';
import { SCOPED_DB, type ScopedDb } from '../db/scoped-db';
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
  constructor(@Inject(SCOPED_DB) private readonly db: ScopedDb) {}

  private knownTopics(userId: string): KnownTopic[] {
    return (
      this.db
        .forUser(userId)
        .prepare('SELECT name, aliases FROM topics WHERE user_id = ? ORDER BY name')
        .all(userId) as Array<{
        name: string;
        aliases: string;
      }>
    ).map((row) => ({ name: row.name, aliases: decodeJson<string[]>(row.aliases ?? '[]') }));
  }

  private findExistingTopicMatches(userId: string, textLower: string): Set<string> {
    const matches = new Set<string>();
    const rows = this.db
      .forUser(userId)
      .prepare('SELECT * FROM topics WHERE user_id = ?')
      .all(userId) as TopicRow[];
    for (const row of rows) {
      const names = [row.name, ...decodeJson<string[]>(row.aliases ?? '[]')];
      if (names.some((name) => name && mentions(textLower, name.toLowerCase()))) {
        matches.add(row.name);
      }
    }
    return matches;
  }

  /**
   * `topics.name` is unique per user (`UNIQUE (user_id, name)`, `schema.ts`'s M-1b step 2 note) —
   * two accounts can each hold their own "coffee" row. The `SELECT` below is scoped to `userId` for
   * the same reason every other query in this class is: it is what makes this user find (or fail
   * to find) only their own prior topic, never adopt a different user's row for the same name.
   */
  private getOrCreateTopic(userId: string, name: string): Topic {
    const handle = this.db.forUser(userId);
    const existing = handle
      .prepare('SELECT * FROM topics WHERE user_id = ? AND name = ?')
      .get(userId, name) as TopicRow | undefined;
    const now = encodeDateTime(nowUtc());

    if (existing) {
      handle
        .prepare('UPDATE topics SET last_seen_at = ? WHERE id = ? AND user_id = ?')
        .run(now, existing.id, userId);
      return { id: existing.id, name: existing.name };
    }

    const id = randomUUID();
    handle
      .prepare(
        `INSERT INTO topics (id, user_id, name, aliases, first_seen_at, last_seen_at)
         VALUES (?, ?, ?, ?, ?, ?)`,
      )
      .run(id, userId, name, encodeJson([]), now, now);
    return { id, name };
  }

  /**
   * Find-or-create the topics mentioned in an entry and link them to it.
   *
   * Idempotent: pattern recomputation re-scans every eligible entry on each run, so this must never
   * duplicate a link or a topic row.
   */
  extractAndLinkTopics(userId: string, entryId: string, rawText: string): Topic[] {
    const textLower = (rawText ?? '').toLowerCase();
    if (!textLower.trim()) return [];

    const candidates = new Set([
      ...findCuratedMatches(textLower),
      ...this.findExistingTopicMatches(userId, textLower),
    ]);
    if (candidates.size === 0) return [];

    return this.linkTopics(userId, entryId, [...candidates], 'keyword');
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
  linkTopics(
    userId: string,
    entryId: string,
    names: string[],
    extractedBy: 'keyword' | 'llm' | 'import',
  ): Topic[] {
    const known = this.knownTopics(userId);
    const canonical = new Set<string>();
    for (const name of names) {
      const resolved = canonicalTopicName(name, known);
      if (resolved) canonical.add(resolved);
    }
    if (canonical.size === 0) return [];

    const handle = this.db.forUser(userId);
    const alreadyLinked = new Set(
      (
        handle
          .prepare('SELECT topic_id FROM entry_topics WHERE user_id = ? AND entry_id = ?')
          .all(userId, entryId) as {
          topic_id: string;
        }[]
      ).map((r) => r.topic_id),
    );

    const linked: Topic[] = [];
    for (const name of canonical) {
      const topic = this.getOrCreateTopic(userId, name);
      linked.push(topic);
      if (!alreadyLinked.has(topic.id)) {
        // `extracted_by` records how the link was found. The column is nullable but is never
        // written as NULL.
        handle
          .prepare(
            'INSERT INTO entry_topics (entry_id, topic_id, user_id, extracted_by) VALUES (?, ?, ?, ?)',
          )
          .run(entryId, topic.id, userId, extractedBy);
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
  matchExistingTopics(userId: string, rawText: string): Topic[] {
    const textLower = (rawText ?? '').toLowerCase();
    if (!textLower.trim()) return [];

    const rows = this.db
      .forUser(userId)
      .prepare('SELECT id, name, aliases FROM topics WHERE user_id = ? ORDER BY name')
      .all(userId) as Array<{
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

  topicsForEntry(userId: string, entryId: string): Topic[] {
    return this.db
      .forUser(userId)
      .prepare(
        `SELECT t.id, t.name FROM topics t JOIN entry_topics et ON et.topic_id = t.id
         WHERE et.user_id = ? AND et.entry_id = ?`,
      )
      .all(userId, entryId) as Topic[];
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
  mergeFragmentedTopics(userId: string): number {
    const handle = this.db.forUser(userId);
    const rows = handle
      .prepare('SELECT id, name, aliases FROM topics WHERE user_id = ? ORDER BY name')
      .all(userId) as Array<{ id: string; name: string; aliases: string }>;
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

    return handle.transaction(() => {
      let moved = 0;
      for (const { from, toName } of merges) {
        const target = byName.get(toName)!;
        if (target.id === from.id) continue;

        // `OR IGNORE`, because an entry that mentioned both the fragment and the canonical topic
        // already has the canonical link — and counting it twice is exactly what A4-06 forbids.
        handle
          .prepare(
            `INSERT OR IGNORE INTO entry_topics (entry_id, topic_id, user_id, extracted_by)
             SELECT entry_id, ?, user_id, extracted_by FROM entry_topics
             WHERE user_id = ? AND topic_id = ?`,
          )
          .run(target.id, userId, from.id);
        handle
          .prepare('DELETE FROM entry_topics WHERE user_id = ? AND topic_id = ?')
          .run(userId, from.id);

        const aliases = new Set(decodeJson<string[]>(target.aliases ?? '[]'));
        aliases.add(from.name);
        for (const alias of decodeJson<string[]>(from.aliases ?? '[]')) aliases.add(alias);
        aliases.delete(target.name);
        const encoded = encodeJson([...aliases].sort());
        handle
          .prepare('UPDATE topics SET aliases = ? WHERE id = ? AND user_id = ?')
          .run(encoded, target.id, userId);
        target.aliases = encoded;

        handle.prepare('DELETE FROM topics WHERE id = ? AND user_id = ?').run(from.id, userId);
        moved += 1;
      }
      return moved;
    });
  }

  // -------------------------------------------------------------------------------------------
  // The alias table the user edits (A4-04)
  // -------------------------------------------------------------------------------------------

  listTopics(userId: string): TopicDetail[] {
    return (
      this.db
        .forUser(userId)
        .prepare(
          `SELECT t.id, t.name, t.aliases,
                  (SELECT COUNT(*) FROM entry_topics et
                   WHERE et.user_id = t.user_id AND et.topic_id = t.id) AS entry_count
           FROM topics t WHERE t.user_id = ? ORDER BY t.name`,
        )
        .all(userId) as Array<{ id: string; name: string; aliases: string; entry_count: number }>
    ).map((row) => ({
      id: row.id,
      name: row.name,
      aliases: decodeJson<string[]>(row.aliases ?? '[]'),
      entry_count: Number(row.entry_count),
    }));
  }

  addAlias(userId: string, topicId: string, alias: string): TopicDetail {
    const normalized = normalizeTopicName(alias);
    if (!normalized) throw new InvalidAliasError('An alias must contain at least one word.');
    const handle = this.db.forUser(userId);
    return handle.transaction(() => {
      const topic = handle
        .prepare('SELECT id, name, aliases FROM topics WHERE id = ? AND user_id = ?')
        .get(topicId, userId) as { id: string; name: string; aliases: string } | undefined;
      if (!topic) throw new TopicNotFoundError(topicId);
      if (normalizeTopicName(topic.name) === normalized) {
        throw new InvalidAliasError('That is already the topic\u2019s own name.');
      }
      // An alias that already points somewhere else would make the same phrase resolve two ways,
      // and which one won would depend on row order.
      const clash = this.knownTopics(userId).find(
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
      handle
        .prepare('UPDATE topics SET aliases = ? WHERE id = ? AND user_id = ?')
        .run(encodeJson([...aliases].sort()), topicId, userId);
      return this.listTopics(userId).find((row) => row.id === topicId)!;
    });
  }

  removeAlias(userId: string, topicId: string, alias: string): TopicDetail {
    const normalized = normalizeTopicName(alias);
    const handle = this.db.forUser(userId);
    return handle.transaction(() => {
      const topic = handle
        .prepare('SELECT id, aliases FROM topics WHERE id = ? AND user_id = ?')
        .get(topicId, userId) as { id: string; aliases: string } | undefined;
      if (!topic) throw new TopicNotFoundError(topicId);
      const remaining = decodeJson<string[]>(topic.aliases ?? '[]').filter(
        (existing) => normalizeTopicName(existing) !== normalized,
      );
      handle
        .prepare('UPDATE topics SET aliases = ? WHERE id = ? AND user_id = ?')
        .run(encodeJson(remaining.sort()), topicId, userId);
      return this.listTopics(userId).find((row) => row.id === topicId)!;
    });
  }
}
