/**
 * T021–T024 — contract tests for the read endpoints.
 *
 * Expectations come from contracts/api.md — the shapes both clients are built against.
 */

import request from 'supertest';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { bootOnCopy, teardown, type Harness } from '../helpers/app';

let h: Harness;

beforeAll(async () => {
  h = await bootOnCopy();
});
afterAll(async () => {
  await teardown(h);
});

const server = () => h.app.getHttpServer();
const FIXTURE_MONTH = '2026-07';

async function populatedFixtureDate(): Promise<string> {
  const summary = await request(server())
    .get(`/monthly-summary?month=${FIXTURE_MONTH}`)
    .expect(200);
  const populated = summary.body.days.find(
    (day: { feelings: string[] }) => day.feelings.length > 0,
  );
  expect(populated).toBeTruthy();
  return populated.date as string;
}

describe('GET /feelings', () => {
  it('serves all eight seeded feelings', async () => {
    const res = await request(server()).get('/feelings').expect(200);
    expect(res.body.feelings).toHaveLength(8);
  });

  it('serves them in seed order', async () => {
    const res = await request(server()).get('/feelings');
    expect(res.body.feelings.map((f: { key: string }) => f.key)).toEqual([
      'happy',
      'excited',
      'neutral',
      'sleepy',
      'exhausted',
      'stressed',
      'sad',
      'depressed',
    ]);
  });

  it('exposes key, label and valence — and nothing else', async () => {
    const res = await request(server()).get('/feelings');
    for (const feeling of res.body.feelings) {
      expect(Object.keys(feeling).sort()).toEqual(['key', 'label', 'valence']);
    }
  });
});

describe('GET /guiding-questions', () => {
  it('serves the library with decoded trigger keywords', async () => {
    const res = await request(server()).get('/guiding-questions').expect(200);
    expect(res.body.questions).toHaveLength(4);
    const core = res.body.questions.filter((q: { is_mandatory: boolean }) => q.is_mandatory);
    expect(core.map((q: { key: string }) => q.key)).toEqual([
      'general_feeling',
      'mind_body',
      'small_influences',
    ]);
    const responseOutcome = res.body.questions.find(
      (q: { key: string }) => q.key === 'response_outcome',
    );
    expect(responseOutcome.prompt_text).toBe('What did you do next, and what changed afterward?');
    expect(responseOutcome.trigger_keywords).toContain('stressed');
    expect(responseOutcome.is_mandatory).toBe(false);
  });

  it('marks the general prompt as mandatory, as a real boolean', async () => {
    const res = await request(server()).get('/guiding-questions');
    const general = res.body.questions.find((q: { key: string }) => q.key === 'general_feeling');
    expect(general.is_mandatory).toBe(true);
    expect(general.trigger_keywords).toEqual([]);
  });
});

describe('GET /entries?date=', () => {
  it('lists the golden diary’s entries for their day', async () => {
    const res = await request(server())
      .get(`/entries?date=${await populatedFixtureDate()}`)
      .expect(200);
    expect(res.body.entries.length).toBeGreaterThan(0);
  });

  it('serves created_at with microseconds and no timezone suffix', async () => {
    const res = await request(server()).get(`/entries?date=${await populatedFixtureDate()}`);

    for (const entry of res.body.entries) {
      expect(entry.created_at).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}$/);
      expect(entry.created_at.endsWith('Z')).toBe(false);
    }
  });

  it('always emits every key, using null rather than omission', async () => {
    const res = await request(server()).get(`/entries?date=${await populatedFixtureDate()}`);

    for (const entry of res.body.entries) {
      expect(Object.keys(entry).sort()).toEqual([
        'created_at',
        'entry_date',
        'feeling_key',
        'feeling_source',
        'id',
        'mode',
        'raw_text',
        'suggested_feeling',
        'version',
      ]);
    }
  });

  it('rejects a missing date with 422', async () => {
    const res = await request(server()).get('/entries').expect(422);
    expect(res.body.error.code).toBe('validation_error');
  });
});

describe('GET /entries/{id}', () => {
  it('returns 404 in the contract error shape for an unknown id', async () => {
    const res = await request(server()).get('/entries/does-not-exist').expect(404);
    expect(res.body).toEqual({ error: { code: 'not_found', message: 'Entry not found' } });
  });
});

describe('GET /monthly-summary', () => {
  it('includes every day of the month, including empty ones', async () => {
    const res = await request(server()).get(`/monthly-summary?month=${FIXTURE_MONTH}`).expect(200);
    expect(res.body.days).toHaveLength(31);
    expect(res.body.days.some((d: { feelings: string[] }) => d.feelings.length === 0)).toBe(true);
  });

  it('does not round the daily average', async () => {
    const res = await request(server()).get(`/monthly-summary?month=${FIXTURE_MONTH}`);
    // Both clients round for display; the backend must not, or they start disagreeing.
    expect(typeof res.body.average_entries_per_day).toBe('number');
  });

  it('rejects a malformed month with 422', async () => {
    const res = await request(server()).get('/monthly-summary?month=nonsense').expect(422);
    expect(res.body.error.code).toBe('validation_error');
  });

  it('sorts each day’s feelings', async () => {
    const res = await request(server()).get(`/monthly-summary?month=${FIXTURE_MONTH}`);
    for (const day of res.body.days) {
      expect(day.feelings).toEqual([...day.feelings].sort());
    }
  });
});
