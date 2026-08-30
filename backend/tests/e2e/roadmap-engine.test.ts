/**
 * The roadmap's success criteria, run against a real diary through the real API.
 *
 * Every scenario below starts from an empty diary and writes entries the way a user would, so the
 * assertions can be *closed*: they name what must be there and check that nothing else was
 * invented. No model runs — each number is one a person could work out by hand from the entries
 * above it, which is the whole claim the product makes.
 */

import Database from 'better-sqlite3';
import request from 'supertest';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { DEFAULT_USER_ID } from '../../src/auth/default-user';
import { MIN_OCCURRENCE_THRESHOLD, RECENCY_WINDOW_DAYS } from '../../src/insights/constants';
import { bootOnFresh, teardown, type Harness } from '../helpers/app';

let h: Harness;
const server = () => h.app.getHttpServer();

beforeEach(async () => {
  // `manualEntitlements: true` costs nothing for the tests that don't use it — it only reaches
  // `POST /billing/admin/grant`, which I3-SC1 below needs (M-3, #48): a free-tier `GET /insights`
  // no longer returns `status: 'historical'` rows at all, and I3-SC1 is specifically about that
  // label existing and being correct, not about the free/paid boundary a different suite covers.
  h = await bootOnFresh({ manualEntitlements: true });
});
afterEach(async () => {
  await teardown(h);
});

interface Written {
  id: string;
  version: number;
}

/** Write an entry and settle its feelings, exactly as a client does. */
async function write(text: string, feelings: string[], daysAgo = 0): Promise<Written> {
  const created = (
    await request(server()).post('/entries').send({ mode: 'freeform', raw_text: text }).expect(201)
  ).body as { id: string; version: number };

  const confirmed = (
    await request(server())
      .patch(`/entries/${created.id}`)
      .send({ feeling_keys: feelings, version: created.version })
      .expect(200)
  ).body as { id: string; version: number };

  if (daysAgo > 0) backdate(created.id, daysAgo);
  return confirmed;
}

const dateDaysAgo = (daysAgo: number): string =>
  new Date(Date.now() - daysAgo * 86_400_000).toISOString().slice(0, 10);

/** The API files every entry under today by design; asking what "recent" means requires going round it. */
function backdate(entryId: string, daysAgo: number): void {
  const db = new Database(h.dbPath);
  const when = new Date(Date.now() - daysAgo * 86_400_000).toISOString().slice(0, 10);
  db.prepare('UPDATE diary_entries SET entry_date = ? WHERE id = ?').run(when, entryId);
  db.close();
}

/**
 * The API writes `created_at` at request time, so an hourly-bucket test has to reach around it the
 * same way `backdate` reaches around `entry_date` — the calendar date is left untouched, only the
 * wall-clock hour moves, and to an exact `HH:00:00` so a test can name the block it expects.
 */
function setHour(entryId: string, hour: number): void {
  const db = new Database(h.dbPath);
  const row = db.prepare('SELECT created_at FROM diary_entries WHERE id = ?').get(entryId) as {
    created_at: string;
  };
  const datePart = row.created_at.slice(0, 10);
  const time = `${String(hour).padStart(2, '0')}:00:00.000000`;
  db.prepare('UPDATE diary_entries SET created_at = ? WHERE id = ?').run(
    `${datePart} ${time}`,
    entryId,
  );
  db.close();
}

interface Evidence {
  entry_id: string;
  entry_date: string;
  raw_text: string;
  feeling_keys: string[];
  feeling_source: string;
}

interface Pattern {
  id: string;
  kind: 'forward' | 'inverse';
  topic: string;
  feeling: string;
  status: 'active' | 'historical';
  occurrence_count: number;
  lifetime_count: number;
  direction: string;
  narrative_text: string;
  lift: number | null;
  comparison_reason: string | null;
  comparison_note: string | null;
  is_strong: boolean;
  present_count: number;
  present_total: number;
  absent_count: number;
  absent_total: number;
  base_rate: number;
  days_since_last_occurrence: number | null;
  historical_note: string | null;
  confounders: Array<{ topic: string; note: string; inseparable: boolean }>;
  evidence: Evidence[];
}

interface Withdrawal {
  topic: string;
  feeling: string;
  kind: 'forward' | 'inverse';
  previous_count: number;
  new_count: number;
  reason: string;
  detail_text: string;
  is_new: boolean;
}

interface InsightsBody {
  patterns: Pattern[];
  withdrawals: Withdrawal[];
  new_withdrawal_count: number;
  insufficient_data: boolean;
  constants: Record<string, number>;
}

const insights = async (): Promise<InsightsBody> =>
  (await request(server()).get('/insights').expect(200)).body as InsightsBody;

const find = (body: InsightsBody, topic: string, kind = 'forward'): Pattern | undefined =>
  body.patterns.find((pattern) => pattern.topic === topic && pattern.kind === kind);

// -----------------------------------------------------------------------------------------------
// A1 — the evidence trail
// -----------------------------------------------------------------------------------------------

