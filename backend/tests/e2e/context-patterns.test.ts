/**
 * #21 — passive context factors (weekday, day type, time of day, season) through the same 2×2 +
 * lift + threshold engine the topic patterns use.
 *
 * Every scenario starts from an empty diary and writes entries the way a user would, exactly like
 * `roadmap-engine.test.ts`, so the assertions can be closed: a number here is one a person could
 * work out by hand from the entries above it.
 */

import Database from 'better-sqlite3';
import request from 'supertest';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { CONTEXT_FACTORS } from '../../src/insights/constants';
import { bootOnFresh, teardown, type Harness } from '../helpers/app';

let h: Harness;
const server = () => h.app.getHttpServer();

beforeEach(async () => {
  h = await bootOnFresh();
});
afterEach(async () => {
  await teardown(h);
});

interface Written {
  id: string;
  version: number;
}

/** Write an entry and confirm its feelings, exactly as a client does. */
async function write(text: string, feelings: string[]): Promise<Written> {
  const created = (
    await request(server()).post('/entries').send({ mode: 'freeform', raw_text: text }).expect(201)
  ).body as { id: string; version: number };

  return (
    await request(server())
      .patch(`/entries/${created.id}`)
      .send({ feeling_keys: feelings, version: created.version })
      .expect(200)
  ).body as Written;
}

/** Sets `entry_date` directly, unlike `roadmap-engine.test.ts`'s `daysAgo` helper — this suite needs
 *  entries pinned to a specific *weekday*, not merely a specific age. */
function backdateTo(entryId: string, date: string): void {
  const db = new Database(h.dbPath);
  db.prepare('UPDATE diary_entries SET entry_date = ? WHERE id = ?').run(date, entryId);
  db.close();
}

const isoDate = (daysAgo: number): string =>
  new Date(Date.now() - daysAgo * 86_400_000).toISOString().slice(0, 10);

/** Sunday, as `new Date(...).getUTCDay()` sees it — the same UTC calendar the backend's own
 *  `weekdayIndex` reads `entry_date` through (`analysis.ts#daysBetween`/`#weekdayIndex`). */
const isSunday = (daysAgo: number): boolean => new Date(isoDate(daysAgo)).getUTCDay() === 0;

/** The first `count` days, within the 30-day recency window, that land on a Sunday. */
function sundaysWithin30Days(count: number): number[] {
  const found: number[] = [];
  for (let daysAgo = 0; daysAgo < 30 && found.length < count; daysAgo += 1) {
    if (isSunday(daysAgo)) found.push(daysAgo);
  }
  if (found.length < count)
    throw new Error('not enough Sundays in a 30-day window — should not happen');
  return found;
}

/** The first `count` days, within the window, that do *not* land on a Sunday. */
function nonSundaysWithin30Days(count: number): number[] {
  const found: number[] = [];
  for (let daysAgo = 0; daysAgo < 30 && found.length < count; daysAgo += 1) {
    if (!isSunday(daysAgo)) found.push(daysAgo);
  }
  if (found.length < count)
    throw new Error('not enough non-Sundays in a 30-day window — should not happen');
  return found;
}

interface ContextPattern {
  id: string;
  kind: 'context';
  factor: string;
  factor_category: 'weekday' | 'daytype' | 'timeofday' | 'season';
  factor_label: string;
  feeling: string;
  occurrence_count: number;
  lifetime_count: number;
  status: 'active' | 'historical';
  direction: string;
  narrative_text: string;
  present_count: number;
  present_total: number;
  absent_count: number;
  absent_total: number;
  present_rate: number | null;
  absent_rate: number | null;
  base_rate: number;
  lift: number | null;
  comparison_reason: string | null;
  comparison_note: string | null;
  is_strong: boolean;
  evidence: Array<{ entry_id: string; entry_date: string; feeling_keys: string[] }>;
}

interface Pattern {
  kind: 'forward' | 'inverse';
  topic: string;
  feeling: string;
}

interface InsightsBody {
  patterns: Pattern[];
  context_patterns: ContextPattern[];
  insufficient_data: boolean;
}

