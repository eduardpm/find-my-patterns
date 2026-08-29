/**
 * CH-0 — `GET /insights/series`, end to end.
 *
 * The endpoint exists so every planned chart (mood line, Year in Pixels, the topic sparkline, Year
 * in Review) reads one number from one place instead of each client inventing its own day score.
 * Every scenario below is picked so a human can work the expected score out by hand from
 * `VALENCE_SCORE` (`happy` +1, `neutral` 0, `sad` −1) — see `src/insights/constants.ts` for the
 * day-score definition this file is verifying.
 */

import Database from 'better-sqlite3';
import request from 'supertest';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { addDays } from '../../src/insights/analysis';
import { decodeDate, encodeDate } from '../../src/db/codecs';
import { bootOnFresh, teardown, type Harness } from '../helpers/app';

let h: Harness;
const server = () => h.app.getHttpServer();

beforeEach(async () => {
  h = await bootOnFresh();
});
afterEach(async () => {
  await teardown(h);
});

interface SeriesPointOut {
  date: string;
  score: number | null;
  entry_count: number;
  confirmed_feeling_count: number;
}

interface SeriesOut {
  granularity: 'day' | 'week' | 'month';
  points: SeriesPointOut[];
  constants: Record<string, unknown>;
}

/** Creates one entry and confirms it with the given feelings, backdated to `date`. */
async function writeConfirmed(date: string, feelings: string[]): Promise<void> {
  const created = (
    await request(server())
      .post('/entries')
      .send({ mode: 'freeform', raw_text: `Entry for ${date}.` })
      .expect(201)
  ).body as { id: string; version: number };

  if (feelings.length > 0) {
    await request(server())
      .patch(`/entries/${created.id}`)
      .send({ feeling_keys: feelings, version: created.version })
      .expect(200);
  }

  // The API always files a new entry under today's date (as `insight-scenarios.test.ts` notes
  // too); every scenario below needs specific, known dates, so this goes around it the same way.
  backdate(created.id, date);
}

/** An entry with no feelings settled at all — an `unset` day with entries but no confirmed evidence. */
async function writeUnconfirmed(date: string): Promise<void> {
  const created = (
    await request(server())
      .post('/entries')
      .send({ mode: 'freeform', raw_text: `Entry for ${date}, unconfirmed.` })
      .expect(201)
  ).body as { id: string };
  backdate(created.id, date);
}

function backdate(entryId: string, date: string): void {
  const db = new Database(h.dbPath);
  db.prepare('UPDATE diary_entries SET entry_date = ? WHERE id = ?').run(date, entryId);
  db.close();
}

/** Not `async` on purpose — returning a thenable from an async function unwraps it early and drops
 *  `.expect()`, so this stays a plain function that hands back the chainable supertest `Test`. */
function series(from: string, to: string, granularity?: 'day' | 'week' | 'month'): request.Test {
  const query = granularity
    ? `from=${from}&to=${to}&granularity=${granularity}`
    : `from=${from}&to=${to}`;
  return request(server()).get(`/insights/series?${query}`);
}

function pointFor(body: SeriesOut, date: string): SeriesPointOut | undefined {
  return body.points.find((p) => p.date === date);
}

// A Monday-first week, matching WEEKDAYS/weekdayIndex.
const MON = '2024-01-01';
const TUE = '2024-01-02';
const WED = '2024-01-03';
// THU 2024-01-04 is left empty on purpose — the gap day.
const FRI = '2024-01-05';
const SAT = '2024-01-06';