describe('A1 — every pattern opens onto the entries that produced it', () => {
  it('returns exactly the supporting entries, oldest first — A1-SC1', async () => {
    const written = [
      await write('Tea in the garden.', ['calm'], 4),
      await write('Tea on the balcony.', ['calm'], 3),
      await write('A pot of tea and a book.', ['calm'], 2),
    ];
    // Something else in the diary, so the comparison group is not empty and the pattern is real
    // rather than an artefact of a three-entry diary.
    for (let index = 0; index < 6; index += 1) {
      await write(`A long day at work, number ${index}.`, ['stressed'], index + 1);
    }

    const tea = find(await insights(), 'tea')!;
    expect(tea.occurrence_count).toBe(3);
    // A1-02: the trail and the count are the same fact, so they cannot disagree.
    expect(tea.evidence).toHaveLength(tea.occurrence_count);
    expect(tea.evidence.map((entry) => entry.entry_id).sort()).toEqual(
      written.map((entry) => entry.id).sort(),
    );
    // A1-04: oldest first.
    const dates = tea.evidence.map((entry) => entry.entry_date);
    expect([...dates].sort()).toEqual(dates);
    // A1-09: enough to scan without opening each entry.
    expect(tea.evidence[0].raw_text).toBeTruthy();
    expect(tea.evidence[0].feeling_keys).toContain('calm');
  });

  it('drops an entry from the trail once it no longer supports the pattern — A1-SC2', async () => {
    const written = [
      await write('Tea in the garden.', ['calm'], 4),
      await write('Tea on the balcony.', ['calm'], 3),
      await write('A pot of tea and a book.', ['calm'], 2),
      await write('Yet more tea.', ['calm'], 1),
    ];
    for (let index = 0; index < 6; index += 1) {
      await write(`A long day at work, number ${index}.`, ['stressed'], index + 1);
    }

    expect(find(await insights(), 'tea')!.evidence).toHaveLength(4);

    await request(server())
      .patch(`/entries/${written[0].id}`)
      .send({ raw_text: 'A quiet morning with water.', version: written[0].version })
      .expect(200);

    const after = find(await insights(), 'tea')!;
    expect(after.occurrence_count).toBe(3);
    expect(after.evidence).toHaveLength(3);
    expect(after.evidence.map((entry) => entry.entry_id)).not.toContain(written[0].id);
  });

  it('never admits an unconfirmed entry as evidence — A1-SC3', async () => {
    for (let index = 0; index < 3; index += 1) {
      await write(`Tea number ${index}.`, ['calm'], index + 1);
    }
    for (let index = 0; index < 6; index += 1) {
      await write(`A long day at work, number ${index}.`, ['stressed'], index + 1);
    }

    // Written but never confirmed: the analyser's opinion is not the user's.
    const unconfirmed = (
      await request(server())
        .post('/entries')
        .send({ mode: 'freeform', raw_text: 'One more pot of tea.' })
        .expect(201)
    ).body as { id: string };

    const tea = find(await insights(), 'tea')!;
    expect(tea.occurrence_count).toBe(3);
    expect(tea.evidence.map((entry) => entry.entry_id)).not.toContain(unconfirmed.id);
    for (const entry of tea.evidence) {
      expect(['confirmed', 'overridden']).toContain(entry.feeling_source);
    }
  });
});

// -----------------------------------------------------------------------------------------------
// A2 — withdrawals
// -----------------------------------------------------------------------------------------------

