/**
 * `GET /export` end to end (M-6): JSON round-trips every field the issue lists plus the
 * `topic_feelings` this PR adds to the list, a Markdown snapshot of the same diary, determinism
 * across two consecutive requests, and format validation.
 *
 * `ImmediateTestInference` (the test double `NODE_ENV=test` wires in — see `app.module.ts`) never
 * extracts topics or writes pairings, so `entry_topics`/`entry_topic_feelings` rows are written
 * directly with `better-sqlite3`, the same technique `entries-topic-feelings.test.ts` uses to
 * reproduce what the real worker would have written.
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

interface Created {
  id: string;
  version: number;
}

interface GuidedAnswerOut {
  question_key: string;
  question_text: string;
  answer_text: string;
  order_index: number;
}

interface EntryReadOut {
  raw_text: string;
  entry_date: string;
  created_at: string;
  guided_answers: GuidedAnswerOut[];
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

/** Write a topic↔feeling pairing row directly, standing in for a stored E-1a decision. */
function pairTopicFeeling(
  entryId: string,
  topicId: string,
  feelingKey: string,
  source: 'suggested' | 'confirmed' | 'overridden',
): void {
  const db = new Database(h.dbPath);
  try {
    db.prepare(
      `INSERT INTO entry_topic_feelings (entry_id, topic_id, feeling_key, source) VALUES (?, ?, ?, ?)`,
    ).run(entryId, topicId, feelingKey, source);
  } finally {
    db.close();
  }
}

/**
 * Resets an entry to the state a freshly created one is in before the (real, non-test) worker has
 * ever run: no feelings, source `'unset'`. `ImmediateTestInference` applies a `'suggested'`
 * `neutral` feeling synchronously on every entry with non-empty text, which is exactly the state
 * production never actually serves for more than an instant — this puts a second, still-unrated
 * entry in the diary to exercise the export's empty-`feelings`/empty-`topics` path honestly.
 */
function clearAnalysis(entryId: string): void {
  const db = new Database(h.dbPath);
  try {
    db.prepare(
      `UPDATE diary_entries SET feeling_key = NULL, feeling_source = 'unset', feeling_intensity = NULL
       WHERE id = ?`,
    ).run(entryId);
    db.prepare('DELETE FROM entry_feelings WHERE entry_id = ?').run(entryId);
  } finally {
    db.close();
  }
}

/** `h:mm AM/PM`, no leading zero on the hour — mirrors `export.service.ts#formatClockTime`. */
function clockTime(isoDateTime: string): string {
  const match = /T(\d{2}):(\d{2})/.exec(isoDateTime);
  if (!match) throw new Error(`Not a naive ISO datetime: ${isoDateTime}`);
  const hour = Number(match[1]);
  const minute = match[2];
  const period = hour >= 12 ? 'PM' : 'AM';
  const hour12 = hour % 12 === 0 ? 12 : hour % 12;
  return `${hour12}:${minute} ${period}`;
}

/**
 * Seeds one guided, mixed-valence, fully-annotated entry (feelings with a mixed
 * rated/unrated pair, two topics, one confirmed topic↔feeling pairing) and one bare freeform
 * entry with nothing on it yet — created second, so `created_at` ordering can be asserted too.
 */
async function seedDiary(): Promise<{
  createdA: Created;
  readA: EntryReadOut;
  workTopic: Topic;
  createdB: Created;
  readB: EntryReadOut;
}> {
  const createdA = (
    await request(server())
      .post('/entries')
      .send({
        mode: 'guided',
        guided_answers: [
          { question_key: 'mind_body', answer_text: 'Tense shoulders, low energy after lunch.' },
          { question_key: 'small_influences', answer_text: 'Barely slept, back-to-back meetings.' },
        ],
      })
      .expect(201)
  ).body as Created;

  await request(server())
    .patch(`/entries/${createdA.id}`)
    .send({
      feeling_keys: ['stressed', 'anxious'],
      feeling_intensities: { stressed: 3 },
      version: createdA.version,
    })
    .expect(200);

  const workTopic = linkTopic(createdA.id, 'work');
  linkTopic(createdA.id, 'exercise');
  pairTopicFeeling(createdA.id, workTopic.id, 'stressed', 'confirmed');

  const readA = (await request(server()).get(`/entries/${createdA.id}`).expect(200))
    .body as EntryReadOut;

  const createdB = (
    await request(server())
      .post('/entries')
      .send({ mode: 'freeform', raw_text: 'Just a quiet day, nothing much to report.' })
      .expect(201)
  ).body as Created;
  clearAnalysis(createdB.id);

  const readB = (await request(server()).get(`/entries/${createdB.id}`).expect(200))
    .body as EntryReadOut;

  return { createdA, readA, workTopic, createdB, readB };
}

