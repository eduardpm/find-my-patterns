/**
 * [R-2] `GET /insights/digest` — "one pattern, one recommendation, one movement", run against the
 * real API on a fresh diary (`bootOnFresh`), the same closed-assertion style
 * `worth-trying-recommendations.test.ts` and `context-patterns.test.ts` already use for this
 * engine: every scenario states exactly what entries produce exactly which response, nothing more.
 *
 * Acceptance criterion 1 is determinism: "same data + week → same digest." Since neither this
 * service nor the rest of the engine consults the wall clock for anything the assertions below
 * check (`DigestService#get` takes the target week as a parameter, same as `series.service.ts`
 * takes `from`/`to`), every scenario passes an explicit `week` query value rather than relying on
 * `todayLocal()` — the one thing that *would* make a test flaky across days.
 *
 * M-3 (#48): `GET /insights/digest` is now `@RequiresPremium()` (weekly digest is the issue's own
 * example of a premium-only feature, daylio-competitive-analysis.md §11.2) — every scenario below
 * is about the digest's *content*, not the gate, so `beforeEach` grants the default user premium
 * once via the dev admin endpoint (M-2, #47) and every existing assertion keeps testing exactly
 * what it did before this ticket. The gate itself gets its own dedicated test at the bottom.
 */

import Database from 'better-sqlite3';
import request from 'supertest';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { DEFAULT_USER_ID } from '../../src/auth/default-user';
import { addDays, weekStart } from '../../src/insights/analysis';
import { serializeDate, todayLocal } from '../../src/db/codecs';
import { bootOnFresh, teardown, type Harness } from '../helpers/app';

let h: Harness;
const server = () => h.app.getHttpServer();