describe('A2 — a pattern that goes away says why', () => {
  async function threeTeas(): Promise<Written[]> {
    const written = [
      await write('Tea in the garden.', ['calm'], 3),
      await write('Tea on the balcony.', ['calm'], 2),
      await write('A pot of tea and a book.', ['calm'], 1),
    ];
    for (let index = 0; index < 6; index += 1) {
      await write(`A long day at work, number ${index}.`, ['stressed'], index + 1);
    }
    return written;
  }

  it('states the previous count, the new one, and the reason — A2-SC1', async () => {
    const written = await threeTeas();
    expect(find(await insights(), 'tea')).toBeDefined();

    await request(server())
      .patch(`/entries/${written[0].id}`)
      .send({ raw_text: 'A quiet morning with water.', version: written[0].version })
      .expect(200);

    const body = await insights();
    expect(find(body, 'tea')).toBeUndefined();

    const withdrawal = body.withdrawals.find(
      (row) => row.topic === 'tea' && row.kind === 'forward',
    )!;
    expect(withdrawal).toBeDefined();
    expect(withdrawal.previous_count).toBe(3);
    expect(withdrawal.new_count).toBe(2);
    // The count genuinely fell, so this is the count reason and not the lift one (A2-02).
    expect(withdrawal.reason).toBe('below_threshold');
    expect(withdrawal.detail_text).toContain('3');
    expect(withdrawal.detail_text).toContain('2');
    expect(withdrawal.detail_text).toContain(String(MIN_OCCURRENCE_THRESHOLD));
    // A2-07: it is counted as unseen until the user says otherwise.
    expect(withdrawal.is_new).toBe(true);
    expect(body.new_withdrawal_count).toBeGreaterThanOrEqual(1);
  });

  it('never shows the same pattern as withdrawn and active at once — A2-SC2', async () => {
    const written = await threeTeas();
    expect(find(await insights(), 'tea')).toBeDefined();
    const edited = (
      await request(server())
        .patch(`/entries/${written[0].id}`)
        .send({ raw_text: 'A quiet morning with water.', version: written[0].version })
        .expect(200)
    ).body as { version: number };

    expect(
      (await insights()).withdrawals.some((row) => row.topic === 'tea' && row.kind === 'forward'),
    ).toBe(true);

    await request(server())
      .patch(`/entries/${written[0].id}`)
      .send({ raw_text: 'Tea in the garden after all.', version: edited.version })
      .expect(200);

    const body = await insights();
    expect(find(body, 'tea')).toBeDefined();
    // Superseded rather than deleted, and never returned beside the active pattern.
    expect(body.withdrawals.some((row) => row.topic === 'tea' && row.kind === 'forward')).toBe(
      false,
    );
  });

  it('stops counting notices as new once the user has acknowledged them — A2-07', async () => {
    const written = await threeTeas();
    expect(find(await insights(), 'tea')).toBeDefined();
    await request(server())
      .patch(`/entries/${written[0].id}`)
      .send({ raw_text: 'A quiet morning with water.', version: written[0].version })
      .expect(200);
    expect((await insights()).new_withdrawal_count).toBeGreaterThan(0);

    await request(server()).post('/insights/withdrawals/acknowledge').expect(204);

    const body = await insights();
    // Still listed — the notice does not disappear because it was read (A2-03).
    expect(body.withdrawals.some((row) => row.topic === 'tea' && row.kind === 'forward')).toBe(
      true,
    );
    expect(body.new_withdrawal_count).toBe(0);
  });

  it('states an inverse withdrawal in its own terms, not the forward pair\u2019s', async () => {
    // An inverse pattern is a claim about the entries that do *not* mention the topic. Reporting
    // its withdrawal with the forward count would print "now 0" on every one of them — true of a
    // pair the user was never shown, and false of the one that went away.
    for (let index = 0; index < 4; index += 1) {
      await write(`Went to the gym, session ${index}.`, ['content'], index + 1);
    }
    for (let index = 0; index < 6; index += 1) {
      await write(`Sat at the desk all evening, number ${index}.`, ['sad'], index + 5);
    }

    const before = await insights();
    const inverse = find(before, 'exercise', 'inverse')!;
    expect(inverse).toBeDefined();

    // Take the evidence away: the "sad without exercise" entries stop being sad.
    for (const entry of inverse.evidence.slice(0, 4)) {
      const listed = (await request(server()).get(`/entries?date=${entry.entry_date}`).expect(200))
        .body.entries as Array<{ id: string; version: number }>;
      const target = listed.find((row) => row.id === entry.entry_id)!;
      await request(server())
        .patch(`/entries/${target.id}`)
        .send({ feeling_keys: ['content'], version: target.version })
        .expect(200);
    }

    const withdrawal = (await insights()).withdrawals.find(
      (row) => row.topic === 'exercise' && row.kind === 'inverse',
    )!;
    expect(withdrawal).toBeDefined();
    expect(withdrawal.detail_text).toContain('without exercise');
    // Whatever the notice says about the count, it must agree with the count it prints. A notice
    // reading "now 12 — below the minimum of 3" is the app contradicting itself in one sentence.
    if (withdrawal.reason === 'below_lift') {
      expect(withdrawal.new_count).toBeGreaterThanOrEqual(MIN_OCCURRENCE_THRESHOLD);
    } else {
      expect(withdrawal.new_count).toBeLessThan(MIN_OCCURRENCE_THRESHOLD);
      expect(withdrawal.detail_text).toContain(String(withdrawal.new_count));
    }
  });

  it('separates "the evidence thinned out" from "the association weakened" — A2-02', async () => {
    // Two different things happen to a pattern, and a client can only tell them apart if the
    // *code* distinguishes them — `detail_text` is prose, not something to branch on.
    for (let index = 0; index < 4; index += 1) {
      await write(`Went to the gym, session ${index}.`, ['content'], index + 1);
    }
    for (let index = 0; index < 6; index += 1) {
      await write(`Sat at the desk all evening, number ${index}.`, ['sad'], index + 5);
    }
    const inverse = find(await insights(), 'exercise', 'inverse')!;
    expect(inverse).toBeDefined();

    // Make the gym days sad too. The inverse pattern keeps every one of its occurrences; what it
    // loses is the contrast that made them mean anything.
    for (let index = 0; index < 4; index += 1) {
      const listed = (await request(server()).get(`/entries?date=${dateDaysAgo(index + 1)}`)).body
        .entries as Array<{ id: string; version: number; raw_text: string }>;
      const gym = listed.find((row) => row.raw_text.includes('gym'))!;
      await request(server())
        .patch(`/entries/${gym.id}`)
        .send({ feeling_keys: ['sad'], version: gym.version })
        .expect(200);
    }

    const withdrawal = (await insights()).withdrawals.find(
      (row) => row.topic === 'exercise' && row.kind === 'inverse',
    )!;
    expect(withdrawal).toBeDefined();
    expect(withdrawal.reason).toBe('below_lift');
    // The count is untouched, which is exactly why `below_threshold` would have been a lie.
    expect(withdrawal.new_count).toBeGreaterThanOrEqual(MIN_OCCURRENCE_THRESHOLD);
    expect(withdrawal.detail_text).toContain('still');
    expect(withdrawal.detail_text).not.toContain(
      `below the minimum of ${MIN_OCCURRENCE_THRESHOLD}`,
    );
  });

  it('carries no diary text — A2-08', async () => {
    const written = await threeTeas();
    expect(find(await insights(), 'tea')).toBeDefined();
    await request(server())
      .patch(`/entries/${written[0].id}`)
      .send({ raw_text: 'A quiet morning with water.', version: written[0].version })
      .expect(200);

    const withdrawal = (await insights()).withdrawals.find(
      (row) => row.topic === 'tea' && row.kind === 'forward',
    )!;
    expect(withdrawal.detail_text).not.toContain('garden');
    expect(withdrawal.detail_text).not.toContain('balcony');
  });
});

