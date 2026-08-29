/**
 * E-1a — read and write of an entry's topic↔feeling pairings.
 *
 * `ImmediateTestInference` (the test double `NODE_ENV=test` wires in — see `app.module.ts`) never
 * extracts topics or pairings, so `entry_topics`/`entry_topic_feelings` rows are written directly
 * with `better-sqlite3`, the same technique `entries-suggested-feelings.test.ts` uses to reproduce
 * what the real worker (`applyAnalysis` in `src/inference/worker.ts`) would have written.
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

async function createMixedValenceEntry(): Promise<{ id: string; version: number }> {
  const created = (
    await request(server())
      .post('/entries')
      .send({
        mode: 'freeform',
        raw_text: 'Missed my workout, disappointing. A call with family felt warm, though.',
      })
      .expect(201)
  ).body as { id: string; version: number };
  // Give the entry a mixed feeling set to pair against — `ImmediateTestInference` only ever
  // proposes `neutral`.
  const patched = (
    await request(server())
      .patch(`/entries/${created.id}`)
      .send({ feeling_keys: ['disappointed', 'grateful'], version: created.version })
      .expect(200)
  ).body as { id: string; version: number };
  return patched;
}

describe('GET /entries/{id} — topic_feelings', () => {
  it('is present and empty when nothing has ever been suggested or confirmed', async () => {
    const entry = await createMixedValenceEntry();
    const res = await request(server()).get(`/entries/${entry.id}`).expect(200);
    expect(res.body.topic_feelings).toEqual([]);
  });

  it('serves a suggested pairing with its topic name and source', async () => {
    const entry = await createMixedValenceEntry();
    const exercise = linkTopic(entry.id, 'exercise');
    suggestPairing(entry.id, exercise.id, 'disappointed');

    const res = await request(server()).get(`/entries/${entry.id}`).expect(200);
    expect(res.body.topic_feelings).toEqual([
      {
        topic_id: exercise.id,
        topic: 'exercise',
        feeling_key: 'disappointed',
        source: 'suggested',
      },
    ]);
  });

  it('is served on the list endpoint too, not only the single-entry read', async () => {
    const entry = await createMixedValenceEntry();
    const family = linkTopic(entry.id, 'family');
    suggestPairing(entry.id, family.id, 'grateful');

    const listed = await request(server())
      .get(`/entries?date=${(await request(server()).get(`/entries/${entry.id}`)).body.entry_date}`)
      .expect(200);
    const found = listed.body.entries.find((e: { id: string }) => e.id === entry.id);
    expect(found.topic_feelings).toEqual([
      { topic_id: family.id, topic: 'family', feeling_key: 'grateful', source: 'suggested' },
    ]);
  });
});

describe('PUT /entries/{id}/topic-feelings', () => {
  it('stores the confirmed set and returns it on the entry', async () => {
    const entry = await createMixedValenceEntry();
    const exercise = linkTopic(entry.id, 'exercise');
    const family = linkTopic(entry.id, 'family');

    const res = await request(server())
      .put(`/entries/${entry.id}/topic-feelings`)
      .send({
        pairings: [
          { topic_id: exercise.id, feeling_key: 'disappointed' },
          { topic_id: family.id, feeling_key: 'grateful' },
        ],
      })
      .expect(200);

    expect(
      (res.body.topic_feelings as Array<{ topic: string; feeling_key: string; source: string }>)
        .map(({ topic, feeling_key, source }) => ({ topic, feeling_key, source }))
        .sort((a, b) => a.topic.localeCompare(b.topic)),
    ).toEqual([
      { topic: 'exercise', feeling_key: 'disappointed', source: 'overridden' },
      { topic: 'family', feeling_key: 'grateful', source: 'overridden' },
    ]);
  });

  it('marks a pair that matches what was suggested as confirmed, and a changed one as overridden', async () => {
    const entry = await createMixedValenceEntry();
    const exercise = linkTopic(entry.id, 'exercise');
    const family = linkTopic(entry.id, 'family');
    suggestPairing(entry.id, exercise.id, 'disappointed');

    const res = await request(server())
      .put(`/entries/${entry.id}/topic-feelings`)
      .send({
        pairings: [
          { topic_id: exercise.id, feeling_key: 'disappointed' }, // matches the suggestion
          { topic_id: family.id, feeling_key: 'grateful' }, // the user added this one
        ],
      })
      .expect(200);

    const byTopic = Object.fromEntries(
      (res.body.topic_feelings as Array<{ topic: string; source: string }>).map((p) => [
        p.topic,
        p.source,
      ]),
    );
    expect(byTopic).toEqual({ exercise: 'confirmed', family: 'overridden' });
  });

  it('overwrites the previous pairing set rather than merging with it', async () => {
    const entry = await createMixedValenceEntry();
    const exercise = linkTopic(entry.id, 'exercise');
    const family = linkTopic(entry.id, 'family');

    await request(server())
      .put(`/entries/${entry.id}/topic-feelings`)
      .send({ pairings: [{ topic_id: exercise.id, feeling_key: 'disappointed' }] })
      .expect(200);

    const second = await request(server())
      .put(`/entries/${entry.id}/topic-feelings`)
      .send({ pairings: [{ topic_id: family.id, feeling_key: 'grateful' }] })
      .expect(200);

    expect(second.body.topic_feelings).toEqual([
      { topic_id: family.id, topic: 'family', feeling_key: 'grateful', source: 'overridden' },
    ]);
  });

  it('an empty set clears every pairing on the entry', async () => {
    const entry = await createMixedValenceEntry();
    const exercise = linkTopic(entry.id, 'exercise');
    await request(server())
      .put(`/entries/${entry.id}/topic-feelings`)
      .send({ pairings: [{ topic_id: exercise.id, feeling_key: 'disappointed' }] })
      .expect(200);

    const cleared = await request(server())
      .put(`/entries/${entry.id}/topic-feelings`)
      .send({ pairings: [] })
      .expect(200);

    expect(cleared.body.topic_feelings).toEqual([]);
  });

  it('rejects a topic that is not on this entry, with 422 validation_error', async () => {
    const entry = await createMixedValenceEntry();
    const otherEntry = await createMixedValenceEntry();
    const foreignTopic = linkTopic(otherEntry.id, 'travel');

    const res = await request(server())
      .put(`/entries/${entry.id}/topic-feelings`)
      .send({ pairings: [{ topic_id: foreignTopic.id, feeling_key: 'disappointed' }] })
      .expect(422);
    expect(res.body.error.code).toBe('validation_error');
  });

  it('rejects a feeling that is not on this entry, with 422 validation_error', async () => {
    const entry = await createMixedValenceEntry();
    const exercise = linkTopic(entry.id, 'exercise');

    // 'happy' is a real feeling in the vocabulary, just not one of this entry's own
    // ['disappointed', 'grateful'] — task 3's "only that entry's topics and feelings".
    const res = await request(server())
      .put(`/entries/${entry.id}/topic-feelings`)
      .send({ pairings: [{ topic_id: exercise.id, feeling_key: 'happy' }] })
      .expect(422);
    expect(res.body.error.code).toBe('validation_error');
  });

  it('rejects a feeling key outside the whole vocabulary before it ever reaches the entry check', async () => {
    const entry = await createMixedValenceEntry();
    const exercise = linkTopic(entry.id, 'exercise');

    const res = await request(server())
      .put(`/entries/${entry.id}/topic-feelings`)
      .send({ pairings: [{ topic_id: exercise.id, feeling_key: 'invented-by-a-client' }] })
      .expect(422);
    expect(res.body.error.code).toBe('validation_error');
  });

  it('leaves existing pairings untouched when a request is rejected — no partial writes', async () => {
    const entry = await createMixedValenceEntry();
    const exercise = linkTopic(entry.id, 'exercise');
    const family = linkTopic(entry.id, 'family');
    await request(server())
      .put(`/entries/${entry.id}/topic-feelings`)
      .send({ pairings: [{ topic_id: exercise.id, feeling_key: 'disappointed' }] })
      .expect(200);

    await request(server())
      .put(`/entries/${entry.id}/topic-feelings`)
      .send({
        pairings: [
          { topic_id: family.id, feeling_key: 'grateful' },
          { topic_id: 'not-a-real-topic', feeling_key: 'grateful' },
        ],
      })
      .expect(422);

    const current = await request(server()).get(`/entries/${entry.id}`).expect(200);
    expect(current.body.topic_feelings).toEqual([
      {
        topic_id: exercise.id,
        topic: 'exercise',
        feeling_key: 'disappointed',
        source: 'overridden',
      },
    ]);
  });

  it('returns 404 for an unknown entry', async () => {
    const res = await request(server())
      .put('/entries/does-not-exist/topic-feelings')
      .send({ pairings: [] })
      .expect(404);
    expect(res.body.error.code).toBe('not_found');
  });

  it('de-duplicates a repeated pairing instead of failing', async () => {
    const entry = await createMixedValenceEntry();
    const exercise = linkTopic(entry.id, 'exercise');

    const res = await request(server())
      .put(`/entries/${entry.id}/topic-feelings`)
      .send({
        pairings: [
          { topic_id: exercise.id, feeling_key: 'disappointed' },
          { topic_id: exercise.id, feeling_key: 'disappointed' },
        ],
      })
      .expect(200);

    expect(res.body.topic_feelings).toHaveLength(1);
  });
});