describe('GET /insights/series — day score (CH-0)', () => {
  it('scores a single-feeling day exactly', async () => {
    await writeConfirmed(MON, ['happy']);
    const res = await series(MON, MON).expect(200);
    const body = res.body as SeriesOut;
    expect(body.granularity).toBe('day');
    expect(body.points).toEqual([
      { date: MON, score: 1, entry_count: 1, confirmed_feeling_count: 1 },
    ]);
  });

  it('flattens every confirmed feeling across every entry that day, not per entry first', async () => {
    // Two confirmed entries on the same day: {happy, sad} and {happy}.
    // Flat mean over the three feelings: (1 + -1 + 1) / 3 = 0.3333…
    // A per-entry-then-per-day mean would instead give (0 + 1) / 2 = 0.5 — the two disagree, which
    // is what makes this scenario prove which rule actually ran.
    await writeConfirmed(SAT, ['happy', 'sad']);
    await writeConfirmed(SAT, ['happy']);

    const res = await series(SAT, SAT).expect(200);
    const point = pointFor(res.body as SeriesOut, SAT)!;
    expect(point.entry_count).toBe(2);
    expect(point.confirmed_feeling_count).toBe(3);
    expect(point.score).toBeCloseTo(1 / 3, 10);
  });

  it('averages confirmed feelings across multiple entries in one day', async () => {
    await writeConfirmed(TUE, ['sad']);
    await writeConfirmed(TUE, ['neutral']);

    const res = await series(TUE, TUE).expect(200);
    expect(res.body.points).toEqual([
      { date: TUE, score: -0.5, entry_count: 2, confirmed_feeling_count: 2 },
    ]);
  });

  it('scores null, carrying the entry count, when a day has entries but zero confirmed feelings', async () => {
    await writeUnconfirmed(WED);

    const res = await series(WED, WED).expect(200);
    expect(res.body.points).toEqual([
      { date: WED, score: null, entry_count: 1, confirmed_feeling_count: 0 },
    ]);
  });

  it('omits a day with no entries at all — a gap is a gap, not a null point', async () => {
    await writeConfirmed(MON, ['happy']);
    await writeConfirmed(FRI, ['neutral']);
    // Thursday 2024-01-04 gets no entry.

    const res = await series(MON, FRI).expect(200);
    const body = res.body as SeriesOut;
    expect(body.points.map((p) => p.date)).toEqual([MON, FRI]);
    expect(pointFor(body, '2024-01-04')).toBeUndefined();
  });

  it('never folds feeling_intensity into the score', async () => {
    const created = (
      await request(server())
        .post('/entries')
        .send({ mode: 'freeform', raw_text: `Entry for ${MON}.` })
        .expect(201)
    ).body as { id: string; version: number };
    const patched = (
      await request(server())
        .patch(`/entries/${created.id}`)
        .send({ feeling_keys: ['neutral'], feeling_intensity: 5, version: created.version })
        .expect(200)
    ).body as { id: string };
    backdate(patched.id, MON);

    const res = await series(MON, MON).expect(200);
    // neutral is VALENCE_SCORE 0 — a 5/5 intensity must not pull this positive or negative.
    expect(pointFor(res.body as SeriesOut, MON)!.score).toBe(0);
  });
});

describe('GET /insights/series — week and month aggregation', () => {
  it('aggregates a week by the mean of day scores, summing the counts', async () => {
    await writeConfirmed(MON, ['happy']); // score 1
    await writeConfirmed(TUE, ['sad']); // score -0.5 (paired below)
    await writeConfirmed(TUE, ['neutral']);
    await writeUnconfirmed(WED); // score null — excluded from the mean, not treated as 0
    // Thursday: gap.
    await writeConfirmed(FRI, ['neutral']); // score 0

    const res = await series(MON, FRI, 'week').expect(200);
    const body = res.body as SeriesOut;
    expect(body.granularity).toBe('week');
    expect(body.points).toHaveLength(1);
    const [week] = body.points;
    // Monday-first week start, matching WEEKDAYS.
    expect(week.date).toBe(MON);
    // Mean of the three non-null day scores: (1 + -0.5 + 0) / 3.
    expect(week.score).toBeCloseTo((1 + -0.5 + 0) / 3, 10);
    // Entries: Mon 1 + Tue 2 + Wed 1 + Fri 1 = 5. Confirmed feelings: Mon 1 + Tue 2 + Wed 0 + Fri 1 = 4.
    expect(week.entry_count).toBe(5);
    expect(week.confirmed_feeling_count).toBe(4);
  });

  it('reports a week as null only when every day in it is null', async () => {
    await writeUnconfirmed(MON);
    await writeUnconfirmed(TUE);

    const res = await series(MON, TUE, 'week').expect(200);
    const [week] = (res.body as SeriesOut).points;
    expect(week.score).toBeNull();
    expect(week.entry_count).toBe(2);
    expect(week.confirmed_feeling_count).toBe(0);
  });

  it('aggregates a month at its first-of-month date', async () => {
    await writeConfirmed('2024-02-10', ['happy']);
    await writeConfirmed('2024-02-20', ['sad']);

    const res = await series('2024-02-01', '2024-02-29', 'month').expect(200);
    const body = res.body as SeriesOut;
    expect(body.granularity).toBe('month');
    expect(body.points).toEqual([
      { date: '2024-02-01', score: 0, entry_count: 2, confirmed_feeling_count: 2 },
    ]);
  });

  it('defaults to day granularity when none is given', async () => {
    await writeConfirmed(MON, ['happy']);
    const res = await series(MON, MON).expect(200);
    expect((res.body as SeriesOut).granularity).toBe('day');
  });
});