// -----------------------------------------------------------------------------------------------
// I3 — recency
// -----------------------------------------------------------------------------------------------

describe('I3 — the count means what the sentence says', () => {
  it('labels a pattern historical when the window is thin but the history is not — I3-SC1', async () => {
    await request(server())
      .post('/billing/admin/grant')
      .send({ user_id: DEFAULT_USER_ID, tier: 'premium' })
      .expect(200);
    for (let index = 0; index < 3; index += 1) {
      await write(`Tea number ${index}.`, ['calm'], 90 + index);
    }
    for (let index = 0; index < 2; index += 1) {
      await write(`More tea, number ${index}.`, ['calm'], index + 1);
    }
    for (let index = 0; index < 6; index += 1) {
      await write(`A long day at work, number ${index}.`, ['stressed'], index + 1);
    }

    const tea = find(await insights(), 'tea')!;
    expect(tea.status).toBe('historical');
    expect(tea.occurrence_count).toBe(2);
    expect(tea.lifetime_count).toBe(5);
    expect(tea.narrative_text).toContain(`in the last ${RECENCY_WINDOW_DAYS} days`);
    expect(tea.narrative_text).not.toMatch(/\brecent\b/i);
    // I3-07.
    expect(tea.historical_note).toContain('across your whole diary');
  });

  it('labels a pattern active when the window carries it — I3-SC2', async () => {
    for (let index = 0; index < 3; index += 1) {
      await write(`Tea number ${index}.`, ['calm'], index + 1);
    }
    for (let index = 0; index < 6; index += 1) {
      await write(`A long day at work, number ${index}.`, ['stressed'], index + 1);
    }

    const tea = find(await insights(), 'tea')!;
    expect(tea.status).toBe('active');
    expect(tea.occurrence_count).toBe(3);
    expect(tea.historical_note).toBeNull();
  });

  it('serves the window length rather than making clients know it — I3-01', async () => {
    const body = await insights();
    expect(body.constants.recency_window_days).toBe(RECENCY_WINDOW_DAYS);
    expect(body.constants.min_occurrence_threshold).toBe(MIN_OCCURRENCE_THRESHOLD);
    expect(body.constants.min_lift).toBeGreaterThan(1);
  });
});

// -----------------------------------------------------------------------------------------------
// A3 / I1 / I2 — strength, the other direction, and entanglement
// -----------------------------------------------------------------------------------------------

