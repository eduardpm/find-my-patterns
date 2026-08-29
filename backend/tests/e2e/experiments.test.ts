/**
 * N-of-1 experiments, end to end (R-3a) — create, get-active, results, abandon, walked through
 * the real API exactly as R-3b's client will drive it.
 *
 * This file stands in for the curl walkthrough a hand-written PR description would otherwise
 * carry: every step below is a real HTTP call against a real diary, booted the same way every
 * other e2e test in this suite boots (`startOnLoopback`, see `tests/helpers/app.ts`), so the
 * whole lifecycle is exercised and re-runnable rather than pasted output that can go stale.
 *
 * The numbers behind the results assertions are hand-computable, in the same spirit as
 * `roadmap-engine.test.ts`: two 7-day windows of entries, written through `POST /entries` exactly
 * as a user would, then backdated (the API always files an entry under today — see `backdate`
 * below) into the experiment window and the baseline window immediately before it.
 */

import request from 'supertest';
import Database from 'better-sqlite3';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import request from 'supertest';
import { DEFAULT_USER_ID } from '../../src/auth/default-user';
import { bootOnFresh, teardown, type Harness } from '../helpers/app';
import { localDateString } from '../helpers/dates';

let h: Harness;
const server = () => h.app.getHttpServer();

// M-3 (#48) gates experiment *creation* behind premium. These tests are about the experiment
// lifecycle, not the paywall, so they run as a premium account — the gate itself is asserted
// in `tests/contract/free-paid-boundary.test.ts`, which owns both sides of that boundary
// (a free account's 402, and the rule that reading back and abandoning are never gated).
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

// -------------------------------------------------------------------------------------------
// Writing entries, exactly as roadmap-engine.test.ts does
// -------------------------------------------------------------------------------------------

interface Written {
  id: string;
  version: number;
}

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

/**
 * The API always files a new entry under today; this is how a test puts one in the past.
 *
 * #125: `entry_date` is filed under `todayLocal()` (`db/codecs.ts`) and an experiment's
 * `start_date`/`end_date` are computed from that same clock (`ExperimentsService.create`) — both
 * local-calendar, not UTC. This used to compute `when` as
 * `new Date(Date.now() - daysAgo * 86_400_000).toISOString().slice(0, 10)`, which reads the UTC
 * calendar date off a UTC-instant subtraction. That agrees with `todayLocal()` every day except
 * the window between local midnight and UTC midnight, where `daysAgo=0` silently backdated an
 * entry to *yesterday's* UTC date while every other clock in this test (and in production) called
 * that day "today" — the same divergence `entries-write.test.ts` had, one step removed.
 * `localDateString` (`tests/helpers/dates.ts`) does the equivalent local-calendar arithmetic.
 */
function backdate(entryId: string, daysAgo: number): void {
  const db = new Database(h.dbPath);
  const when = localDateString(-daysAgo);
  db.prepare('UPDATE diary_entries SET entry_date = ? WHERE id = ?').run(when, entryId);
  db.close();
}

const dateDaysAgo = (daysAgo: number): string => localDateString(-daysAgo);

// -------------------------------------------------------------------------------------------
// Wire shapes
// -------------------------------------------------------------------------------------------

interface ExperimentConstants {
  default_length_days: number;
  min_length_days: number;
  max_length_days: number;
  min_bucket_entries: number;
}

interface ExperimentOut {
  id: string;
  pattern_topic: string;
  pattern_feeling: string;
  hypothesis_kind: 'more_of' | 'less_of';
  start_date: string;
  end_date: string;
  status: 'active' | 'finished' | 'abandoned';
  created_at: string;
  constants: ExperimentConstants;
}

interface WindowOut {
  start_date: string;
  end_date: string;
  total_days: number;
  days_with_topic: number;
  present_count: number;
  present_total: number;
  absent_count: number;
  absent_total: number;
  present_rate: number | null;
  absent_rate: number | null;
}

interface ExperimentResultsOut {
  experiment: ExperimentOut;
  experiment_window: WindowOut;
  baseline_window: WindowOut;
  verdict_text: string;
  insufficient_data: boolean;
  constants: ExperimentConstants;
}

interface Pattern {
  topic: string;
  feeling: string;
  kind: 'forward' | 'inverse';
  status: 'active' | 'historical';
}

interface InsightsBody {
  patterns: Pattern[];
  withdrawals: unknown[];
  new_withdrawal_count: number;
  insufficient_data: boolean;
  constants: Record<string, number>;
}

const insights = async (): Promise<InsightsBody> =>
  (await request(server()).get('/insights').expect(200)).body as InsightsBody;