describe('GET /insights/series — constants', () => {
  it('serves the identical constants shape GET /insights does', async () => {
    const insights = (await request(server()).get('/insights').expect(200)).body as {
      constants: Record<string, unknown>;
    };
    const s = (await series(MON, MON).expect(200)).body as SeriesOut;
    expect(Object.keys(s.constants).sort()).toEqual(Object.keys(insights.constants).sort());
    expect(s.constants).toEqual(insights.constants);
  });
});

describe('GET /insights/series — range validation', () => {
  it('rejects a missing from', async () => {
    const res = await request(server()).get('/insights/series?to=2024-01-01').expect(422);
    expect(res.body.error.code).toBe('validation_error');
  });

  it('rejects a missing to', async () => {
    const res = await request(server()).get('/insights/series?from=2024-01-01').expect(422);
    expect(res.body.error.code).toBe('validation_error');
  });

  it('rejects a malformed date', async () => {
    const res = await series('not-a-date', '2024-01-31').expect(422);
    expect(res.body.error.code).toBe('validation_error');
  });

  it('rejects from after to', async () => {
    const res = await series('2024-01-31', '2024-01-01').expect(422);
    expect(res.body.error.code).toBe('validation_error');
  });

  it('rejects an unknown granularity', async () => {
    const res = await request(server())
      .get('/insights/series?from=2024-01-01&to=2024-01-02&granularity=year')
      .expect(422);
    expect(res.body.error.code).toBe('validation_error');
  });

  it('accepts exactly 400 days at day granularity', async () => {
    const from = decodeDate('2024-01-01');
    const to = encodeDate(addDays(from, 399)); // 400 days inclusive
    await series('2024-01-01', to).expect(200);
  });

  it('rejects 401 days at day granularity', async () => {
    const from = decodeDate('2024-01-01');
    const to = encodeDate(addDays(from, 400)); // 401 days inclusive
    const res = await series('2024-01-01', to).expect(422);
    expect(res.body.error.code).toBe('validation_error');
  });

  it('does not cap week/month granularity at 400 days', async () => {
    const from = decodeDate('2020-01-01');
    const to = encodeDate(addDays(from, 900)); // > 400 days
    await series('2020-01-01', to, 'week').expect(200);
    await series('2020-01-01', to, 'month').expect(200);
  });
});

describe('GET /insights/series — performance (CH-0 acceptance criterion)', () => {
  it('answers a 365-day day-granularity query in under 200ms', async () => {
    // Seeded directly rather than through 365 HTTP round trips: the budget is for the query this
    // endpoint runs, not for the setup that gets a year of data into the fixture.
    const db = new Database(h.dbPath);
    const keys = ['happy', 'neutral', 'sad'];
    const insertEntry = db.prepare(
      `INSERT INTO diary_entries
       (id, created_at, updated_at, entry_date, mode, raw_text, feeling_key, feeling_source, version)
       VALUES (?, ?, ?, ?, 'freeform', ?, ?, 'confirmed', 1)`,
    );
    const insertFeeling = db.prepare(
      `INSERT INTO entry_feelings (entry_id, feeling_key, position) VALUES (?, ?, 0)`,
    );
    const seed = db.transaction(() => {
      const start = decodeDate('2025-01-01');
      for (let i = 0; i < 365; i += 1) {
        const date = encodeDate(addDays(start, i));
        const id = `perf-entry-${i}`;
        const key = keys[i % keys.length];
        const stamp = `${date} 12:00:00.000000`;
        insertEntry.run(id, stamp, stamp, date, `Day ${i}`, key);
        insertFeeling.run(id, key);
      }
    });
    seed();
    db.close();

    const started = performance.now();
    const res = await series('2025-01-01', '2025-12-31').expect(200);
    const elapsedMs = performance.now() - started;

    expect((res.body as SeriesOut).points).toHaveLength(365);
    console.log(`[CH-0 perf] GET /insights/series over 365 days: ${elapsedMs.toFixed(2)}ms`);
    expect(elapsedMs).toBeLessThan(200);
  });
});
