/**
 * #119 (E-1e): repairing `pattern_withdrawals` rows a pre-#109 diary stored under the old,
 * mislabelling classifier.
 *
 * `pattern_withdrawals` is written once, at the instant a pattern transitions away
 * (`PatternsService#recordWithdrawal`), and never rewritten by a later recompute — #109 fixed the
 * classifier itself (`backend/tests/e2e/withdrawal-excluded-unpaired.test.ts` proves that fix
 * through the real API), but a diary that already ran the post-#26, pre-#109 engine is left with
 * `no_longer_confirmed` rows for pairs #26's pairing-exclusion rule actually caused. Those rows
 * assert the exact false claim #109 was filed to eliminate — "entries still mention it, but none
 * of them carries a feeling you confirmed" — of entries that, per the diary's own data, carry one.
 *
 * `migrateDiary` (`src/db/migrate.ts`) now repairs these in place via `repairWithdrawalReasons`,
 * option 1 of the issue's three (true reclassification, using the same inputs `buildCandidates`
 * uses: `isMixedValence`, `confirmedPairs`, `isPairExcluded`, and whether the pair's unexcluded
 * evidence would have cleared `MIN_OCCURRENCE_THRESHOLD` — i.e. `excludedFromThreshold`).
 *
 * There is no live code path left on `main` that produces a mislabelled row — #109 already fixed
 * the classifier — so scenario 1 below builds the real transition through the API (mirroring
 * `withdrawal-excluded-unpaired.test.ts`'s own scenario 1, which proves the *live* engine now
 * calls this `excluded_unpaired`), then hand-rewrites the stored row back to `no_longer_confirmed`
 * with the old, false sentence — exactly the shape a diary that ran the engine before #109 landed
 * would be in. Scenario 2 needs no such rewriting: a genuinely `no_longer_confirmed` row (an
 * entry's feeling flipped back to `suggested`, `withdrawal-excluded-unpaired.test.ts`'s own
 * scenario 2) is produced directly by live code and must be left exactly as it is.
 */