describe('A3 — a pattern states how strong it is', () => {
  it('shows both rates, the base rate, and the lift', async () => {
    // 4 walking entries, all energised. 8 others, one energised.
    for (let index = 0; index < 4; index += 1) {
      await write(`A walk by the river, number ${index}.`, ['energised'], index + 1);
    }
    for (let index = 0; index < 7; index += 1) {
      await write(`A long day at work, number ${index}.`, ['stressed'], index + 1);
    }
    await write('Work went well today.', ['energised'], 8);

    const walking = find(await insights(), 'walking')!;
    expect(walking.present_count).toBe(4);
    expect(walking.present_total).toBe(4);
    expect(walking.absent_count).toBe(1);
    expect(walking.absent_total).toBe(8);
    expect(walking.lift).toBeCloseTo(8, 5);
    expect(walking.base_rate).toBeCloseTo(5 / 12, 5);
    expect(walking.narrative_text).toContain('4 of 4');
    expect(walking.narrative_text).toContain('1 of 8');
  });

  it('says so instead of inventing a ratio when there is nothing to compare — A3-SC3', async () => {
    for (let index = 0; index < 4; index += 1) {
      await write(`Tea number ${index}.`, ['calm'], index + 1);
    }

    const tea = find(await insights(), 'tea')!;
    expect(tea.lift).toBeNull();
    expect(tea.comparison_reason).toBe('insufficient_comparison');
    expect(tea.comparison_note).toContain('Not enough entries');
    expect(tea.is_strong).toBe(false);
    // P0-6: a card that cannot state a ratio must not carry advice built on one either.
    expect(tea.direction).toBe('none');
  });

  // P0-6 — the exact bug reported live: "Work → anxious" showed `LIFT —` (0 of 7 entries without
  // work, a division by zero) and still carried a red CONSIDER CHANGING badge. Reproduced here as
  // the zero-cell case (`no_absent_occurrences`), distinct from A3-SC3's too-small comparison
  // group above: this one has plenty of entries on the other side, just none with the feeling.
  it('never badges a card whose feeling never once occurred without the topic — P0-6', async () => {
    for (let index = 0; index < 4; index += 1) {
      await write(`Work again, number ${index}.`, ['anxious'], index + 1);
    }
    for (let index = 0; index < 5; index += 1) {
      await write(`A quiet evening off, number ${index}.`, ['content'], index + 5);
    }

    const work = find(await insights(), 'work')!;
    expect(work.present_count).toBe(4);
    expect(work.absent_count).toBe(0);
    expect(work.absent_total).toBeGreaterThanOrEqual(3);
    expect(work.lift).toBeNull();
    expect(work.comparison_reason).toBe('no_absent_occurrences');
    // Without the fix this would read 'change' — anxious is a negative feeling on the forward
    // side — despite the card's own "LIFT —" saying there is no ratio to back that advice.
    expect(work.direction).toBe('none');
  });
});

describe('I1 — what helps, not only what hurts', () => {
  it('surfaces the absent side as its own card with its own numbers — I1-SC1', async () => {
    // Exercise days are fine; the days without it are the low ones.
    for (let index = 0; index < 4; index += 1) {
      await write(`Went to the gym, session ${index}.`, ['content'], index + 1);
    }
    // One exercise day that was sad too (P0-6): without at least one entry on this side, the
    // ratio behind the inverse pattern is a division by zero — exactly the undefined-lift case
    // P0-6 withholds a badge for — which would make this a test of that behaviour instead of
    // I1-05's keep/change mapping, the thing this test is actually about.
    await write('Went to the gym anyway, still low.', ['sad'], 5);
    for (let index = 0; index < 6; index += 1) {
      await write(`Sat at the desk all evening, number ${index}.`, ['sad'], index + 6);
    }

    const body = await insights();
    const inverse = find(body, 'exercise', 'inverse');
    expect(inverse).toBeDefined();
    expect(inverse!.feeling).toBe('sad');
    expect(inverse!.present_count).toBe(6);
    expect(inverse!.present_total).toBe(6);
    expect(inverse!.narrative_text).toContain('without exercise');
    // I1-05: the absence coincides with a bad feeling, so the topic itself is worth keeping.
    expect(inverse!.direction).toBe('keep');
    // I1-07: association, never protection.
    expect(inverse!.narrative_text).not.toMatch(/protect|prevent|because/i);
    // The forward pair (exercise → sad) is correctly absent.
    expect(
      body.patterns.some(
        (p) => p.kind === 'forward' && p.topic === 'exercise' && p.feeling === 'sad',
      ),
    ).toBe(false);
  });
});

describe('I2 — two topics that always travel together', () => {
  it('annotates the pattern with the split rather than hiding it — I2-SC1', async () => {
    // Coffee accompanies every work entry but one.
    for (let index = 0; index < 9; index += 1) {
      await write(`Coffee at the desk, work again, number ${index}.`, ['anxious'], index + 1);
    }
    // Phrased without the word, because the extractor still counts a negated mention — the one
    // entry that separates the two topics has to genuinely not mention one of them.
    await write('Work all morning, only water today.', ['anxious'], 10);
    for (let index = 0; index < 6; index += 1) {
      await write(`A walk by the river, number ${index}.`, ['content'], index + 1);
    }

    const work = find(await insights(), 'work')!;
    expect(work).toBeDefined();
    const note = work.confounders.find((row) => row.topic === 'coffee')!;
    expect(note).toBeDefined();
    expect(note.note).toContain('9 of 10');
    expect(note.note).toContain('90%');
    expect(note.inseparable).toBe(false);
  });
});

// -----------------------------------------------------------------------------------------------
// I4 / I5 / I6
// -----------------------------------------------------------------------------------------------

