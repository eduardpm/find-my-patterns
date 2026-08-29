/**
 * T021–T024 — contract tests for the read endpoints.
 *
 * Expectations come from contracts/api.md — the shapes both clients are built against.
 */

import request from 'supertest';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { bootOnCopy, teardown, type Harness } from '../helpers/app';
import { FEELING_GROUP_SEED, FEELING_SEED } from '../../src/db/feeling-vocabulary';

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
  it('serves the whole vocabulary flat, in vocabulary order', async () => {
    const res = await request(server()).get('/feelings').expect(200);
    expect(res.body.feelings.map((f: { key: string }) => f.key)).toEqual(
      FEELING_SEED.map((feeling) => feeling.key),
    );
  });

  it('still serves the eight original keys, so existing entries keep resolving', async () => {
    const res = await request(server()).get('/feelings');
    const keys = new Set(res.body.feelings.map((f: { key: string }) => f.key));
    for (const key of [
      'happy',
      'excited',
      'neutral',
      'sleepy',
      'exhausted',
      'stressed',
      'sad',
      'depressed',
    ]) {
      expect(keys.has(key)).toBe(true);
    }
  });

  it('exposes key, label, valence and group_key — and nothing else', async () => {
    const res = await request(server()).get('/feelings');
    for (const feeling of res.body.feelings) {
      expect(Object.keys(feeling).sort()).toEqual(['group_key', 'key', 'label', 'valence']);
    }
  });

  it('serves the same vocabulary nested as groups', async () => {
    const res = await request(server()).get('/feelings');
    expect(res.body.groups.map((g: { key: string }) => g.key)).toEqual(
      FEELING_GROUP_SEED.map((group) => group.key),
    );

    const nested = res.body.groups.flatMap((g: { feelings: Array<{ key: string }> }) =>
      g.feelings.map((f) => f.key),
    );
    expect(nested.sort()).toEqual(res.body.feelings.map((f: { key: string }) => f.key).sort());
  });

  it('gives every group between three and eight feelings, valence matching the group except a stated override', async () => {
    // #60: `calm`, `content`, `relaxed`, `focused` and `curious` are pleasant states that sit in
    // "Steady" for presentation only — the group stays `neutral`, tinting the client accordingly,
    // but these five carry their own `positive` valence for the insight engine. Anything else
    // diverging from its group here would be the seed drifting apart by accident, not this ticket.
    const OVERRIDDEN: Record<string, string> = {
      calm: 'positive',
      content: 'positive',
      relaxed: 'positive',
      focused: 'positive',
      curious: 'positive',
    };
    const res = await request(server()).get('/feelings');
    for (const group of res.body.groups) {
      expect(group.feelings.length).toBeGreaterThanOrEqual(3);
      expect(group.feelings.length).toBeLessThanOrEqual(8);
      for (const feeling of group.feelings) {
        expect(feeling.valence).toBe(OVERRIDDEN[feeling.key] ?? group.valence);
        expect(feeling.group_key).toBe(group.key);
      }
    }
  });
});

describe('GET /guiding-questions', () => {
  it('serves the library with decoded trigger keywords', async () => {
    const res = await request(server()).get('/guiding-questions').expect(200);
    // A6-01/A6-02: the library grew by three optional time-slot prompts, and the three mandatory
    // questions that were already there keep the same keys and mandatory flags — only their
    // wording was shortened (#14). Entries already store a snapshot of the wording they were
    // answered under, so that snapshot (not this endpoint) is what has to keep quoting the user
    // accurately; this endpoint is free to serve whatever the current copy is.
    expect(res.body.questions).toHaveLength(7);
    const core = res.body.questions.filter((q: { is_mandatory: boolean }) => q.is_mandatory);
    expect(core.map((q: { key: string }) => q.key)).toEqual([
      'general_feeling',
      'mind_body',
      'small_influences',
    ]);
    expect(
      res.body.questions
        .filter((q: { category: string }) =>
          ['morning', 'afternoon', 'evening'].includes(q.category),
        )
        .map((q: { key: string; is_mandatory: boolean }) => [q.key, q.is_mandatory]),
    ).toEqual([
      ['morning_start', false],
      ['afternoon_middle', false],
      ['evening_close', false],
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
        'analysis_pending',
        'created_at',
        'entry_date',
        'feeling_intensities',
        'feeling_intensity',
        'feeling_key',
        'feeling_keys',
        'feeling_source',
        'guided_answers',
        'id',
        'mode',
        'origin',
        'raw_text',
        'suggested_feeling',
        'suggested_feelings',
        'topic_feelings',
        'topics',
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
