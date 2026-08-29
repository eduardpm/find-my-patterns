/**
 * L-4 / SC-008 — `GET /insights/question-yield`.
 *
 * `entry_topics` is derived data: keyword extraction only runs for entries whose feeling has been
 * confirmed (`PatternsService.loadEvidenceEntries` reads `feeling_source IN ('confirmed',
 * 'overridden')`), and only as part of `GET /insights`'s recompute. Every entry below is therefore
 * PATCHed with a feeling before `GET /insights` is called once to populate `entry_topics`, exactly
 * as `insight-scenarios.test.ts` does for the same reason.
 *
 * The guided-question *prompt* text is itself part of an entry's `raw_text` (createEntry composes
 * "prompt\nanswer" blocks), and some prompts — `mind_body`, `small_influences`, `morning_start` —
 * contain curated keywords in their own wording (e.g. mind_body's prompt says "hunger" and "pain").
 * That would make every guided entry using those questions "yield" a topic regardless of what was
 * actually answered. `general_feeling` and `evening_close` are used here because their prompt text
 * contains no curated keyword, which keeps the scenario a fact about the answers, not the prompts.
 */

import Database from 'better-sqlite3';
import request from 'supertest';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { bootOnFresh, teardown, type Harness } from '../helpers/app';

let h: Harness;
const server = () => h.app.getHttpServer();

const GENERAL_FEELING_PROMPT =
  'Since your last entry—or in the last few hours—what happened? What were you doing, where ' +
  'were you, and who was around?';
const EVENING_CLOSE_PROMPT =
  'How is the day ending? Think what changed since this afternoon, what you did to wind down, ' +
  'and what you are carrying into tonight.';

interface CreatedEntry {
  id: string;
  version: number;
  entry_date: string;
}

/** Creates a guided entry, then confirms a feeling on it so `GET /insights` treats it as evidence. */
async function createGuidedEntry(
  answers: Array<{ question_key: string; answer_text: string }>,
): Promise<CreatedEntry> {
  const created = (
    await request(server())
      .post('/entries')
      .send({ mode: 'guided', raw_text: '', guided_answers: answers })
      .expect(201)
  ).body as CreatedEntry;

  await request(server())
    .patch(`/entries/${created.id}`)
    .send({ feeling_keys: ['content'], version: created.version })
    .expect(200);

  return created;
}

function backdate(dbPath: string, entryId: string, daysAgo: number): string {
  const db = new Database(dbPath);
  const when = new Date(Date.now() - daysAgo * 86_400_000).toISOString().slice(0, 10);
  db.prepare('UPDATE diary_entries SET entry_date = ? WHERE id = ?').run(when, entryId);
  db.close();
  return when;
}

beforeEach(async () => {
  h = await bootOnFresh();
});
afterEach(async () => {
  await teardown(h);
});

