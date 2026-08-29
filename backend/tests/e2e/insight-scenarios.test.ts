/**
 * Every way the Insights view could mislead someone, run as a test.
 *
 * The corpus lives in `../fixtures/insight-scenarios.json` and each scenario states what the app
 * **should** do — never what it currently does. That distinction is the whole design of this file:
 *
 *  - a scenario marked `holds` runs as an ordinary test and guards behaviour that is already right;
 *  - a scenario marked `defect` runs as a *failing* expectation, so the suite stays green while the
 *    problem exists and turns **red the moment it is fixed** — which forces the fixture to be
 *    updated in the same change, instead of a stale "known issue" comment rotting in a file.
 *
 * Nothing here involves a model. Feelings are the ones a user settled on and topics come from the
 * keyword extractor, so every expectation can be worked out by hand and every failure is a real
 * disagreement about behaviour rather than a model having an off day.
 */

import Database from 'better-sqlite3';
import * as fs from 'node:fs';
import * as path from 'node:path';
import request from 'supertest';
import { describe, expect, it } from 'vitest';
import { DEFAULT_USER_ID } from '../../src/auth/default-user';
import { bootOnFresh, teardown, type Harness } from '../helpers/app';

interface WrittenEntry {
  text: string;
  feelings: string[];
  /** Backdated by writing `entry_date` directly; the API always files an entry under today. */
  daysAgo?: number;
}

interface Expectation {
  /** Each must be present, and every field given on it must match. */
  patterns?: Array<{ topic: string; feeling: string; count?: number; direction?: string }>;
  /** None of these may appear as a topic at all. */
  absentTopics?: string[];
  /** The diary supports no claim worth making. */
  noPatterns?: boolean;
  /** More than this many insights from one situation is noise, not analysis. */
  maxPatterns?: number;
  /** These may be reported, but must never carry advice to change them. */
  notAdvisedToChange?: string[];
  /** No topic may appear with both a keep and a change insight. */
  noContradictoryTopics?: boolean;
  /** Reading the view twice in a row must give the same list in the same order. */
  stableAcrossReads?: boolean;
  /** These topics must be present but labelled historical, never as active findings (I3). */
  historicalTopics?: string[];
  /** No narrative may call anything "recent" — the window is stated in days or not at all (I3-04). */
  neverSaysRecent?: boolean;
  /** Each of these topics must carry a confounder annotation naming the other one (I2-02). */
  confounderNotedFor?: string[];
  /** Every surfaced pattern must state a lift, or state why it has none (A3-02/A3-03). */
  everyPatternStatesItsComparison?: boolean;
}

interface Scenario {
  name: string;
  concern: string;
  source: string;
  verdict: 'holds' | 'defect';
  note?: string;
  entries?: WrittenEntry[];
  repeat?: { times: number; entry: WrittenEntry };
  expect: Expectation;
}

const CORPUS = JSON.parse(
  fs.readFileSync(path.resolve(__dirname, '../fixtures/insight-scenarios.json'), 'utf8'),
) as { scenarios: Scenario[] };

interface Insight {
  topic: string;
  feeling: string;
  occurrence_count: number;
  direction: string;
  narrative_text: string;
  suggestion_text: string;
  status: 'active' | 'historical';
  lift: number | null;
  comparison_reason: string | null;
  comparison_note: string | null;
  confounders: Array<{ topic: string; note: string }>;
}

/** A scenario may list entries, repeat one many times, or both. */
function entriesOf(scenario: Scenario): WrittenEntry[] {
  const repeated = scenario.repeat
    ? Array.from({ length: scenario.repeat.times }, () => scenario.repeat!.entry)
    : [];
  return [...(scenario.entries ?? []), ...repeated];
}

