/**
 * M-3 (#48): the free/paid boundary itself — everything M-2 (#47) built (`entitlements`,
 * `EntitlementsService`, `RequiresPremiumGuard`) applied, or deliberately *not* applied, to real
 * routes. Three concerns, each its own `describe` block below:
 *
 *  1. **Never gated.** Diary write/read, feelings, monthly summary, export and health must ignore
 *     tier entirely — a table over the endpoint list, run under both tiers, so a future gate added
 *     to any of these by accident (a copy-pasted `@RequiresPremium()`, a controller merged into one
 *     of these by mistake) fails this suite instead of shipping silently.
 *  2. **Entitlement-derived window.** `GET /insights` and `GET /insights/series` compute a
 *     narrower result for free and report the window they actually used in `constants` — the two
 *     engine-behaviour test suites (`roadmap-engine.test.ts`, `series.test.ts`) already prove the
 *     mechanics in detail; this file proves the boundary itself, once, end to end.
 *  3. **Gated creation, ungated read-back.** `POST /experiments` is the one route this ticket
 *     blocks outright; `GET /experiments/active`, `GET /experiments/:id/results` and
 *     `POST /experiments/:id/abandon` all stay reachable regardless of tier — "never paywall
 *     reading back", applied to a lapsed premium user's own experiment, not only to diary entries.
 *
 * The bottom `describe` is the issue's own manual tier-flip demo, turned into a reproducible e2e
 * test: one running app (`startOnLoopback`, via `bootOnFresh`), tier flipped twice through
 * `POST /billing/admin/grant`, asserting both the insights window and the experiments gate move
 * together each time — no restart, no reinstall.
 */

import Database from 'better-sqlite3';
import request from 'supertest';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { DEFAULT_USER_ID } from '../../src/auth/default-user';
import { bootOnFresh, teardown, type Harness } from '../helpers/app';

let h: Harness;
const server = () => h.app.getHttpServer();

beforeEach(async () => {
  h = await bootOnFresh({ manualEntitlements: true });
});
afterEach(async () => {
  await teardown(h);
});

async function grant(tier: 'free' | 'premium'): Promise<void> {
  await request(server())
    .post('/billing/admin/grant')
    .send({ user_id: DEFAULT_USER_ID, tier })
    .expect(200);
}

interface Written {
  id: string;
  version: number;
}

/** Write an entry and confirm a feeling, exactly as a client does. */
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

/**
 * Makes "exercise" / "exhausted" a qualifying forward pattern within the free tier's own 30-day
 * window — every entry lands in the last few days, so this corpus qualifies for an experiment
 * under *either* tier, isolating the assertions below to the gate itself rather than to whether
 * the pattern is visible at all.
 */
async function writeQualifyingCorpus(): Promise<void> {
  await write('Intense workout at the gym this morning.', ['exhausted']);
  await write('Went running before breakfast.', ['exhausted']);
  await write('Did a full workout session at the gym.', ['exhausted']);
  await write('Long day of back-to-back meetings.', ['exhausted']);
  await write('Quiet afternoon reading a novel.', ['happy']);
  await write('Cooked a big dinner for friends.', ['happy']);
  await write('Watched a film at home.', ['happy']);
  await write('Tidied up the whole apartment.', ['happy']);
}

const EXPERIMENT_BODY = {
  pattern_topic: 'exercise',
  pattern_feeling: 'exhausted',
  hypothesis_kind: 'more_of' as const,
};

// -------------------------------------------------------------------------------------------
// 1. Never gated
// -------------------------------------------------------------------------------------------

