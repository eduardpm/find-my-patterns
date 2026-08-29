/**
 * #109 (E-1d): a pair withdrawn because of #26's mixed-valence exclusion must carry its own
 * reason — `excluded_unpaired` — and must never be confused with `no_longer_confirmed`.
 *
 * The bug: the very next recompute after #26 (E-1b) landed withdrew every pair whose lifetime
 * count depended entirely on entries #26 now excludes, and `PatternsService#recordWithdrawal`
 * fell through to `no_longer_confirmed` for every one of them — a sentence that reads "entries
 * still mention it, but none of them carries a feeling you confirmed." That is false of these
 * entries: they carry a feeling the user explicitly confirmed (`feeling_source = 'confirmed'` or
 * `'overridden'`, `CONFIRMED_FEELING_SOURCES`). What they never confirmed is the specific
 * topic↔feeling *pairing* #26's rule requires once an entry is mixed-valence.
 *
 * Scenario 1 builds this through the real API, mirroring `pairing-counting-rule.test.ts`
 * (#26's own e2e suite): three single-valence, confirmed `alcohol` → `anxious` entries become an
 * active pattern, then each entry gains a positive feeling (`grateful`) without ever confirming a
 * pairing — turning them mixed-valence and, per #26, excluded from this exact pair's count.
 *
 * Scenario 2 builds the genuine `no_longer_confirmed` case this reason must still cover. There is
 * no API path that reverts a confirmed entry back to unconfirmed (`updateEntry` only ever moves
 * `feeling_source` *into* `'confirmed'`/`'overridden'`, never out — see
 * `backend/src/entries/entries.service.ts`), so this scenario flips `diary_entries.feeling_source`
 * directly with `better-sqlite3` against the harness's own `dbPath` — the same direct-DB technique
 * `export.test.ts`/`context-patterns.test.ts`/`entries-topic-feelings.test.ts` already use for
 * setup a real client action cannot produce. `entry_topics` and `entry_feelings` are left exactly
 * as they were: the point of the scenario is that the *mention* survives while the *confirmation*
 * does not, which is the one thing `no_longer_confirmed`'s sentence is actually true of.
 *
 * Scenario 3 builds both in the same diary, in the same recompute, and asserts each keeps its own
 * reason — the acceptance criterion's own "test both, so the two cannot be confused again."
 */

import Database from 'better-sqlite3';
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

/** Write an entry and settle its feelings, exactly as a client does (mirrors `roadmap-engine.test.ts`). */
async function write(text: string, feelings: string[]): Promise<Written> {
  const created = (
    await request(server()).post('/entries').send({ mode: 'freeform', raw_text: text }).expect(201)
  ).body as Written;

  return (
    await request(server())
      .patch(`/entries/${created.id}`)
      .send({ feeling_keys: feelings, version: created.version })
      .expect(200)
  ).body as Written;
}

/** Add a feeling to an already-written entry without touching its text (mirrors `write` above). */
async function addFeeling(entryId: string, version: number, feelings: string[]): Promise<Written> {
  return (
    await request(server())
      .patch(`/entries/${entryId}`)
      .send({ feeling_keys: feelings, version })
      .expect(200)
  ).body as Written;
}

interface Pattern {
  topic: string;
  feeling: string;
  kind: 'forward' | 'inverse';
  occurrence_count: number;
}

interface Withdrawal {
  topic: string;
  feeling: string;
  kind: 'forward' | 'inverse';
  reason: string;
  previous_count: number;
  new_count: number;
  detail_text: string;
}

interface InsightsBody {
  patterns: Pattern[];
  withdrawals: Withdrawal[];
  excluded_unpaired: number;
}

async function recompute(): Promise<InsightsBody> {
  return (await request(server()).get('/insights').expect(200)).body as InsightsBody;
}

function findPattern(patterns: Pattern[], topic: string, feeling: string): Pattern | undefined {
  return patterns.find((p) => p.topic === topic && p.feeling === feeling && p.kind === 'forward');
}

function findWithdrawal(
  withdrawals: Withdrawal[],
  topic: string,
  feeling: string,
): Withdrawal | undefined {
  return withdrawals.find(
    (w) => w.topic === topic && w.feeling === feeling && w.kind === 'forward',
  );
}