async function insightsFor(
  scenario: Scenario,
): Promise<{ insights: Insight[]; reread: Insight[]; h: Harness }> {
  // M-3 (#48): `manualEntitlements: true` plus a standing premium grant for the default user —
  // this corpus is about the engine's own correctness (recency labelling, lift, confounders…),
  // which is exactly the "full ranges" premium behaviour (unchanged since before this ticket). The
  // free/paid boundary itself — that a free reader never sees a `historicalTopics` entry at all —
  // has its own dedicated coverage in `tests/contract/free-paid-boundary.test.ts`, not here.
  const h = await bootOnFresh({ manualEntitlements: true });
  const server = h.app.getHttpServer();
  await request(server)
    .post('/billing/admin/grant')
    .send({ user_id: DEFAULT_USER_ID, tier: 'premium' })
    .expect(200);

  for (const entry of entriesOf(scenario)) {
    const created = (
      await request(server)
        .post('/entries')
        .send({ mode: 'freeform', raw_text: entry.text })
        .expect(201)
    ).body as { id: string; version: number };

    await request(server)
      .patch(`/entries/${created.id}`)
      .send({ feeling_keys: entry.feelings, version: created.version })
      .expect(200);

    if (entry.daysAgo) {
      // The API files every entry under today, deliberately. Backdating has to go around it, and
      // going around it is the only way to ask what "recent" means to the engine.
      const db = new Database(h.dbPath);
      const when = new Date(Date.now() - entry.daysAgo * 86_400_000).toISOString().slice(0, 10);
      db.prepare('UPDATE diary_entries SET entry_date = ? WHERE id = ?').run(when, created.id);
      db.close();
    }
  }

  // Read twice: `GET /insights` recomputes before it reads, so the second call is the one that
  // would expose an order that shifts under the reader for no reason they could see.
  const body = (await request(server).get('/insights').expect(200)).body as { patterns: Insight[] };
  const again = (await request(server).get('/insights').expect(200)).body as {
    patterns: Insight[];
  };
  return { insights: body.patterns, reread: again.patterns, h };
}

/** Renders what was actually found, so a failure names the disagreement rather than a boolean. */
function describeFound(insights: Insight[]): string {
  if (insights.length === 0) return '(no insights)';
  return insights
    .map((i) => `${i.topic}/${i.feeling} x${i.occurrence_count} (${i.direction})`)
    .join('; ');
}

function check(insights: Insight[], want: Expectation, reread: Insight[] = insights): void {
  const found = describeFound(insights);

  if (want.noPatterns) {
    expect(
      insights.map((i) => i.topic),
      found,
    ).toEqual([]);
  }

  if (want.maxPatterns !== undefined) {
    expect(insights.length, found).toBeLessThanOrEqual(want.maxPatterns);
  }

  for (const topic of want.absentTopics ?? []) {
    expect(
      insights.map((i) => i.topic),
      found,
    ).not.toContain(topic);
  }

  for (const wanted of want.patterns ?? []) {
    const match = insights.find((i) => i.topic === wanted.topic && i.feeling === wanted.feeling);
    expect(match, `${wanted.topic}/${wanted.feeling} missing — found ${found}`).toBeDefined();
    if (wanted.count !== undefined) expect(match!.occurrence_count).toBe(wanted.count);
    if (wanted.direction !== undefined) expect(match!.direction).toBe(wanted.direction);
  }

  for (const topic of want.notAdvisedToChange ?? []) {
    const advised = insights.filter((i) => i.topic === topic && i.direction === 'change');
    expect(
      advised.map((i) => i.suggestion_text),
      found,
    ).toEqual([]);
  }

  if (want.stableAcrossReads) {
    const shape = (list: Insight[]) => list.map((i) => `${i.topic}/${i.feeling}`);
    expect(shape(reread), found).toEqual(shape(insights));
  }

  for (const topic of want.historicalTopics ?? []) {
    const match = insights.find((i) => i.topic === topic);
    expect(match, `${topic} missing — found ${found}`).toBeDefined();
    // I3-08/I3-09: it is neither presented as an active finding nor silently deleted. Withdrawal
    // is the only removal path, and this pattern was not withdrawn — it simply stopped being now.
    expect(match!.status, found).toBe('historical');
  }

  if (want.neverSaysRecent) {
    const offending = insights.filter((i) => /\brecent\b/i.test(i.narrative_text));
    expect(
      offending.map((i) => i.narrative_text),
      found,
    ).toEqual([]);
  }

  for (const topic of want.confounderNotedFor ?? []) {
    const match = insights.find((i) => i.topic === topic);
    expect(match, `${topic} missing — found ${found}`).toBeDefined();
    // I2-07: the pattern is annotated, never hidden. Withholding it would contradict the app's
    // own explainability principle, so "we showed you both and told you they are inseparable" is
    // the correct behaviour rather than a compromise.
    expect(match!.confounders.length, `${topic} carries no confounder note`).toBeGreaterThan(0);
  }

  if (want.everyPatternStatesItsComparison) {
    const silent = insights.filter((i) => i.lift === null && i.comparison_reason === null);
    expect(
      silent.map((i) => i.topic),
      found,
    ).toEqual([]);
  }

  if (want.noContradictoryTopics) {
    const byTopic = new Map<string, Set<string>>();
    for (const insight of insights) {
      if (!byTopic.has(insight.topic)) byTopic.set(insight.topic, new Set());
      byTopic.get(insight.topic)!.add(insight.direction);
    }
    const contradictory = [...byTopic].filter(([, directions]) => directions.size > 1);
    expect(
      contradictory.map(([topic]) => topic),
      found,
    ).toEqual([]);
  }
}

