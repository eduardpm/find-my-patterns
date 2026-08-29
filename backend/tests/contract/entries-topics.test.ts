/**
 * #81 — the entry's topics on the entry payload, independent of `topic_feelings`.
 *
 * `topic_feelings` (E-1a, `entries-topic-feelings.test.ts`) is flattened one row per
 * (topic, feeling) pair, so a topic the engine extracted but could not pair with any feeling —
 * "fine and common" per E-1a's own spec — produces no row there at all. This field is sourced
 * from `TopicsService.topicsForEntry()` (also what `echo.service.ts` and `patterns.service.ts`
 * already use) and must include that unpaired topic, which is the specific case these tests cover.
 *
 * `ImmediateTestInference` (the test double `NODE_ENV=test` wires in — see `app.module.ts`) never
 * extracts topics itself, so `entry_topics` rows are written directly with `better-sqlite3`, the
 * same technique `entries-topic-feelings.test.ts` uses.
 */

import Database from 'better-sqlite3';
import { randomUUID } from 'node:crypto';
import request from 'supertest';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { encodeDateTime, nowUtc } from '../../src/db/codecs';
import { bootOnFresh, teardown, type Harness } from '../helpers/app';

let h: Harness;
const server = () => h.app.getHttpServer();

beforeEach(async () => {
  h = await bootOnFresh();
});
afterEach(async () => {
  await teardown(h);
});

interface Topic {
  id: string;
  name: string;
}

/** Link a topic to an entry directly, exactly as `TopicsService.linkTopics` would. */
function linkTopic(entryId: string, name: string): Topic {
  const db = new Database(h.dbPath);
  try {
    const id = randomUUID();
    const now = encodeDateTime(nowUtc());
    db.prepare(
      `INSERT INTO topics (id, name, aliases, first_seen_at, last_seen_at) VALUES (?, ?, '[]', ?, ?)`,
    ).run(id, name, now, now);
    db.prepare(
      `INSERT INTO entry_topics (entry_id, topic_id, extracted_by) VALUES (?, ?, 'llm')`,
    ).run(entryId, id);
    return { id, name };
  } finally {
    db.close();
  }
}

/** Write a `'suggested'` pairing row directly, standing in for a completed `applyAnalysis`. */
function suggestPairing(entryId: string, topicId: string, feelingKey: string): void {
  const db = new Database(h.dbPath);
  try {
    db.prepare(
      `INSERT INTO entry_topic_feelings (entry_id, topic_id, feeling_key, source)
       VALUES (?, ?, ?, 'suggested')`,
    ).run(entryId, topicId, feelingKey);
  } finally {
    db.close();
  }
}

async function createEntry(): Promise<{ id: string; entry_date: string }> {
  const created = (
    await request(server())
      .post('/entries')
      .send({ mode: 'freeform', raw_text: 'A walk, then a call with family.' })
      .expect(201)
  ).body as { id: string; entry_date: string };
  return created;
}

describe('GET /entries/{id} — topics', () => {
  it('is present and empty when the entry has no topics', async () => {
    const entry = await createEntry();
    const res = await request(server()).get(`/entries/${entry.id}`).expect(200);
    expect(res.body.topics).toEqual([]);
  });

  it('includes a topic that has no feeling pairing at all', async () => {
    // The case `topic_feelings` cannot represent: a topic the engine extracted but could not pair
    // with any feeling produces no `topic_feelings` row, yet it must still appear in `topics`.
    const entry = await createEntry();
    const walking = linkTopic(entry.id, 'walking');

    const res = await request(server()).get(`/entries/${entry.id}`).expect(200);
    expect(res.body.topics).toEqual([{ id: walking.id, name: 'walking' }]);
    expect(res.body.topic_feelings).toEqual([]);
  });

  it('includes both a paired and an unpaired topic on the same entry', async () => {
    const entry = await createEntry();
    const family = linkTopic(entry.id, 'family');
    const walking = linkTopic(entry.id, 'walking');
    suggestPairing(entry.id, family.id, 'grateful');
    // `walking` is deliberately left without any pairing.

    const res = await request(server()).get(`/entries/${entry.id}`).expect(200);
    expect(res.body.topics).toEqual(
      expect.arrayContaining([
        { id: family.id, name: 'family' },
        { id: walking.id, name: 'walking' },
      ]),
    );
    expect(res.body.topics).toHaveLength(2);
    expect(res.body.topic_feelings).toEqual([
      { topic_id: family.id, topic: 'family', feeling_key: 'grateful', source: 'suggested' },
    ]);
  });

  it('is served on the list endpoint too, not only the single-entry read', async () => {
    const entry = await createEntry();
    const walking = linkTopic(entry.id, 'walking');

    const listed = await request(server()).get(`/entries?date=${entry.entry_date}`).expect(200);
    const found = listed.body.entries.find((e: { id: string }) => e.id === entry.id);
    expect(found.topics).toEqual([{ id: walking.id, name: 'walking' }]);
  });

  it('is served after a PATCH that does not touch the raw text', async () => {
    const entry = await createEntry();
    const walking = linkTopic(entry.id, 'walking');
    const current = (await request(server()).get(`/entries/${entry.id}`).expect(200)).body as {
      version: number;
    };

    const patched = await request(server())
      .patch(`/entries/${entry.id}`)
      .send({ feeling_keys: ['calm'], version: current.version })
      .expect(200);
    expect(patched.body.topics).toEqual([{ id: walking.id, name: 'walking' }]);
  });
});