describe('GET /export', () => {
  it('rejects a missing or unrecognised format', async () => {
    await request(server()).get('/export').expect(422);
    await request(server()).get('/export?format=csv').expect(422);
  });

  it('JSON round-trips every field for a seeded mixed entry, ordered by created_at', async () => {
    const { createdA, readA, workTopic, createdB, readB } = await seedDiary();

    const res = await request(server()).get('/export?format=json').expect(200);

    expect(res.headers['content-type']).toContain('application/json');
    expect(res.headers['content-disposition']).toMatch(
      /^attachment; filename="find-my-patterns-export-\d{4}-\d{2}-\d{2}\.json"$/,
    );
    expect(res.body.schema_version).toBe(1);
    expect(res.body.entries).toHaveLength(2);

    const [entryA, entryB] = res.body.entries as unknown[];

    // The guided, mixed entry — every field the issue lists, plus `topic_feelings` (E-1a, not in
    // the issue's original field list — see the PR description and docs/export.md).
    expect(entryA).toEqual({
      id: createdA.id,
      date: readA.entry_date,
      created_at: readA.created_at,
      mode: 'guided',
      raw_text: readA.raw_text,
      guided_answers: readA.guided_answers,
      // `source` is entry-level (`feeling_source`), repeated on each feeling — see
      // docs/export.md "Feelings" for why there is no per-feeling provenance to serve instead.
      feelings: [
        { key: 'stressed', source: 'overridden', intensity: 3 },
        { key: 'anxious', source: 'overridden', intensity: null },
      ],
      // Ordered by name; `surface_form` repeats `topic` (docs/export.md "Topics").
      topics: [
        { topic: 'exercise', surface_form: 'exercise' },
        { topic: 'work', surface_form: 'work' },
      ],
      topic_feelings: [
        { topic_id: workTopic.id, topic: 'work', feeling_key: 'stressed', source: 'confirmed' },
      ],
    });

    // The bare freeform entry — every array present and empty, nothing silently omitted.
    expect(entryB).toEqual({
      id: createdB.id,
      date: readB.entry_date,
      created_at: readB.created_at,
      mode: 'freeform',
      raw_text: readB.raw_text,
      guided_answers: [],
      feelings: [],
      topics: [],
      topic_feelings: [],
    });
  });

  it(
    'renders a Markdown document: guided and freeform bodies, Feelings/Topics lines present ' +
      'and omitted',
    async () => {
      const { readA, readB } = await seedDiary();

      const res = await request(server()).get('/export?format=markdown').expect(200);

      expect(res.headers['content-type']).toContain('text/markdown');
      expect(res.headers['content-disposition']).toMatch(
        /^attachment; filename="find-my-patterns-export-\d{4}-\d{2}-\d{2}\.md"$/,
      );

      const sectionA = [
        `## ${readA.entry_date} — ${clockTime(readA.created_at)}`,
        readA.guided_answers
          .map((answer) => `**${answer.question_text}**\n${answer.answer_text}`)
          .join('\n\n'),
        'Feelings: Stressed (3/5, overridden) · Anxious (overridden)',
        'Topics: exercise, work',
      ].join('\n\n');

      const sectionB = [
        `## ${readB.entry_date} — ${clockTime(readB.created_at)}`,
        readB.raw_text,
      ].join('\n\n');

      expect(res.text).toBe(`${sectionA}\n\n${sectionB}\n`);
    },
  );

  it('is deterministic: two consecutive exports of an unchanged diary are byte-identical', async () => {
    await seedDiary();

    const jsonFirst = await request(server()).get('/export?format=json').expect(200);
    const jsonSecond = await request(server()).get('/export?format=json').expect(200);
    expect(jsonSecond.text).toBe(jsonFirst.text);

    const mdFirst = await request(server()).get('/export?format=markdown').expect(200);
    const mdSecond = await request(server()).get('/export?format=markdown').expect(200);
    expect(mdSecond.text).toBe(mdFirst.text);
  });

  it('excludes an unfinalized guided draft from both formats', async () => {
    const draft = (await request(server()).post('/guided-entry-drafts').expect(201)).body as {
      draft_key: string;
    };
    await request(server())
      .put(`/guided-entry-drafts/${draft.draft_key}/questions/mind_body`)
      .send({ answer_text: 'Still drafting.', order_index: 0 })
      .expect(204);

    const json = await request(server()).get('/export?format=json').expect(200);
    expect(json.body.entries).toEqual([]);

    const markdown = await request(server()).get('/export?format=markdown').expect(200);
    expect(markdown.text).toBe('');
  });
});
