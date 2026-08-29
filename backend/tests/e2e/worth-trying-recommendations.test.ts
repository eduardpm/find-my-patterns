/**
 * R-1: "Worth trying" recommendation cards, run against the real API on a fresh diary
 * (`bootOnFresh`) the same way `roadmap-engine.test.ts` proves the rest of the pattern engine — so
 * every assertion here is closed: it names what the response must contain and checks nothing else
 * was invented.
 *
 * The qualifying rule under test is not a new one: a pattern earns a `recommendation` exactly when
 * its own `direction` — decided once, in `badgeDirectionFor` (P0-2/P0-6) — reads `'keep'`. That
 * function's own boundary cases (a null lift, a lift below `MIN_LIFT`, every kind/valence
 * combination) already have full unit coverage in `tests/unit/pure-logic.test.ts`; what this file
 * proves is that `patterns.service.ts#attachRecommendations` wires that decision through to a real
 * `GET /insights` response correctly — composing the right sentence, capping at three, breaking
 * ties the same way the inverse-pattern cap does (C-02), and never leaving a stale reference behind
 * once the pattern it points to is withdrawn (task 4).
 */

import request from 'supertest';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
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

/** Write an entry and settle its feelings, exactly as a client does. */
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

interface Evidence {
  entry_id: string;
  entry_date: string;
}

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
  direction: string;
  lift: number | null;
  occurrence_count: number;
  present_count: number;
  present_total: number;
  absent_count: number;
  absent_total: number;
  comparison_reason: string | null;
  evidence: Evidence[];
  recommendation: Recommendation | null;
}

interface Withdrawal {
  topic: string;
  kind: 'forward' | 'inverse';
}

interface InsightsBody {
  patterns: Pattern[];
  withdrawals: Withdrawal[];
}

const insights = async (): Promise<InsightsBody> =>
  (await request(server()).get('/insights').expect(200)).body as InsightsBody;

const find = (
  body: InsightsBody,
  topic: string,
  kind: 'forward' | 'inverse',
): Pattern | undefined =>
  body.patterns.find((pattern) => pattern.topic === topic && pattern.kind === kind);