/**
 * Strips whatever a recompute regenerates purely from wall-clock time — `last_updated_at` on a
 * pattern is rewritten on *every* call to `GET /insights` regardless of whether anything the
 * pattern is derived from changed (`recomputePatterns` rebuilds the whole table each time). Two
 * snapshots taken seconds apart would otherwise differ on that field alone.
 */
function stableInsights(body: InsightsBody): unknown {
  return {
    ...body,
    patterns: body.patterns.map((pattern) => {
      const { ...rest } = pattern as Record<string, unknown>;
      delete rest.last_updated_at;
      return rest;
    }),
  };
}

// -------------------------------------------------------------------------------------------
// The corpus
// -------------------------------------------------------------------------------------------

/**
 * Makes "exercise" / "exhausted" a qualifying forward pattern (recent, within the 30-day
 * recency window, independent of the experiment/baseline windows below): 3 entries mentioning
 * exercise are all exhausted, and only 1 of 5 entries without exercise is.
 */
async function writeQualifyingCorpus(): Promise<void> {
  await write('Intense workout at the gym this morning.', ['exhausted'], 1);
  await write('Went running before breakfast.', ['exhausted'], 2);
  await write('Did a full workout session at the gym.', ['exhausted'], 3);
  await write('Long day of back-to-back meetings.', ['exhausted'], 4);
  await write('Quiet afternoon reading a novel.', ['happy'], 5);
  await write('Cooked a big dinner for friends.', ['happy'], 6);
  await write('Watched a film at home.', ['happy'], 7);
  await write('Tidied up the whole apartment.', ['happy'], 8);
}

/**
 * The experiment window (14–20 days ago, a 7-day span) and the baseline window immediately
 * before it (21–27 days ago). Numbers are chosen so both windows clear
 * `MIN_EXPERIMENT_BUCKET_ENTRIES` and the exact verdict sentence can be asserted by hand:
 * exercise mentioned on 4 of 7 days during the experiment, exhausted in 1 of those 4 entries
 * (25%), vs 3 of 5 (60%) in the 7 days before.
 */
async function writeExperimentAndBaselineCorpus(): Promise<void> {
  // Experiment window (daysAgo 15–20; day 14 deliberately carries no entry).
  await write('Went running around the block.', ['exhausted'], 20);
  await write('Did yoga before work.', ['happy'], 19);
  await write('Workout session at the gym after lunch.', ['happy'], 18);
  await write('Quick gym visit in the evening.', ['calm'], 17);
  await write('Busy day catching up on emails.', ['exhausted'], 16);
  await write('Relaxed evening with a podcast.', ['happy'], 15);

  // Baseline window (daysAgo 21–27).
  await write('Ran five miles in the morning.', ['exhausted'], 27);
  await write('Another yoga class after breakfast.', ['exhausted'], 26);
  await write('Gym session before heading to work.', ['exhausted'], 25);
  await write('Quick workout at lunchtime.', ['happy'], 24);
  await write('Went running along the river.', ['calm'], 23);
  await write('Long stretch of paperwork at the office.', ['exhausted'], 22);
  await write('Chatted with a neighbour over tea.', ['happy'], 21);
}

// -------------------------------------------------------------------------------------------
// The walkthrough
// -------------------------------------------------------------------------------------------