describe('never gated — ignores tier entirely (issue task 1)', () => {
  /** One request per row, run once as free and once as premium; `expect` is what the row must
   *  answer under *both* tiers — never 402, whatever else it does. */
  const rows: Array<{
    name: string;
    request: () => request.Test;
    expectStatus: number;
  }> = [
    { name: 'GET /health', request: () => request(server()).get('/health'), expectStatus: 200 },
    {
      name: 'GET /entries?date=...',
      request: () => request(server()).get('/entries?date=2026-01-15'),
      expectStatus: 200,
    },
    {
      name: 'POST /entries',
      request: () =>
        request(server())
          .post('/entries')
          .send({ mode: 'freeform', raw_text: 'A plain entry, written to prove this is ungated.' }),
      expectStatus: 201,
    },
    { name: 'GET /feelings', request: () => request(server()).get('/feelings'), expectStatus: 200 },
    {
      name: 'GET /monthly-summary?month=...',
      request: () => request(server()).get('/monthly-summary?month=2026-01'),
      expectStatus: 200,
    },
    {
      name: 'GET /export?format=json',
      request: () => request(server()).get('/export?format=json'),
      expectStatus: 200,
    },
  ];

  it.each(rows)('$name answers the same way for free and for premium', async (row) => {
    const asFree = await row.request();
    expect(asFree.status).toBe(row.expectStatus);
    expect(asFree.status).not.toBe(402);

    await grant('premium');

    const asPremium = await row.request();
    expect(asPremium.status).toBe(row.expectStatus);
    expect(asPremium.status).not.toBe(402);
  });
});

// -------------------------------------------------------------------------------------------
// 2. Entitlement-derived window (mechanics are `roadmap-engine.test.ts` / `series.test.ts`'s job;
//    this is the boundary itself, end to end)
// -------------------------------------------------------------------------------------------

describe('insights and series — the window is entitlement-derived (issue task 1)', () => {
  it('GET /insights reports the free-tier window it actually applied, in constants', async () => {
    const body = (await request(server()).get('/insights').expect(200)).body as {
      constants: { recency_window_days: number | null };
    };
    expect(body.constants.recency_window_days).toBe(30);
  });

  it('GET /insights reports no window (full range) once premium', async () => {
    await grant('premium');
    const body = (await request(server()).get('/insights').expect(200)).body as {
      constants: { recency_window_days: number | null };
    };
    expect(body.constants.recency_window_days).toBeNull();
  });

  it('GET /insights/series rejects a > 30-day range for free but reports the same cap in constants', async () => {
    const res = await request(server())
      .get('/insights/series?from=2020-01-01&to=2020-03-01&granularity=day')
      .expect(422);
    expect(res.body.error.code).toBe('validation_error');

    const ok = (
      await request(server())
        .get('/insights/series?from=2026-01-01&to=2026-01-15&granularity=day')
        .expect(200)
    ).body as { constants: { recency_window_days: number | null } };
    expect(ok.constants.recency_window_days).toBe(30);
  });

  it('GET /insights/series accepts the same > 30-day range once premium, with no window in constants', async () => {
    await grant('premium');
    const res = await request(server())
      .get('/insights/series?from=2020-01-01&to=2020-03-01&granularity=day')
      .expect(200);
    expect(
      (res.body as { constants: { recency_window_days: number | null } }).constants,
    ).toHaveProperty('recency_window_days', null);
  });
});

describe('history_span_days — the real number behind the mobile locked state (issue task 2)', () => {
  it('is null on an empty diary, for either tier', async () => {
    const free = (await request(server()).get('/insights').expect(200)).body as {
      history_span_days: number | null;
    };
    expect(free.history_span_days).toBeNull();

    await grant('premium');
    const premium = (await request(server()).get('/insights').expect(200)).body as {
      history_span_days: number | null;
    };
    expect(premium.history_span_days).toBeNull();
  });

  it('counts every entry, not only confirmed evidence, and is identical for free and premium', async () => {
    // An entry with no confirmed feeling at all still marks when the diary started.
    await request(server())
      .post('/entries')
      .send({ mode: 'freeform', raw_text: 'First entry ever, never confirmed.' })
      .expect(201);
    const db = new Database(h.dbPath);
    db.prepare("UPDATE diary_entries SET entry_date = '2025-01-01'").run();
    db.close();

    const free = (await request(server()).get('/insights').expect(200)).body as {
      history_span_days: number | null;
    };
    expect(free.history_span_days).toBeGreaterThan(300); // well past the 30-day free window

    await grant('premium');
    const premium = (await request(server()).get('/insights').expect(200)).body as {
      history_span_days: number | null;
    };
    // Same fact, unaffected by the tier that also drives the window and the pattern list.
    expect(premium.history_span_days).toBe(free.history_span_days);
  });
});