describe('I4 — the pattern echoes at the moment it is lived', () => {
  it('echoes an active pattern for a saved entry, and stores nothing in its text — I4-SC1', async () => {
    for (let index = 0; index < 4; index += 1) {
      await write(`Espresso at the desk, number ${index}.`, ['anxious'], index + 1);
    }
    for (let index = 0; index < 7; index += 1) {
      await write(`A walk by the river, number ${index}.`, ['content'], index + 1);
    }
    await insights(); // patterns are recomputed on read, and only there (C-06)

    const text = 'One more espresso before the call.';
    const written = await write(text, ['anxious']);

    const body = (await request(server()).get(`/entries/${written.id}/echo`).expect(200)).body as {
      echoes: Array<{ topic: string; narrative_text: string; occurrence_count: number }>;
    };
    expect(body.echoes.map((echo) => echo.topic)).toContain('coffee');
    // I4-08: the entry is exactly what the user wrote.
    const stored = (await request(server()).get(`/entries/${written.id}`).expect(200)).body as {
      raw_text: string;
    };
    expect(stored.raw_text).toBe(text);
  });

  it('says nothing at all when the entry has no pattern behind it — I4-09', async () => {
    const written = await write('A quiet afternoon reading in the garden.', ['calm']);
    const body = (await request(server()).get(`/entries/${written.id}/echo`).expect(200)).body as {
      echoes: unknown[];
    };
    expect(body.echoes).toEqual([]);
  });
});

describe('I5 — when am I worst', () => {
  it('reports a bucket below the minimum as insufficient rather than as a number — I5-SC2', async () => {
    await write('A single Monday entry.', ['sad'], 0);

    const body = (await request(server()).get('/insights/when').expect(200)).body as {
      weekdays: Array<{
        key: string;
        entry_count: number;
        average_valence: number | null;
        sufficient: boolean;
      }>;
      times_of_day: Array<{ sufficient: boolean; average_valence: number | null }>;
      min_bucket_entries: number;
    };

    for (const bucket of body.weekdays) {
      if (bucket.entry_count < body.min_bucket_entries) {
        expect(bucket.sufficient).toBe(false);
        expect(bucket.average_valence).toBeNull();
      }
    }
  });

  it('is identical across two reads — I5-SC3', async () => {
    for (let index = 0; index < 5; index += 1) {
      await write(`A long day at work, number ${index}.`, ['stressed'], index + 1);
    }
    const first = (await request(server()).get('/insights/when').expect(200)).body as unknown;
    const second = (await request(server()).get('/insights/when').expect(200)).body as unknown;
    expect(second).toEqual(first);
  });

  interface WhenBucketBody {
    key: string;
    label: string;
    entry_count: number;
    average_valence: number | null;
    sufficient: boolean;
  }

  interface WhenBody {
    weekdays: WhenBucketBody[];
    times_of_day: WhenBucketBody[];
    hourly: WhenBucketBody[];
    best_weekday: string | null;
    worst_weekday: string | null;
    best_time_of_day: string | null;
    worst_time_of_day: string | null;
    best_hour: string | null;
    worst_hour: string | null;
    busiest_time_of_day: string | null;
    min_bucket_entries: number;
  }

  describe('hourly heat strip — CH-5', () => {
    it('sorts entries into their 2-hour block, boundary-exclusive at the top', async () => {
      const inBlock: Written[] = [];
      for (let index = 0; index < 3; index += 1) {
        inBlock.push(await write(`Evening entry ${index}.`, ['content']));
      }
      for (const entry of inBlock) setHour(entry.id, 19); // 18:00-20:00

      const nextBlock = await write('Just past the boundary.', ['content']);
      setHour(nextBlock.id, 20); // 20:00-22:00

      const body = (await request(server()).get('/insights/when').expect(200)).body as WhenBody;

      const eighteen = body.hourly.find((bucket) => bucket.key === '18')!;
      expect(eighteen.label).toBe('18:00–20:00');
      expect(eighteen.entry_count).toBe(3);
      expect(eighteen.sufficient).toBe(true);

      const twenty = body.hourly.find((bucket) => bucket.key === '20')!;
      expect(twenty.entry_count).toBe(1);
      expect(twenty.sufficient).toBe(false);

      expect(body.hourly).toHaveLength(12);
    });

    it('reuses MIN_BUCKET_ENTRIES: an hourly bucket below it reports no average', async () => {
      const thin = await write('One late entry.', ['sad']);
      setHour(thin.id, 22);

      const body = (await request(server()).get('/insights/when').expect(200)).body as WhenBody;
      const bucket = body.hourly.find((candidate) => candidate.key === '22')!;

      expect(bucket.entry_count).toBeLessThan(body.min_bucket_entries);
      expect(bucket.sufficient).toBe(false);
      expect(bucket.average_valence).toBeNull();
    });

    it('keeps the existing weekday and time-of-day payload unchanged alongside the new hourly field', async () => {
      const morning = await write('An early entry.', ['calm']);
      setHour(morning.id, 7);

      const body = (await request(server()).get('/insights/when').expect(200)).body as WhenBody;

      // The pre-CH-5 shape: still exactly 7 weekday buckets and 3 time-of-day buckets, with the
      // same fields on each — nothing about this ticket touches how those are computed.
      expect(body.weekdays).toHaveLength(7);
      expect(body.times_of_day).toHaveLength(3);
      expect(body.times_of_day.map((bucket) => bucket.key).sort()).toEqual([
        'afternoon',
        'evening',
        'morning',
      ]);
      for (const bucket of [...body.weekdays, ...body.times_of_day]) {
        expect(bucket).toHaveProperty('key');
        expect(bucket).toHaveProperty('label');
        expect(bucket).toHaveProperty('entry_count');
        expect(bucket).toHaveProperty('average_valence');
        expect(bucket).toHaveProperty('negative_rate');
        expect(bucket).toHaveProperty('sufficient');
      }

      // The new fields are additive: present, twelve blocks, well-formed keys.
      expect(body.hourly).toHaveLength(12);
      expect(body.hourly.map((bucket) => bucket.key)).toEqual([
        '00',
        '02',
        '04',
        '06',
        '08',
        '10',
        '12',
        '14',
        '16',
        '18',
        '20',
        '22',
      ]);
      expect(body.best_hour === null || typeof body.best_hour === 'string').toBe(true);
      expect(body.worst_hour === null || typeof body.worst_hour === 'string').toBe(true);
      expect(
        body.busiest_time_of_day === null || typeof body.busiest_time_of_day === 'string',
      ).toBe(true);
    });
  });
});