beforeEach(async () => {
  h = await bootOnFresh({ manualEntitlements: true });
  await request(server())
    .post('/billing/admin/grant')
    .send({ user_id: DEFAULT_USER_ID, tier: 'premium' })
    .expect(200);
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

/** Sets `entry_date` directly, the same escape hatch `context-patterns.test.ts` uses to pin
 *  entries to a specific week rather than merely a specific age. */
function backdateTo(entryId: string, date: string): void {
  const db = new Database(h.dbPath);
  db.prepare('UPDATE diary_entries SET entry_date = ? WHERE id = ?').run(date, entryId);
  db.close();
}

// The current calendar week (Monday-first, `analysis.ts#weekStart`'s own convention) and the one
// before it — both always within the engine's 30-day recency window, unlike a hardcoded date would
// be once this suite is run far enough in the future.
const thisMonday = weekStart(todayLocal());
const lastMonday = addDays(thisMonday, -7);
const dateThisWeek = (offset: number) => serializeDate(addDays(thisMonday, offset));
const dateLastWeek = (offset: number) => serializeDate(addDays(lastMonday, offset));

interface Recommendation {
  action_topic: string;
  headline: string;
  sentence: string;
  pattern_ref: string;
}

interface Pattern {
  id: string;
  kind: 'forward' | 'inverse';
  topic: string;
  feeling: string;
  status: 'active' | 'historical';
  recommendation: Recommendation | null;
}

interface InsightsBody {
  patterns: Pattern[];
}

const insights = async (): Promise<InsightsBody> =>
  (await request(server()).get('/insights').expect(200)).body as InsightsBody;

interface DigestHighlight {
  pattern_ref: string;
  kind: 'forward' | 'inverse';
  topic: string;
  feeling: string;
  week_count: number;
  lift: number;
  sentence: string;
}

interface DigestMovement {
  feeling: string;
  current_count: number;
  previous_count: number;
  direction: 'up' | 'down' | 'flat';
  sentence: string;
}

interface DigestBody {
  empty: boolean;
  entry_count: number;
  week?: string;
  highlight?: DigestHighlight;
  recommendation?: Recommendation;
  movement?: DigestMovement;
}

const digest = async (week?: string): Promise<DigestBody> =>
  (
    await request(server())
      .get('/insights/digest')
      .query(week === undefined ? {} : { week })
      .expect(200)
  ).body as DigestBody;

describe('R-2 — weekly digest', () => {
  it('an empty diary reports the empty shape, and nothing else', async () => {
    const body = await digest(dateThisWeek(0));
    expect(body).toEqual({ empty: true, entry_count: 0 });
  });

  it('entries with no qualifying pattern still report entry_count, with every part omitted', async () => {
    // A single entry never clears `MIN_OCCURRENCE_THRESHOLD` (3), so no pattern is ever built for
    // it — the digest still has an honest entry count to report, and nothing to hang a pattern,
    // recommendation or movement figure on.
    await write('Went for a short walk.', ['neutral']);
    await request(server()).get('/insights').expect(200); // triggers recompute (C-06)

    const body = await digest(dateThisWeek(0));
    expect(body.empty).toBe(false);
    expect(body.entry_count).toBe(1);
    expect(body.highlight).toBeUndefined();
    expect(body.recommendation).toBeUndefined();
    expect(body.movement).toBeUndefined();
    expect(body).not.toHaveProperty('highlight');
    expect(body).not.toHaveProperty('recommendation');
    expect(body).not.toHaveProperty('movement');
  });

  it('reports the strongest pattern with activity this week, R-1’s top card, and an honest movement figure', async () => {
    // "reading" ⇒ "calm", forward, present_rate 3/4 vs absent_rate 6/12 ⇒ lift exactly 1.5 (MIN_LIFT,
    // not suppressed — `badgeDirectionFor` only suppresses *below* the minimum). The three calm
    // reading entries land this week, so they are both the pattern's evidence for the highlight and
    // (via `write`'s explicit `feeling_keys`) three of this week's "calm" entries.
    const readingWritten: Written[] = [];
    for (let index = 0; index < 4; index += 1) {
      readingWritten.push(
        await write(`Read a book tonight, chapter ${index}.`, index < 3 ? ['calm'] : ['neutral']),
      );
    }
    readingWritten.forEach((entry) => backdateTo(entry.id, dateThisWeek(1)));

    // "laundry": absent-side bulk with no calm entries at all, so it only dilutes the denominator,
    // never the count under test.
    for (let index = 0; index < 6; index += 1) {
      const entry = await write(`Did the laundry, load ${index}.`, ['neutral']);
      backdateTo(entry.id, dateThisWeek(2));
    }

    // Topic-free padding, all "calm", all last week — six entries a client could count by hand
    // against the digest's own claim.
    for (let index = 0; index < 6; index += 1) {
      const entry = await write(`Felt low again, entry ${index}.`, ['calm']);
      backdateTo(entry.id, dateLastWeek(2));
    }

    const before = await insights();
    const pattern = before.patterns.find((p) => p.topic === 'reading' && p.kind === 'forward')!;
    expect(pattern).toBeDefined();
    expect(pattern.status).toBe('active');
    expect(pattern.recommendation).not.toBeNull();

    const body = await digest(dateThisWeek(3)); // any day in the same week — see the next test

    expect(body.empty).toBe(false);
    expect(body.week).toBe(serializeDate(thisMonday));
    expect(body.entry_count).toBe(4 + 6);

    expect(body.highlight).toEqual({
      pattern_ref: pattern.id,
      kind: 'forward',
      topic: 'reading',
      feeling: 'calm',
      week_count: 3,
      lift: 1.5,
      sentence: expect.stringContaining('reading came up in 3 entries this week.'),
    });

    // Reused, not re-derived (task 1's own requirement): the exact object R-1 already built.
    expect(body.recommendation).toEqual(pattern.recommendation);

    expect(body.movement).toEqual({
      feeling: 'calm',
      current_count: 3,
      previous_count: 6,
      direction: 'down',
      sentence: 'calm appeared in 3 entries this week, down from 6 last week.',
    });
  });

  it('is deterministic: the same data and any date in the same week produce the same digest', async () => {
    for (let index = 0; index < 4; index += 1) {
      const entry = await write(
        `Read a book tonight, chapter ${index}.`,
        index < 3 ? ['calm'] : ['neutral'],
      );
      backdateTo(entry.id, dateThisWeek(1));
    }
    for (let index = 0; index < 6; index += 1) {
      const entry = await write(`Did the laundry, load ${index}.`, ['neutral']);
      backdateTo(entry.id, dateThisWeek(2));
    }
    for (let index = 0; index < 6; index += 1) {
      const entry = await write(`Felt low again, entry ${index}.`, ['calm']);
      backdateTo(entry.id, dateLastWeek(2));
    }
    await insights();

    const monday = await digest(serializeDate(thisMonday));
    const wednesday = await digest(dateThisWeek(3));
    const sunday = await digest(dateThisWeek(6));
    const repeat = await digest(serializeDate(thisMonday));

    expect(wednesday).toEqual(monday);
    expect(sunday).toEqual(monday);
    expect(repeat).toEqual(monday);
  });

  it('reports "flat" without inventing a direction when the count did not move', async () => {
    for (let index = 0; index < 4; index += 1) {
      const entry = await write(
        `Read a book tonight, chapter ${index}.`,
        index < 3 ? ['calm'] : ['neutral'],
      );
      backdateTo(entry.id, dateThisWeek(1));
    }
    for (let index = 0; index < 6; index += 1) {
      const entry = await write(`Did the laundry, load ${index}.`, ['neutral']);
      backdateTo(entry.id, dateThisWeek(2));
    }
    // Exactly three calm entries last week too — matching this week's three from the reading group.
    for (let index = 0; index < 3; index += 1) {
      const entry = await write(`Felt low again, entry ${index}.`, ['calm']);
      backdateTo(entry.id, dateLastWeek(2));
    }
    await insights();

    const body = await digest(serializeDate(thisMonday));
    expect(body.movement).toEqual({
      feeling: 'calm',
      current_count: 3,
      previous_count: 3,
      direction: 'flat',
      sentence: 'calm appeared in 3 entries this week, the same as last week.',
    });
  });

  it('rejects a malformed week with a 422, the same validation status `series` uses', async () => {
    await request(server()).get('/insights/digest').query({ week: 'not-a-date' }).expect(422);
  });

  it('a historical (withdrawn) pattern is never the highlight, even with evidence this week', async () => {
    // Same shape as `worth-trying-recommendations.test.ts`'s withdrawal case: take the qualifying
    // entries away so the pattern withdraws, then confirm the digest has nothing left to highlight.
    const written: Written[] = [];
    for (let index = 0; index < 4; index += 1) {
      written.push(
        await write(`Read a book tonight, chapter ${index}.`, index < 3 ? ['calm'] : ['neutral']),
      );
    }
    written.forEach((entry) => backdateTo(entry.id, dateThisWeek(1)));
    for (let index = 0; index < 6; index += 1) {
      const entry = await write(`Did the laundry, load ${index}.`, ['neutral']);
      backdateTo(entry.id, dateThisWeek(2));
    }
    for (let index = 0; index < 6; index += 1) {
      const entry = await write(`Felt low again, entry ${index}.`, ['calm']);
      backdateTo(entry.id, dateLastWeek(2));
    }
    await insights();

    // Undo the three calm reading entries — the pattern drops below `MIN_OCCURRENCE_THRESHOLD`.
    for (const entry of written.slice(0, 3)) {
      await request(server())
        .patch(`/entries/${entry.id}`)
        .send({ feeling_keys: ['neutral'], version: entry.version })
        .expect(200);
    }
    await insights();

    const body = await digest(serializeDate(thisMonday));
    expect(body.highlight).toBeUndefined();
    expect(body.recommendation).toBeUndefined();
    expect(body.movement).toBeUndefined();
    // The three now-neutral entries are still this week's entries — writing them did not un-happen.
    expect(body.entry_count).toBe(4 + 6);
  });
});

describe('R-2 — weekly digest, gated (M-3, #48)', () => {
  it('answers 402 premium_required for a free account, before ever computing a digest', async () => {
    // A fresh app with no admin grant at all: `EntitlementsService`'s "absence means free" applies
    // to the default user exactly as it would to any other (see that service's own doc comment) —
    // no special case for `SINGLE_USER_MODE`'s fixed user is the point of that rule.
    const free = await bootOnFresh();
    try {
      const res = await request(free.app.getHttpServer())
        .get('/insights/digest')
        .query({ week: dateThisWeek(0) })
        .expect(402);
      expect(res.body).toEqual({ error: 'premium_required' });
    } finally {
      await teardown(free);
    }
  });
});