// -------------------------------------------------------------------------------------------
// 3. Gated creation, ungated read-back and abandon
// -------------------------------------------------------------------------------------------

describe('experiments — creation is gated, reading back and abandoning never are (issue task 1)', () => {
  it('POST /experiments answers 402 premium_required for a free account', async () => {
    await writeQualifyingCorpus();
    const res = await request(server()).post('/experiments').send(EXPERIMENT_BODY).expect(402);
    expect(res.body).toEqual({ error: 'premium_required' });
  });

  it('POST /experiments succeeds for a premium account', async () => {
    await writeQualifyingCorpus();
    await grant('premium');
    await request(server()).post('/experiments').send(EXPERIMENT_BODY).expect(201);
  });

  it('GET /experiments/active never 402s, before or after any grant', async () => {
    // No experiment yet, still free: a 404 (nothing active), never a 402 (the route itself is not
    // gated) — the distinction this whole describe block exists to prove.
    await request(server()).get('/experiments/active').expect(404);
    await grant('premium');
    await request(server()).get('/experiments/active').expect(404);
  });

  it('a lapsed premium user can still read results and abandon the experiment they started — never trapped', async () => {
    await writeQualifyingCorpus();
    await grant('premium');
    const created = (await request(server()).post('/experiments').send(EXPERIMENT_BODY).expect(201))
      .body as { id: string };

    // Subscription lapses.
    await grant('free');

    // Reading back is never gated (product rule: never paywall reading back).
    await request(server()).get('/experiments/active').expect(200);
    await request(server()).get(`/experiments/${created.id}/results`).expect(200);

    // Abandoning is never gated either — otherwise a lapsed user could neither finish the
    // experiment they started nor clear it to start a new one once premium again.
    await request(server())
      .post(`/experiments/${created.id}/abandon`)
      .expect(200)
      .expect((res) => {
        expect(res.body.status).toBe('abandoned');
      });
  });
});

// -------------------------------------------------------------------------------------------
// The manual tier-flip demo (issue acceptance criterion 3), as a reproducible e2e test: one
// running app, tier flipped twice, both layers (the insights window and the experiments gate)
// move together each time.
// -------------------------------------------------------------------------------------------

describe('manual tier-flip demo — one running app, both layers move together, no restart', () => {
  it('flips the insights window and the experiments gate together, twice, with no restart', async () => {
    await writeQualifyingCorpus();

    // --- starts free ---------------------------------------------------------------------------
    let insights = (await request(server()).get('/insights').expect(200)).body as {
      constants: { recency_window_days: number | null };
    };
    expect(insights.constants.recency_window_days).toBe(30);
    let createRes = await request(server()).post('/experiments').send(EXPERIMENT_BODY);
    expect(createRes.status).toBe(402);

    // --- flips to premium, same app instance ----------------------------------------------------
    await grant('premium');
    insights = (await request(server()).get('/insights').expect(200)).body as {
      constants: { recency_window_days: number | null };
    };
    expect(insights.constants.recency_window_days).toBeNull();
    createRes = await request(server()).post('/experiments').send(EXPERIMENT_BODY);
    expect(createRes.status).toBe(201);
    const experimentId = (createRes.body as { id: string }).id;

    // --- flips back to free, same app instance ----------------------------------------------------
    await grant('free');
    insights = (await request(server()).get('/insights').expect(200)).body as {
      constants: { recency_window_days: number | null };
    };
    expect(insights.constants.recency_window_days).toBe(30);
    // Creating a *second* experiment is blocked again, immediately — no cache, no stale state.
    createRes = await request(server())
      .post('/experiments')
      .send({ ...EXPERIMENT_BODY, pattern_topic: 'reading' });
    expect(createRes.status).toBe(402);
    // But the one already started (while premium) is still readable, free or not.
    await request(server()).get(`/experiments/${experimentId}/results`).expect(200);
  });
});