describe('R-1 — "Worth trying" recommendations', () => {
  it('emits a recommendation for a qualifying inverse pattern — the topic looks protective', async () => {
    // 4 entries mention exercise, only 1 of them anxious; 6 do not, 4 of them anxious. Anxious is
    // much likelier without exercise — the issue's own worked example, "without walking →
    // anxious", with a different topic word.
    for (let index = 0; index < 4; index += 1) {
      await write(`Went to the gym, session ${index}.`, index === 0 ? ['anxious'] : ['neutral']);
    }
    for (let index = 0; index < 6; index += 1) {
      await write(
        `Stayed in for the evening, night ${index}.`,
        index < 4 ? ['anxious'] : ['neutral'],
      );
    }

    const body = await insights();
    const pattern = find(body, 'exercise', 'inverse')!;
    expect(pattern).toBeDefined();
    expect(pattern.direction).toBe('keep');
    expect(pattern.lift).not.toBeNull();

    const rec = pattern.recommendation;
    expect(rec).not.toBeNull();
    expect(rec!.pattern_ref).toBe(pattern.id);
    expect(rec!.action_topic).toBe('exercise');
    expect(rec!.headline).toBe('More exercise days');
    // R-0: every number the card claims is a number this same pattern already shows.
    expect(rec!.sentence).toContain(`${pattern.present_count} of ${pattern.present_total}`);
    expect(rec!.sentence).toContain(`${pattern.absent_count} of ${pattern.absent_total}`);
    expect(rec!.sentence).toContain(`${pattern.lift!.toFixed(1)}×`);
    expect(rec!.sentence.startsWith('On days without exercise,')).toBe(true);
    expect(rec!.sentence).toContain('may help');
    // Task 3: association, never causation.
    expect(rec!.sentence).not.toMatch(/will fix|cure|prevent|guarantee|protects|causes|because/i);
  });

  it('emits a recommendation for a qualifying forward pattern — keep doing what already works', async () => {
    for (let index = 0; index < 4; index += 1) {
      await write(`Read a book tonight, chapter ${index}.`, index < 3 ? ['calm'] : ['neutral']);
    }
    for (let index = 0; index < 6; index += 1) {
      await write(`Did the laundry, load ${index}.`, index === 0 ? ['calm'] : ['neutral']);
    }

    const body = await insights();
    const pattern = find(body, 'reading', 'forward')!;
    expect(pattern).toBeDefined();
    expect(pattern.direction).toBe('keep');
    expect(pattern.lift).not.toBeNull();

    const rec = pattern.recommendation;
    expect(rec).not.toBeNull();
    expect(rec!.pattern_ref).toBe(pattern.id);
    expect(rec!.headline).toBe('Keep doing reading');
    expect(rec!.sentence.startsWith('On days with reading,')).toBe(true);
    expect(rec!.sentence).toContain(`${pattern.present_count} of ${pattern.present_total}`);
    expect(rec!.sentence).toContain(`${pattern.absent_count} of ${pattern.absent_total}`);
    expect(rec!.sentence).toContain('Keep doing reading');
    expect(rec!.sentence).not.toMatch(/will fix|cure|prevent|guarantee|protects|causes|because/i);
  });

  it('excludes a forward pattern whose feeling is negative — direction is "change", not "keep"', async () => {
    // Same shape as the qualifying forward case above, deliberately: a strong, well-defined lift,
    // just paired with a negative feeling. The only thing that should change the outcome is
    // valence, and this proves it does.
    for (let index = 0; index < 4; index += 1) {
      await write(
        `Studied for the exam, session ${index}.`,
        index < 3 ? ['stressed'] : ['neutral'],
      );
    }
    for (let index = 0; index < 6; index += 1) {
      await write(
        `Took the dog for a walk, round ${index}.`,
        index === 0 ? ['stressed'] : ['neutral'],
      );
    }

    const body = await insights();
    const pattern = find(body, 'study', 'forward')!;
    expect(pattern).toBeDefined();
    expect(pattern.lift).not.toBeNull();
    expect(pattern.direction).toBe('change');
    expect(pattern.recommendation).toBeNull();
  });

  it('excludes an inverse pattern whose lift is undefined — no comparison number to cite (P0-6)', async () => {
    // Every entry mentioning meditation is neutral; sad only ever happens without it. That is the
    // strongest possible inverse signal a diary can hold, and precisely the case A3-02 forbids
    // stating as a ratio: the "with" side's rate is a division by zero, so `lift` stays null and
    // `badgeDirectionFor` withholds the badge (P0-6) — no badge means no recommendation either.
    for (let index = 0; index < 4; index += 1) {
      await write(`Did some meditation, session ${index}.`, ['neutral']);
    }
    for (let index = 0; index < 6; index += 1) {
      await write(`Spent the evening alone, night ${index}.`, index < 4 ? ['sad'] : ['neutral']);
    }

    const body = await insights();
    const pattern = find(body, 'meditation', 'inverse')!;
    expect(pattern).toBeDefined();
    expect(pattern.lift).toBeNull();
    expect(pattern.comparison_reason).toBe('no_absent_occurrences');
    expect(pattern.direction).toBe('none');
    expect(pattern.recommendation).toBeNull();
  });

  it('caps "Worth trying" cards at three, ranked by lift, tiebroken on topic name (C-02)', async () => {
    // A shared backdrop of "sad" entries that mention no topic at all — the common comparison
    // every one of the four topics below is read against.
    for (let index = 0; index < 20; index += 1) {
      await write(`Felt low again, entry ${index}.`, ['sad']);
    }

    // Four topics, symmetric by construction: each contributes exactly one "sad" entry of its own
    // (so every other topic's "without me" bucket sees the same sad count), and each has an
    // identical 4-entry "mentions the topic" group with exactly one sad entry in it. The four
    // inverse patterns this produces are therefore tied on lift *and* occurrence count — which of
    // three of the four gets a card is decided purely by topic name, alphabetically, never by the
    // random `id` two clients could disagree about.
    const topics: Array<[topic: string, prefix: string]> = [
      ['commute', 'Sat in traffic on the commute, day'],
      ['meditation', 'Did some meditation, session'],
      ['music', 'Listened to music on the drive, day'],
      ['therapy', 'Went to therapy, session'],
    ];
    for (const [, prefix] of topics) {
      for (let index = 0; index < 4; index += 1) {
        await write(`${prefix} ${index}.`, index === 0 ? ['sad'] : ['neutral']);
      }
    }

    const body = await insights();
    const inversePatterns = topics.map(([topic]) => find(body, topic, 'inverse')!);
    for (const pattern of inversePatterns) {
      expect(pattern).toBeDefined();
      expect(pattern.direction).toBe('keep');
      expect(pattern.lift).not.toBeNull();
    }
    const lifts = new Set(inversePatterns.map((pattern) => pattern.lift));
    expect(lifts.size).toBe(1); // confirms the tie the tiebreak has to resolve

    const recommended = body.patterns.filter((pattern) => pattern.recommendation !== null);
    expect(recommended).toHaveLength(3);
    expect(recommended.map((pattern) => pattern.topic).sort()).toEqual([
      'commute',
      'meditation',
      'music',
    ]);
    expect(find(body, 'therapy', 'inverse')!.recommendation).toBeNull();
  });

  it('a recommendation disappears with the pattern it was derived from — derived, not cached (task 4)', async () => {
    for (let index = 0; index < 4; index += 1) {
      await write(`Went to the gym, session ${index}.`, index === 0 ? ['anxious'] : ['neutral']);
    }
    for (let index = 0; index < 6; index += 1) {
      await write(
        `Stayed in for the evening, night ${index}.`,
        index < 4 ? ['anxious'] : ['neutral'],
      );
    }

    const before = await insights();
    const pattern = find(before, 'exercise', 'inverse')!;
    expect(pattern.recommendation).not.toBeNull();
    const withdrawnId = pattern.id;

    // Take the evidence away, the same way `roadmap-engine.test.ts` withdraws an inverse pattern:
    // the "anxious without exercise" entries stop being anxious, dropping the pattern's own
    // occurrence count below the minimum and withdrawing it entirely on the next recompute.
    for (const entry of pattern.evidence) {
      const listed = (await request(server()).get(`/entries?date=${entry.entry_date}`).expect(200))
        .body.entries as Array<{ id: string; version: number }>;
      const target = listed.find((row) => row.id === entry.entry_id)!;
      await request(server())
        .patch(`/entries/${target.id}`)
        .send({ feeling_keys: ['neutral'], version: target.version })
        .expect(200);
    }

    const after = await insights();
    expect(find(after, 'exercise', 'inverse')).toBeUndefined();
    expect(
      after.withdrawals.some((row) => row.topic === 'exercise' && row.kind === 'inverse'),
    ).toBe(true);
    // No surviving pattern points back at the one that was just withdrawn — there is no separate
    // store for a recommendation to go stale in (it is computed fresh from the row on every read).
    expect(after.patterns.every((row) => row.recommendation?.pattern_ref !== withdrawnId)).toBe(
      true,
    );
  });
});