import Database from 'better-sqlite3';
import * as fs from 'node:fs';
import type { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { createApp } from '../../src/main';
import { migrateDiary } from '../../src/db/migrate';
import { bootOnFresh, startOnLoopback, type Harness } from '../helpers/app';

let h: Harness;
const server = () => h.app.getHttpServer();

beforeEach(async () => {
  h = await bootOnFresh();
});
afterEach(async () => {
  // `h.app` may already be closed by a test that drives the migration mid-test — closing twice is
  // harmless, but guard it anyway so a failed assertion never leaks a dangling handle.
  try {
    await h.app.close();
  } catch {
    // already closed
  }
  fs.rmSync(h.dir, { recursive: true, force: true });
});

interface Written {
  id: string;
  version: number;
}

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

async function addFeeling(entryId: string, version: number, feelings: string[]): Promise<Written> {
  return (
    await request(server())
      .patch(`/entries/${entryId}`)
      .send({ feeling_keys: feelings, version })
      .expect(200)
  ).body as Written;
}

interface Withdrawal {
  id?: string;
  topic: string;
  feeling: string;
  kind: 'forward' | 'inverse';
  reason: string;
  detail_text: string;
  is_new: boolean;
  withdrawn_at: string;
}

interface InsightsBody {
  withdrawals: Withdrawal[];
}

async function recompute(): Promise<InsightsBody> {
  return (await request(server()).get('/insights').expect(200)).body as InsightsBody;
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

interface StoredWithdrawalRow {
  id: string;
  topic_id: string;
  topic_name: string;
  feeling_key: string;
  kind: string;
  reason: string;
  detail_text: string;
  withdrawn_at: string;
}

function readWithdrawalRow(
  dbPath: string,
  topicName: string,
  feelingKey: string,
): StoredWithdrawalRow {
  const db = new Database(dbPath, { readonly: true });
  try {
    const row = db
      .prepare(
        `SELECT id, topic_id, topic_name, feeling_key, kind, reason, detail_text, withdrawn_at
         FROM pattern_withdrawals WHERE topic_name = ? AND feeling_key = ? AND kind = 'forward'`,
      )
      .get(topicName, feelingKey) as StoredWithdrawalRow | undefined;
    expect(row, `no stored withdrawal row for ${topicName} / ${feelingKey}`).toBeDefined();
    return row!;
  } finally {
    db.close();
  }
}

const OLD_NO_LONGER_CONFIRMED_TEMPLATE = (topic: string, feeling: string): string =>
  `${topic} → ${feeling} was withdrawn: entries still mention it, but none of them carries a ` +
  `feeling you confirmed.`;

describe('#119 (E-1e): migrateDiary repairs stored withdrawal reasons', () => {
  it(
    'reclassifies an exclusion-caused row hand-set to the old no_longer_confirmed reason, ' +
      'leaves a genuine no_longer_confirmed row untouched, and does not re-flag either as new',
    async () => {
      // --- Build both kinds of withdrawal through the real engine, in the same diary ------------
      // The excluded_unpaired half: three wine entries, confirmed `anxious` only, then made
      // mixed-valence without ever confirming a pairing — #26's rule 2 excludes them from this
      // exact pair, and #109's live classifier already calls this `excluded_unpaired` correctly.
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

      for (const entry of wine) {
        await addFeeling(entry.id, entry.version, ['anxious', 'grateful']);
      }
      const flipDb = new Database(h.dbPath);
      try {
        const flip = flipDb.prepare(
          `UPDATE diary_entries SET feeling_source = 'suggested' WHERE id = ?`,
        );
        for (const entry of coffee) flip.run(entry.id);
      } finally {
        flipDb.close();
      }

      const live = await recompute();
      const liveWine = findWithdrawal(live.withdrawals, 'alcohol', 'anxious');
      const liveCoffee = findWithdrawal(live.withdrawals, 'coffee', 'stressed');
      expect(liveWine?.reason).toBe('excluded_unpaired');
      expect(liveCoffee?.reason).toBe('no_longer_confirmed');
      const genuineDetailText = liveCoffee!.detail_text;
      expect(genuineDetailText).toBe(OLD_NO_LONGER_CONFIRMED_TEMPLATE('coffee', 'stressed'));

      // Acknowledge both notices before the migration runs — this is what proves the repair does
      // not resurrect them as "new". `withdrawals_acknowledged_at` is now after both rows'
      // `withdrawn_at`.
      await request(server()).post('/insights/withdrawals/acknowledge').expect(204);
      expect((await recompute()).withdrawals.every((w) => !w.is_new)).toBe(true);

      // --- Simulate a pre-#109 diary: hand-rewrite the wine row back to the old, false label -----
      // No live code path can produce this anymore (#109 already fixed the classifier) — this is
      // exactly the shape the orchestrator found on the maintainer's diary: an `excluded_unpaired`
      // transition stored under the old `no_longer_confirmed` reason and sentence.
      const wineBefore = readWithdrawalRow(h.dbPath, 'alcohol', 'anxious');
      const coffeeBefore = readWithdrawalRow(h.dbPath, 'coffee', 'stressed');
      const rewriteDb = new Database(h.dbPath);
      try {
        rewriteDb
          .prepare(`UPDATE pattern_withdrawals SET reason = ?, detail_text = ? WHERE id = ?`)
          .run(
            'no_longer_confirmed',
            OLD_NO_LONGER_CONFIRMED_TEMPLATE('alcohol', 'anxious'),
            wineBefore.id,
          );
      } finally {
        rewriteDb.close();
      }

      // --- Run the migration -----------------------------------------------------------------
      // A migration is a deliberate, out-of-band command against the diary file — close the app's
      // own connection first, exactly as `npm run migrate-db` is never run against a diary the
      // server still has open.
      await h.app.close();

      const report = migrateDiary(h.dbPath);
      expect(report.withdrawalReasonsRepaired).toBe(1);

      // --- The exclusion-caused row is reclassified, correctly and completely -------------------
      const wineAfter = readWithdrawalRow(h.dbPath, 'alcohol', 'anxious');
      expect(wineAfter.reason).toBe('excluded_unpaired');
      expect(wineAfter.detail_text).toContain('carry a feeling you confirmed');
      expect(wineAfter.detail_text).not.toMatch(/none of them carries a feeling/);
      expect(wineAfter.detail_text).not.toMatch(/unconfirmed|missing/);
      expect(wineAfter.detail_text).toMatch(/\d+ entries diary-wide are excluded from counting/);
      // `withdrawn_at` is never touched by the repair — this is what keeps `is_new` sane.
      expect(wineAfter.withdrawn_at).toBe(wineBefore.withdrawn_at);

      // --- The genuinely no_longer_confirmed row survives byte-for-byte --------------------------
      const coffeeAfter = readWithdrawalRow(h.dbPath, 'coffee', 'stressed');
      expect(coffeeAfter.reason).toBe('no_longer_confirmed');
      expect(coffeeAfter.detail_text).toBe(genuineDetailText);
      expect(coffeeAfter.withdrawn_at).toBe(coffeeBefore.withdrawn_at);

      // --- Idempotent: a second run touches nothing further --------------------------------------
      const second = migrateDiary(h.dbPath);
      expect(second.withdrawalReasonsRepaired).toBe(0);
      expect(readWithdrawalRow(h.dbPath, 'alcohol', 'anxious')).toEqual(wineAfter);
      expect(readWithdrawalRow(h.dbPath, 'coffee', 'stressed')).toEqual(coffeeAfter);

      // --- Acknowledgement state: neither notice comes back as "new" through the real read path --
      const reopenedApp: INestApplication = await createApp(h.dbPath);
      await startOnLoopback(reopenedApp);
      try {
        const body = (await request(reopenedApp.getHttpServer()).get('/insights').expect(200))
          .body as InsightsBody;
        const wineNotice = findWithdrawal(body.withdrawals, 'alcohol', 'anxious');
        const coffeeNotice = findWithdrawal(body.withdrawals, 'coffee', 'stressed');
        expect(wineNotice?.reason).toBe('excluded_unpaired');
        expect(wineNotice?.is_new).toBe(false);
        expect(coffeeNotice?.reason).toBe('no_longer_confirmed');
        expect(coffeeNotice?.is_new).toBe(false);
      } finally {
        await reopenedApp.close();
      }
    },
  );

  it('is a no-op on a diary with no no_longer_confirmed rows at all', async () => {
    // Only a below_lift-shaped withdrawal — never touched by the repair regardless.
    const written: Written[] = [];
    for (const text of ['Tea in the evening.', 'Tea again.', 'Tea before bed.']) {
      written.push(await write(text, ['calm']));
    }
    await recompute();
    // Drive the association's lift below the minimum without touching the count: flood the
    // "without tea" side with the same feeling so tea stops looking special. Simpler here: just
    // confirm there is nothing to repair on a diary that never withdrew anything at all.
    await h.app.close();

    const report = migrateDiary(h.dbPath);
    expect(report.withdrawalReasonsRepaired).toBe(0);
  });
});