describe('GET /insights/question-yield', () => {
  it('attributes yield per answer and reports the SC-008 overall rate', async () => {
    // Entry A: one answer mentions a curated topic ("coffee"), the other does not — the
    // acceptance criteria's "one answer yields a topic and one doesn't" inside a single entry.
    await createGuidedEntry([
      { question_key: 'general_feeling', answer_text: 'Had coffee this morning and felt great' },
      { question_key: 'evening_close', answer_text: 'Wound down slowly and felt calm before bed' },
    ]);

    // Entry B: neither answer mentions any curated topic, so it yields nothing at all.
    await createGuidedEntry([
      {
        question_key: 'general_feeling',
        answer_text: 'Nothing much happened today, an ordinary quiet one',
      },
      { question_key: 'evening_close', answer_text: 'Just relaxed and did nothing special' },
    ]);

    // A freeform entry that mentions "coffee" too — must never be counted as a guided entry.
    const freeform = (
      await request(server())
        .post('/entries')
        .send({ mode: 'freeform', raw_text: 'Had coffee and went for a run' })
        .expect(201)
    ).body as CreatedEntry;
    await request(server())
      .patch(`/entries/${freeform.id}`)
      .send({ feeling_keys: ['content'], version: freeform.version })
      .expect(200);

    // Recomputes patterns, which is the only place `entry_topics` gets (re)written.
    await request(server()).get('/insights').expect(200);

    const body = (await request(server()).get('/insights/question-yield').expect(200)).body as {
      from: string | null;
      to: string | null;
      overall: { guided_entries: number; guided_entries_yielding: number; rate: number | null };
      questions: Array<{
        question_key: string;
        wording_snapshot_latest: string;
        answered: number;
        yielded: number;
        rate: number | null;
      }>;
    };

    expect(body.from).toBeNull();
    expect(body.to).toBeNull();

    // Only the two guided entries count — SC-008 is about guided entries specifically.
    expect(body.overall).toEqual({
      guided_entries: 2,
      guided_entries_yielding: 1,
      rate: 0.5,
    });

    const byKey = Object.fromEntries(body.questions.map((q) => [q.question_key, q]));
    expect(Object.keys(byKey).sort()).toEqual(['evening_close', 'general_feeling']);

    expect(byKey.general_feeling).toEqual({
      question_key: 'general_feeling',
      wording_snapshot_latest: GENERAL_FEELING_PROMPT,
      answered: 2,
      yielded: 1,
      rate: 0.5,
    });

    expect(byKey.evening_close).toEqual({
      question_key: 'evening_close',
      wording_snapshot_latest: EVENING_CLOSE_PROMPT,
      answered: 2,
      yielded: 0,
      rate: 0,
    });
  });

  it('filters by entry_date range, inclusive on both ends', async () => {
    const entryA = await createGuidedEntry([
      { question_key: 'general_feeling', answer_text: 'Had coffee this morning and felt great' },
    ]);
    await createGuidedEntry([
      { question_key: 'general_feeling', answer_text: 'An ordinary quiet day' },
    ]);

    const dateA = backdate(h.dbPath, entryA.id, 10);
    // Entry B stays dated today.

    await request(server()).get('/insights').expect(200);

    // A window that brackets only entry A's date.
    const from = new Date(Date.now() - 11 * 86_400_000).toISOString().slice(0, 10);
    const to = dateA;
    const onlyA = (
      await request(server()).get('/insights/question-yield').query({ from, to }).expect(200)
    ).body as { overall: { guided_entries: number; guided_entries_yielding: number } };

    expect(onlyA.overall).toEqual({ guided_entries: 1, guided_entries_yielding: 1, rate: 1 });

    // A window that excludes entry A and keeps entry B.
    const recentFrom = new Date(Date.now() - 1 * 86_400_000).toISOString().slice(0, 10);
    const onlyB = (
      await request(server())
        .get('/insights/question-yield')
        .query({ from: recentFrom })
        .expect(200)
    ).body as { overall: { guided_entries: number; guided_entries_yielding: number } };

    expect(onlyB.overall).toEqual({ guided_entries: 1, guided_entries_yielding: 0, rate: 0 });
  });

  it('answers 422 validation_error for a malformed date', async () => {
    const res = await request(server())
      .get('/insights/question-yield')
      .query({ from: 'not-a-date' })
      .expect(422);
    expect(res.body.error.code).toBe('validation_error');
  });

  it('answers 422 validation_error when from is after to', async () => {
    const res = await request(server())
      .get('/insights/question-yield')
      .query({ from: '2026-08-20', to: '2026-08-01' })
      .expect(422);
    expect(res.body.error.code).toBe('validation_error');
  });

  it('reports null rates and an empty question list on an empty diary', async () => {
    const body = (await request(server()).get('/insights/question-yield').expect(200)).body as {
      overall: { guided_entries: number; guided_entries_yielding: number; rate: number | null };
      questions: unknown[];
    };
    expect(body.overall).toEqual({ guided_entries: 0, guided_entries_yielding: 0, rate: null });
    expect(body.questions).toEqual([]);
  });
});