describe('the Insights view, situation by situation', () => {
  for (const scenario of CORPUS.scenarios) {
    // `it.fails` inverts the result: while the defect exists the expectation throws and the test
    // passes. Fix the defect and this goes red, which is exactly the alarm a known-issue list never
    // gives you.
    const runner = scenario.verdict === 'defect' ? it.fails : it;

    runner(
      `${scenario.verdict === 'defect' ? '[defect] ' : ''}${scenario.name} — ${scenario.concern}`,
      async () => {
        const { insights, reread, h } = await insightsFor(scenario);
        try {
          check(insights, scenario.expect, reread);
        } finally {
          await teardown(h);
        }
      },
      60_000,
    );
  }
});

describe('the defects fail for the reason claimed', () => {
  // `it.fails` above passes whenever the test throws, which includes throwing because a topic in
  // the fixture is misspelled or a scenario writes no entries. That would quietly turn a broken
  // scenario into a green "known defect", so each one is re-run here and its failure inspected: it
  // has to be an assertion about behaviour, not an accident.
  for (const scenario of CORPUS.scenarios.filter((s) => s.verdict === 'defect')) {
    it(`${scenario.name} fails on its expectation, not by accident`, async () => {
      const { insights, h } = await insightsFor(scenario);
      await teardown(h);

      let thrown: unknown;
      try {
        check(insights, scenario.expect);
      } catch (error) {
        thrown = error;
      }

      expect(
        thrown,
        `${scenario.name} no longer fails — update its verdict to "holds"`,
      ).toBeDefined();
      // An expectation that fails throws an `AssertionError`. A misspelled topic, a scenario
      // with no entries, or a broken harness throws a `TypeError` or an `Error` — which is the
      // case this guard exists to catch.
      expect(
        (thrown as Error).name,
        `${scenario.name} threw ${String(thrown)} rather than failing an expectation`,
      ).toBe('AssertionError');
    }, 60_000);
  }
});

describe('the corpus itself', () => {
  it('states an expectation for every scenario', () => {
    for (const scenario of CORPUS.scenarios) {
      expect(Object.keys(scenario.expect).length, scenario.name).toBeGreaterThan(0);
      expect(scenario.concern, scenario.name).toBeTruthy();
      expect(scenario.source, scenario.name).toBeTruthy();
      expect(['holds', 'defect']).toContain(scenario.verdict);
    }
  });

  it('has entries to write in every scenario', () => {
    for (const scenario of CORPUS.scenarios) {
      expect(entriesOf(scenario).length, scenario.name).toBeGreaterThan(0);
    }
  });
});