describe('N-of-1 experiments — the full lifecycle (R-3a)', () => {
  it('rejects creation for a pattern that does not qualify', async () => {
    await request(server())
      .post('/experiments')
      .send({ pattern_topic: 'reading', pattern_feeling: 'calm', hypothesis_kind: 'less_of' })
      .expect(422)
      .expect((res) => {
        expect(res.body.error.code).toBe('validation_error');
      });
  });

  it('walks create → get active → single-active rejection → abandon → results → re-create', async () => {
    await writeQualifyingCorpus();
    await writeExperimentAndBaselineCorpus();

    // Nothing changed about /insights yet — a clean before-snapshot to compare against at the end.
    const beforeInsights = await insights();
    const before = stableInsights(beforeInsights);
    const exercisePattern = beforeInsights.patterns.find(
      (p) => p.topic === 'exercise' && p.kind === 'forward',
    );
    expect(exercisePattern).toMatchObject({
      topic: 'exercise',
      feeling: 'exhausted',
      status: 'active',
    });

    // No experiment yet.
    await request(server()).get('/experiments/active').expect(404);

    // --- create (present-day window, so it stays active for the single-active check) ---------
    const createBody = {
      pattern_topic: 'exercise',
      pattern_feeling: 'exhausted',
      hypothesis_kind: 'more_of',
    };
    const created = (await request(server()).post('/experiments').send(createBody).expect(201))
      .body as ExperimentOut;
    expect(created).toMatchObject({
      pattern_topic: 'exercise',
      pattern_feeling: 'exhausted',
      hypothesis_kind: 'more_of',
      status: 'active',
      start_date: dateDaysAgo(0),
      end_date: dateDaysAgo(-6), // today + 6 days: the 7-day default length.
    });
    expect(created.constants).toEqual({
      default_length_days: 7,
      min_length_days: 7,
      max_length_days: 28,
      min_bucket_entries: 3,
    });

    // --- get active -----------------------------------------------------------------------
    const active = (await request(server()).get('/experiments/active').expect(200))
      .body as ExperimentOut;
    expect(active.id).toBe(created.id);

    // --- single-active constraint: a second experiment is refused while one is running -----
    await request(server())
      .post('/experiments')
      .send(createBody)
      .expect(422)
      .expect((res) => {
        expect(res.body.error.code).toBe('validation_error');
      });

    // --- abandon ----------------------------------------------------------------------------
    const abandoned = (
      await request(server()).post(`/experiments/${created.id}/abandon`).expect(200)
    ).body as ExperimentOut;
    expect(abandoned.status).toBe('abandoned');
    await request(server()).get('/experiments/active').expect(404);

    // Abandoning again is refused — it is no longer active.
    await request(server())
      .post(`/experiments/${created.id}/abandon`)
      .expect(422)
      .expect((res) => {
        expect(res.body.error.code).toBe('validation_error');
      });

    // --- create a second experiment, this time over the already-elapsed 14–20-days-ago window,
    // to exercise the results math and the auto-finish transition (single-active now allows it,
    // since the first is abandoned rather than active) --------------------------------------
    const second = (
      await request(server())
        .post('/experiments')
        .send({ ...createBody, start_date: dateDaysAgo(20), length_days: 7 })
        .expect(201)
    ).body as ExperimentOut;
    expect(second.status).toBe('active');
    expect(second.start_date).toBe(dateDaysAgo(20));
    expect(second.end_date).toBe(dateDaysAgo(14));

    // --- results — also the first read that notices the window has closed and flips status --
    const results = (await request(server()).get(`/experiments/${second.id}/results`).expect(200))
      .body as ExperimentResultsOut;

    expect(results.experiment.status).toBe('finished');
    expect(results.experiment_window).toMatchObject({
      start_date: dateDaysAgo(20),
      end_date: dateDaysAgo(14),
      total_days: 7,
      days_with_topic: 4,
      present_count: 1,
      present_total: 4,
      absent_count: 1,
      absent_total: 2,
    });
    expect(results.experiment_window.present_rate).toBeCloseTo(0.25, 5);
    expect(results.baseline_window).toMatchObject({
      start_date: dateDaysAgo(27),
      end_date: dateDaysAgo(21),
      total_days: 7,
      days_with_topic: 5,
      present_count: 3,
      present_total: 5,
      absent_count: 1,
      absent_total: 2,
    });
    expect(results.baseline_window.present_rate).toBeCloseTo(0.6, 5);
    expect(results.insufficient_data).toBe(false);
    expect(results.verdict_text).toBe(
      'During the experiment you mentioned exercise on 4 of 7 days; exhausted appeared in 1 of 4 ' +
        'entries (25%) vs 3 of 5 (60%) in the 7 days before.',
    );
    expect(results.verdict_text).not.toMatch(/because|caused|protect/i);
    expect(results.constants).toEqual(created.constants);

    // GET /experiments/active now that both experiments are settled — none active.
    await request(server()).get('/experiments/active').expect(404);

    // --- no effect on /insights (R-3a #4): the whole lifecycle above wrote no diary entries and
    // touched no pattern — the patterns list is unchanged (modulo the recompute timestamp) -----
    const after = stableInsights(await insights());
    expect(after).toEqual(before);
  });

  it('rejects a length outside 7–28 days', async () => {
    await writeQualifyingCorpus();
    await request(server())
      .post('/experiments')
      .send({
        pattern_topic: 'exercise',
        pattern_feeling: 'exhausted',
        hypothesis_kind: 'more_of',
        length_days: 6,
      })
      .expect(422);
    await request(server())
      .post('/experiments')
      .send({
        pattern_topic: 'exercise',
        pattern_feeling: 'exhausted',
        hypothesis_kind: 'more_of',
        length_days: 29,
      })
      .expect(422);
  });

  it('returns 404 for results and abandon on an unknown experiment id', async () => {
    await request(server()).get('/experiments/does-not-exist/results').expect(404);
    await request(server()).post('/experiments/does-not-exist/abandon').expect(404);
  });
});