describe('I6 — the optional intensity dial', () => {
  it('stores what the user set, returns it, and shows it on the calendar — I6-SC1', async () => {
    const created = (
      await request(server())
        .post('/entries')
        .send({ mode: 'freeform', raw_text: 'A tense afternoon before the call.' })
        .expect(201)
    ).body as { id: string; version: number };

    const saved = (
      await request(server())
        .patch(`/entries/${created.id}`)
        .send({ feeling_keys: ['anxious'], feeling_intensity: 4, version: created.version })
        .expect(200)
    ).body as { feeling_intensity: number; version: number; entry_date: string };

    expect(saved.feeling_intensity).toBe(4);

    const month = saved.entry_date.slice(0, 7);
    const summary = (await request(server()).get(`/monthly-summary?month=${month}`).expect(200))
      .body as { days: Array<{ date: string; intensity: number | null }> };
    const day = summary.days.find((row) => row.date === saved.entry_date)!;
    expect(day.intensity).toBe(4);
  });

  it('keeps an intensity through an unrelated edit and drops it when the feeling changes — I6-SC2', async () => {
    const created = (
      await request(server())
        .post('/entries')
        .send({ mode: 'freeform', raw_text: 'A tense afternoon.' })
        .expect(201)
    ).body as { id: string; version: number };

    let entry = (
      await request(server())
        .patch(`/entries/${created.id}`)
        .send({ feeling_keys: ['anxious'], feeling_intensity: 4, version: created.version })
        .expect(200)
    ).body as { feeling_intensity: number | null; version: number };

    entry = (
      await request(server())
        .patch(`/entries/${created.id}`)
        .send({ raw_text: 'A tense afternoon, then it eased.', version: entry.version })
        .expect(200)
    ).body as typeof entry;
    expect(entry.feeling_intensity).toBe(4);

    entry = (
      await request(server())
        .patch(`/entries/${created.id}`)
        .send({ feeling_keys: ['calm'], version: entry.version })
        .expect(200)
    ).body as typeof entry;
    expect(entry.feeling_intensity).toBeNull();
  });

  it('rates every feeling on the entry, not only the first one', async () => {
    const created = (
      await request(server())
        .post('/entries')
        .send({ mode: 'freeform', raw_text: 'Grateful for the day and anxious about tomorrow.' })
        .expect(201)
    ).body as { id: string; version: number };

    const saved = (
      await request(server())
        .patch(`/entries/${created.id}`)
        .send({
          feeling_keys: ['grateful', 'anxious'],
          feeling_intensities: { grateful: 2, anxious: 5 },
          version: created.version,
        })
        .expect(200)
    ).body as {
      feeling_intensity: number;
      feeling_intensities: Record<string, number>;
      version: number;
    };

    expect(saved.feeling_intensities).toEqual({ grateful: 2, anxious: 5 });
    // The entry-wide column mirrors the primary feeling and nothing else, so the calendar keeps
    // drawing a number that is true about the dot it draws.
    expect(saved.feeling_intensity).toBe(2);
  });

  it('drops a rating for a feeling removed from the entry, and keeps the rest', async () => {
    const created = (
      await request(server())
        .post('/entries')
        .send({ mode: 'freeform', raw_text: 'Mixed.' })
        .expect(201)
    ).body as { id: string; version: number };

    let entry = (
      await request(server())
        .patch(`/entries/${created.id}`)
        .send({
          feeling_keys: ['grateful', 'anxious'],
          feeling_intensities: { grateful: 2, anxious: 5 },
          version: created.version,
        })
        .expect(200)
    ).body as { feeling_intensities: Record<string, number>; version: number };

    // Ratings travel with their feeling: dropping *grateful* must not slide its 2 onto *anxious*.
    entry = (
      await request(server())
        .patch(`/entries/${created.id}`)
        .send({ feeling_keys: ['anxious'], version: entry.version })
        .expect(200)
    ).body as typeof entry;

    expect(entry.feeling_intensities).toEqual({ anxious: 5 });
  });

  it('reads a single feeling_intensity as a rating of the primary feeling', async () => {
    const created = (
      await request(server())
        .post('/entries')
        .send({ mode: 'freeform', raw_text: 'An older client is writing this.' })
        .expect(201)
    ).body as { id: string; version: number };

    const saved = (
      await request(server())
        .patch(`/entries/${created.id}`)
        .send({ feeling_keys: ['anxious', 'sad'], feeling_intensity: 3, version: created.version })
        .expect(200)
    ).body as { feeling_intensities: Record<string, number>; feeling_intensity: number };

    expect(saved.feeling_intensities).toEqual({ anxious: 3 });
    expect(saved.feeling_intensity).toBe(3);
  });

  it('refuses a value outside the scale — I6-08', async () => {
    const created = (
      await request(server())
        .post('/entries')
        .send({ mode: 'freeform', raw_text: 'A tense afternoon.' })
        .expect(201)
    ).body as { id: string; version: number };

    await request(server())
      .patch(`/entries/${created.id}`)
      .send({ feeling_keys: ['anxious'], feeling_intensity: 50, version: created.version })
      .expect(422);
  });

  it('never affects pattern eligibility — I6-06', async () => {
    for (let index = 0; index < 4; index += 1) {
      await write(`Tea number ${index}.`, ['calm'], index + 1);
    }
    for (let index = 0; index < 6; index += 1) {
      await write(`A long day at work, number ${index}.`, ['stressed'], index + 1);
    }
    const before = find(await insights(), 'tea')!;

    const day = (await request(server()).get(`/entries?date=${before.evidence[0].entry_date}`)).body
      .entries[0] as { id: string; version: number };
    await request(server())
      .patch(`/entries/${day.id}`)
      .send({ feeling_keys: ['calm'], feeling_intensity: 5, version: day.version })
      .expect(200);

    const after = find(await insights(), 'tea')!;
    expect(after.occurrence_count).toBe(before.occurrence_count);
    expect(after.lift).toBe(before.lift);
  });
});