describe('#109 (E-1d): excluded_unpaired vs no_longer_confirmed', () => {
  it('a pair suppressed by #26 exclusion is withdrawn as excluded_unpaired, not no_longer_confirmed', async () => {
    // Three single-valence entries, confirmed with only `anxious` — never touches the pairing
    // rule at all (rule 1: single-valence is untouched), so this becomes an ordinary active
    // pattern exactly as it would have before #26.
    const written: Written[] = [];
    for (const text of [
      'Had a glass of wine after work.',
      'Another glass of wine tonight.',
      'Wine again — it has become a habit.',
    ]) {
      written.push(await write(text, ['anxious']));
    }

    const before = await recompute();
    expect(findPattern(before.patterns, 'alcohol', 'anxious')).toMatchObject({
      occurrence_count: 3,
    });
    expect(findWithdrawal(before.withdrawals, 'alcohol', 'anxious')).toBeUndefined();

    // Each entry now also confirms `grateful` — positive, alongside `anxious`'s negative,
    // which is exactly §11.7's mixed-valence trigger. No pairing is ever confirmed for any of
    // them (no call to `PUT .../topic-feelings`), so #26's rule excludes every one of them from
    // the (alcohol, anxious) pair specifically — the entries the ticket's own SQLite evidence
    // showed still carry `anxious` as a confirmed feeling.
    for (const entry of written) {
      const updated = await addFeeling(entry.id, entry.version, ['anxious', 'grateful']);
      expect(updated.version).toBeGreaterThan(entry.version);
    }

    const after = await recompute();

    // The pair is gone from `patterns` — #26's counting rule itself is untouched and out of
    // scope here; this ticket is only about how the withdrawal is explained.
    expect(findPattern(after.patterns, 'alcohol', 'anxious')).toBeUndefined();

    const withdrawal = findWithdrawal(after.withdrawals, 'alcohol', 'anxious');
    expect(withdrawal, JSON.stringify(after.withdrawals)).toBeDefined();
    expect(withdrawal!.reason).toBe('excluded_unpaired');
    expect(withdrawal!.reason).not.toBe('no_longer_confirmed');

    // The sentence is true of these entries: it says a feeling *was* confirmed, never that one
    // is missing or unconfirmed, and it cites the top-level `excluded_unpaired` count instead of
    // inventing a per-pair one.
    expect(withdrawal!.detail_text).toContain('carry a feeling you confirmed');
    expect(withdrawal!.detail_text).not.toMatch(/none of them carries a feeling/);
    expect(withdrawal!.detail_text).not.toMatch(/unconfirmed|missing/);
    expect(after.excluded_unpaired).toBe(3);
    expect(withdrawal!.detail_text).toContain(`${after.excluded_unpaired} entries diary-wide`);

    // previous_count is what the pattern showed before the exclusion (3, from `before` above);
    // new_count is the honest post-exclusion count for this pair, which is 0 — a real delta, not
    // the "2 → 2" the issue was filed over.
    expect(withdrawal!.previous_count).toBe(3);
    expect(withdrawal!.new_count).toBe(0);
  });

  it(
    'a pair whose entries genuinely carry no confirmed feeling is still withdrawn as ' +
      'no_longer_confirmed',
    async () => {
      const written: Written[] = [];
      for (const text of [
        'Too much coffee again this morning.',
        'Coffee before the meeting, as usual.',
        'Third coffee of the day.',
      ]) {
        written.push(await write(text, ['stressed']));
      }

      const before = await recompute();
      expect(findPattern(before.patterns, 'coffee', 'stressed')).toMatchObject({
        occurrence_count: 3,
      });

      // No API path un-confirms an entry (`updateEntry` only ever moves `feeling_source` into
      // `'confirmed'`/`'overridden'`), so this reaches for the diary file directly — the same
      // technique this suite's sibling e2e tests already use for setup no client action can
      // produce. `entry_topics` and `entry_feelings` are left untouched: the entries still mention
      // the topic and still carry the feeling in the raw sense `anySource` checks, exactly the
      // "the user un-confirmed it" case `recordWithdrawal`'s own comment describes.
      const db = new Database(h.dbPath);
      try {
        const flip = db.prepare(
          `UPDATE diary_entries SET feeling_source = 'suggested' WHERE id = ?`,
        );
        for (const entry of written) flip.run(entry.id);
      } finally {
        db.close();
      }

      const after = await recompute();
      expect(findPattern(after.patterns, 'coffee', 'stressed')).toBeUndefined();

      const withdrawal = findWithdrawal(after.withdrawals, 'coffee', 'stressed');
      expect(withdrawal, JSON.stringify(after.withdrawals)).toBeDefined();
      expect(withdrawal!.reason).toBe('no_longer_confirmed');
      expect(withdrawal!.reason).not.toBe('excluded_unpaired');
      expect(withdrawal!.detail_text).toBe(
        'coffee → stressed was withdrawn: entries still mention it, but none of them carries a ' +
          'feeling you confirmed.',
      );
      expect(withdrawal!.previous_count).toBe(3);
      expect(withdrawal!.new_count).toBe(0);
    },
  );

  it('keeps the two reasons apart when both happen in the same diary, in the same recompute', async () => {
    // The excluded_unpaired half: three wine entries, confirmed `anxious` only.
    const wine: Written[] = [];
    for (const text of ['A glass of wine.', 'Wine with dinner.', 'Wine again tonight.']) {
      wine.push(await write(text, ['anxious']));
    }
    // The no_longer_confirmed half: three coffee entries, confirmed `stressed` only.
    const coffee: Written[] = [];
    for (const text of ['Coffee at my desk.', 'Coffee before the call.', 'Another coffee.']) {
      coffee.push(await write(text, ['stressed']));
    }

    await recompute();

    // Turn the wine entries mixed-valence, unpaired.
    for (const entry of wine) {
      await addFeeling(entry.id, entry.version, ['anxious', 'grateful']);
    }
    // Turn the coffee entries genuinely unconfirmed.
    const db = new Database(h.dbPath);
    try {
      const flip = db.prepare(`UPDATE diary_entries SET feeling_source = 'suggested' WHERE id = ?`);
      for (const entry of coffee) flip.run(entry.id);
    } finally {
      db.close();
    }

    const after = await recompute();

    const wineWithdrawal = findWithdrawal(after.withdrawals, 'alcohol', 'anxious');
    const coffeeWithdrawal = findWithdrawal(after.withdrawals, 'coffee', 'stressed');
    expect(wineWithdrawal, JSON.stringify(after.withdrawals)).toBeDefined();
    expect(coffeeWithdrawal, JSON.stringify(after.withdrawals)).toBeDefined();

    expect(wineWithdrawal!.reason).toBe('excluded_unpaired');
    expect(coffeeWithdrawal!.reason).toBe('no_longer_confirmed');
    // The two reasons — and the two sentences — must never land on the other's pattern.
    expect(wineWithdrawal!.reason).not.toBe(coffeeWithdrawal!.reason);
    expect(wineWithdrawal!.detail_text).not.toBe(coffeeWithdrawal!.detail_text);
  });
});