const insights = async (): Promise<InsightsBody> =>
  (await request(server()).get('/insights').expect(200)).body as InsightsBody;

const findContext = (
  body: InsightsBody,
  factor: string,
  feeling: string,
): ContextPattern | undefined =>
  body.context_patterns.find((p) => p.factor === factor && p.feeling === feeling);

describe('#21 — weekday, day type, time of day and season through the engine', () => {
  it('surfaces a weekday:sunday → anxious pattern with correct 2×2 counts and a 3× lift', async () => {
    // 4 Sundays, every one of them anxious.
    const sundays = sundaysWithin30Days(4);
    for (const daysAgo of sundays) {
      const entry = await write(`A tense Sunday, ${daysAgo} days ago.`, ['anxious']);
      backdateTo(entry.id, isoDate(daysAgo));
    }
    // 12 other days: 4 anxious, 8 content — so the "without Sunday" anxious rate is 4/12 (33%)
    // against Sunday's 4/4 (100%), a lift of exactly 3.
    const others = nonSundaysWithin30Days(12);
    for (const [index, daysAgo] of others.entries()) {
      const feeling = index < 4 ? 'anxious' : 'content';
      const entry = await write(`An ordinary day, ${daysAgo} days ago.`, [feeling]);
      backdateTo(entry.id, isoDate(daysAgo));
    }

    const body = await insights();
    const pattern = findContext(body, 'weekday:sunday', 'anxious')!;
    expect(pattern).toBeDefined();
    expect(pattern.kind).toBe('context');
    expect(pattern.factor_category).toBe('weekday');
    expect(pattern.factor_label).toBe('Sunday');
    expect(pattern.present_count).toBe(4);
    expect(pattern.present_total).toBe(4);
    expect(pattern.absent_count).toBe(4);
    expect(pattern.absent_total).toBe(12);
    expect(pattern.lift).toBeCloseTo(3, 5);
    expect(pattern.occurrence_count).toBe(4);
    expect(pattern.status).toBe('active');
    // Lift clears STRONG_LIFT (3.0) but only 4 occurrences, short of STRONG_MIN_OCCURRENCES (5) —
    // both conditions are required, same as a topic pattern (A3-07).
    expect(pattern.is_strong).toBe(false);
    expect(pattern.direction).toBe('change'); // anxious is negative, kind is not 'inverse'
    expect(pattern.narrative_text).toBe(
      'You felt anxious in 4 of 4 entries on Sundays in the last 30 days (100%), ' +
        'and in 4 of 12 other entries (33%).',
    );
    // A1-02/A1-04: the evidence trail agrees with the count, oldest first.
    expect(pattern.evidence).toHaveLength(4);
    const dates = pattern.evidence.map((e) => e.entry_date);
    expect([...dates].sort()).toEqual(dates);
    for (const entry of pattern.evidence) expect(entry.feeling_keys).toContain('anxious');
  });

  it('suppresses a below-threshold weekday pair — only 2 Sunday occurrences', async () => {
    const sundays = sundaysWithin30Days(2);
    for (const daysAgo of sundays) {
      const entry = await write(`A tense Sunday, ${daysAgo} days ago.`, ['anxious']);
      backdateTo(entry.id, isoDate(daysAgo));
    }
    const others = nonSundaysWithin30Days(10);
    for (const daysAgo of others) {
      const entry = await write(`An ordinary day, ${daysAgo} days ago.`, ['content']);
      backdateTo(entry.id, isoDate(daysAgo));
    }

    const body = await insights();
    // Below MIN_OCCURRENCE_THRESHOLD entirely — the pair never even becomes a candidate.
    expect(findContext(body, 'weekday:sunday', 'anxious')).toBeUndefined();
  });

  it('suppresses a pair that merely rides the base rate, even at 3+ occurrences', async () => {
    // 4 anxious Sundays, but anxious is *also* the majority feeling everywhere else — no lift.
    const sundays = sundaysWithin30Days(4);
    for (const daysAgo of sundays) {
      const entry = await write(`A Sunday, ${daysAgo} days ago.`, ['anxious']);
      backdateTo(entry.id, isoDate(daysAgo));
    }
    const others = nonSundaysWithin30Days(16);
    for (const daysAgo of others) {
      const entry = await write(`An ordinary day, ${daysAgo} days ago.`, ['anxious']);
      backdateTo(entry.id, isoDate(daysAgo));
    }

    const body = await insights();
    expect(findContext(body, 'weekday:sunday', 'anxious')).toBeUndefined();
  });

  it('never pairs a context factor with another context factor', async () => {
    const sundays = sundaysWithin30Days(4);
    for (const daysAgo of sundays) {
      const entry = await write(`A Sunday, ${daysAgo} days ago.`, ['anxious']);
      backdateTo(entry.id, isoDate(daysAgo));
    }
    const others = nonSundaysWithin30Days(12);
    for (const [index, daysAgo] of others.entries()) {
      const feeling = index < 4 ? 'anxious' : 'content';
      const entry = await write(`An ordinary day, ${daysAgo} days ago.`, [feeling]);
      backdateTo(entry.id, isoDate(daysAgo));
    }

    const body = await insights();
    const factorKeys = new Set(CONTEXT_FACTORS.map((f) => f.key));
    // `feeling` never names another context factor — the only "present" side ever paired with a
    // context factor is a real feeling key.
    for (const pattern of body.context_patterns) {
      expect(factorKeys.has(pattern.feeling)).toBe(false);
    }
  });

  it('never lets a context factor masquerade as a topic in the topic patterns array', async () => {
    const sundays = sundaysWithin30Days(4);
    for (const daysAgo of sundays) {
      const entry = await write(`A Sunday, ${daysAgo} days ago.`, ['anxious']);
      backdateTo(entry.id, isoDate(daysAgo));
    }
    const others = nonSundaysWithin30Days(12);
    for (const [index, daysAgo] of others.entries()) {
      const feeling = index < 4 ? 'anxious' : 'content';
      const entry = await write(`An ordinary day, ${daysAgo} days ago.`, [feeling]);
      backdateTo(entry.id, isoDate(daysAgo));
    }

    const body = await insights();
    const factorKeysAndLabels = new Set(
      CONTEXT_FACTORS.flatMap((f) => [f.key, f.label.toLowerCase()]),
    );
    for (const pattern of body.patterns) {
      expect(factorKeysAndLabels.has(pattern.topic.toLowerCase())).toBe(false);
    }
  });

  it('leaves the rest of the insights payload unchanged — only the new array is added', async () => {
    await write('A quiet afternoon.', ['calm']);
    const body = (await request(server()).get('/insights').expect(200)).body as Record<
      string,
      unknown
    >;
    expect(Object.keys(body).sort()).toEqual(
      [
        'constants',
        'context_patterns',
        // E-1b: `excluded_unpaired` is additive (acceptance criterion 5) — a diary-wide count of
        // entries the mixed-valence pairing rule excluded from at least one pair, zero here since
        // this diary has no mixed-valence entries at all.
        'excluded_unpaired',
        'insufficient_data',
        'new_withdrawal_count',
        'patterns',
        'withdrawals',
      ].sort(),
    );
  });

  it('is identical across two reads, same as the topic patterns (I5-SC3 for context)', async () => {
    const sundays = sundaysWithin30Days(4);
    for (const daysAgo of sundays) {
      const entry = await write(`A Sunday, ${daysAgo} days ago.`, ['anxious']);
      backdateTo(entry.id, isoDate(daysAgo));
    }
    const others = nonSundaysWithin30Days(12);
    for (const [index, daysAgo] of others.entries()) {
      const feeling = index < 4 ? 'anxious' : 'content';
      const entry = await write(`An ordinary day, ${daysAgo} days ago.`, [feeling]);
      backdateTo(entry.id, isoDate(daysAgo));
    }

    const first = (await insights()).context_patterns;
    const second = (await insights()).context_patterns;
    expect(second).toEqual(first);
  });
});