// -----------------------------------------------------------------------------------------------
// A4 — topic consolidation
// -----------------------------------------------------------------------------------------------

describe('A4 — one idea, one topic row', () => {
  it('folds a user alias into the canonical topic on the next recompute — A4-SC3', async () => {
    for (let index = 0; index < 4; index += 1) {
      await write(`A quiet kintsugi evening, number ${index}.`, ['calm'], index + 1);
    }
    for (let index = 0; index < 6; index += 1) {
      await write(`A long day at work, number ${index}.`, ['stressed'], index + 1);
    }

    // The keyword extractor knows nothing about kintsugi, so the topic has to be created the way a
    // user would create it: by telling the app the word matters.
    const db = new Database(h.dbPath);
    db.prepare(
      `INSERT INTO topics (id, name, aliases, first_seen_at, last_seen_at)
       VALUES ('t-kintsugi', 'kintsugi', '[]', '2026-01-01 00:00:00.000000', '2026-01-01 00:00:00.000000')`,
    ).run();
    db.close();

    expect(find(await insights(), 'kintsugi')).toBeDefined();

    const topics = (await request(server()).get('/topics').expect(200)).body as {
      topics: Array<{ id: string; name: string; aliases: string[] }>;
    };
    const kintsugi = topics.topics.find((topic) => topic.name === 'kintsugi')!;

    const updated = (
      await request(server())
        .post(`/topics/${kintsugi.id}/aliases`)
        .send({ alias: 'gold repair' })
        .expect(200)
    ).body as { aliases: string[] };
    expect(updated.aliases).toContain('gold repair');

    // A4-04: the edit takes effect on the next recompute, with no model involved.
    await write('An evening of gold repair on the broken bowl.', ['calm'], 1);
    const after = find(await insights(), 'kintsugi')!;
    expect(after.occurrence_count).toBe(5);
  });

  it('rejects an alias already spoken for, rather than letting one phrase resolve two ways', async () => {
    await write('A walk by the river.', ['content']);
    await write('Tea in the garden.', ['calm']);

    await insights(); // topics are written by the recompute, so ask for one first
    const topics = (await request(server()).get('/topics').expect(200)).body as {
      topics: Array<{ id: string; name: string }>;
    };
    const walking = topics.topics.find((topic) => topic.name === 'walking')!;
    await request(server())
      .post(`/topics/${walking.id}/aliases`)
      .send({ alias: 'tea' })
      .expect(422);
  });

  it('is idempotent — a second recompute changes no count — A4-SC2', async () => {
    for (let index = 0; index < 4; index += 1) {
      await write(`Tea number ${index}.`, ['calm'], index + 1);
    }
    for (let index = 0; index < 6; index += 1) {
      await write(`A long day at work, number ${index}.`, ['stressed'], index + 1);
    }

    const first = await insights();
    const second = await insights();
    const shape = (body: InsightsBody) =>
      body.patterns.map((p) => [p.kind, p.topic, p.feeling, p.occurrence_count, p.lifetime_count]);
    expect(shape(second)).toEqual(shape(first));
  });
});
