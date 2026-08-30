/**
 * End to end, from written entries to discovered insights — the app's whole purpose in one test.
 *
 * Deliberately **no model runs here.** Everything this file asserts is a factual claim the app
 * makes to the user — "this happened 3 times", "this one is worth keeping" — and constitution
 * Principle III says those must come from deterministic, reproducible code. The corpus below is
 * written so a human can work out the right answer by hand, and the assertions are *closed*: they
 * name every insight that must exist and check that nothing else was invented. That is only
 * possible because the diary starts empty.
 *
 * The companion file `llm-analysis.eval.test.ts` covers the other half — whether the local model
 * reads a real diary entry sensibly — and is graded rather than asserted, for the same reason.
 */

import request from 'supertest';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { associationFrom } from '../../src/insights/analysis';
import {
  MIN_OCCURRENCE_THRESHOLD,
  observationFor,
  templateSuggestionFor,
} from '../../src/insights/patterns.service';
import { RECENCY_WINDOW_DAYS } from '../../src/insights/constants';
import { bootOnFresh, teardown, type Harness } from '../helpers/app';
import { localDateString } from '../helpers/dates';

let h: Harness;
const server = () => h.app.getHttpServer();

beforeEach(async () => {
  h = await bootOnFresh();
});
afterEach(async () => {
  await teardown(h);
});

/**
 * One written entry and the feelings the user settled on for it.
 *
 * The text is chosen so the deterministic keyword extractor finds exactly the topics named in the
 * comment beside it — no more. An accidental extra match would be a silent extra `(topic, feeling)`
 * pair, so the corpus is as much a test of `CURATED_TOPIC_KEYWORDS` as of the pattern engine.
 */
interface Written {
  text: string;
  feelings: string[];
}

const LATE_COFFEE: Written = {
  // topics: coffee ("espresso"), sleep ("slept")
  text: 'Another late espresso at the desk, and then I barely slept.',
  feelings: ['exhausted'],
};

const RIVER_WALK: Written = {
  // topics: walking ("walk"), friends ("friends")
  text: 'A long walk by the river with friends.',
  feelings: ['happy', 'grateful'],
};

const PIZZA_NIGHT: Written = {
  // topics: junk food ("Pizza")
  text: 'Pizza for dinner again.',
  feelings: ['sleepy'],
};

const WALK_WHEN_FLAT: Written = {
  // topics: walking ("walked")
  text: 'Walked to the shops the long way round.',
  feelings: ['energised'],
};

/** Write an entry and settle its feelings, which is what makes it count as evidence (FR-012). */
async function write(entry: Written): Promise<void> {
  const created = (
    await request(server())
      .post('/entries')
      .send({ mode: 'freeform', raw_text: entry.text })
      .expect(201)
  ).body as { id: string; version: number };

  await request(server())
    .patch(`/entries/${created.id}`)
    .send({ feeling_keys: entry.feelings, version: created.version })
    .expect(200);
}

interface Insight {
  topic: string;
  status: 'active' | 'historical';
  present_count: number;
  present_total: number;
  absent_count: number;
  absent_total: number;
  feeling: string;
  occurrence_count: number;
  direction: string;
  narrative_text: string;
  suggestion_text: string;
  kind: 'forward' | 'inverse';
}

async function insights(): Promise<{ patterns: Insight[]; insufficient_data: boolean }> {
  return (await request(server()).get('/insights').expect(200)).body as {
    patterns: Insight[];
    insufficient_data: boolean;
  };
}

/**
 * `(topic, feeling)` pairs, which is the unit pattern detection actually counts.
 *
 * Split by kind since I1, because the two are different claims about the same table: a forward
 * pair says the feeling went *with* the topic, an inverse pair says it went with its *absence*.
 * Pooling them would let an inverse card silently satisfy an assertion about forward ones.
 */
const pairsOf = (found: Insight[], kind: 'forward' | 'inverse' = 'forward'): string[] =>
  found
    .filter((pattern) => pattern.kind === kind)
    .map((pattern) => `${pattern.topic}/${pattern.feeling}`)
    .sort();

describe('from written entries to insights', () => {
  it('says so plainly when there is nothing to report yet', async () => {
    const found = await insights();
    expect(found.patterns).toEqual([]);
    // The clients branch on the flag, not on array length — so the flag is the assertion.
    expect(found.insufficient_data).toBe(true);
  });

  it('finds nothing in a single entry, however clear that entry is', async () => {
    await write(LATE_COFFEE);
    const found = await insights();
    expect(found.insufficient_data).toBe(true);
  });

  it('waits for the third occurrence before claiming a pattern', async () => {
    await write(LATE_COFFEE);
    await write(LATE_COFFEE);

    // Two is a coincidence. The threshold is the app's one defence against telling someone a story
    // about their life on the strength of two coincidences.
    expect(MIN_OCCURRENCE_THRESHOLD).toBe(3);
    expect((await insights()).insufficient_data).toBe(true);

    await write(LATE_COFFEE);
    expect((await insights()).insufficient_data).toBe(false);
  });

  it('discovers exactly the correlations the entries support, and nothing else', async () => {
    for (let i = 0; i < 3; i += 1) await write(LATE_COFFEE);
    for (let i = 0; i < 3; i += 1) await write(RIVER_WALK);
    // Only twice: below the threshold, so this must not surface at all.
    for (let i = 0; i < 2; i += 1) await write(PIZZA_NIGHT);

    const found = await insights();

    expect(pairsOf(found.patterns)).toEqual([
      'coffee/exhausted',
      'friends/grateful',
      'friends/happy',
      'sleep/exhausted',
      'walking/grateful',
      'walking/happy',
    ]);
    // Said explicitly rather than left to the list above: under-reporting is a bug the user would
    // never notice, but over-reporting is the app inventing a correlation.
    expect(pairsOf(found.patterns)).not.toContain('junk food/sleepy');

    // I1 reads the other half of the same table, and it is closed too. Every one of these is the
    // literal complement of a forward pair above — the three walk entries are exactly the three
    // that do not mention coffee — which is why nothing here contradicts the forward list.
    // Capped and ranked by the backend (I1-06), so this is the top five by strength with ties
    // broken on the topic name — a total order, and the same five on every read.
    expect(pairsOf(found.patterns, 'inverse')).toEqual([
      'coffee/grateful',
      'coffee/happy',
      'friends/exhausted',
      'sleep/grateful',
      'sleep/happy',
    ]);
    expect(pairsOf((await insights()).patterns, 'inverse')).toEqual(
      pairsOf(found.patterns, 'inverse'),
    );
  });

  it('counts every feeling on an entry, not just its primary one', async () => {
    // Three entries, each carrying two feelings, are six occurrences of evidence — not three.
    // Counting only the primary feeling would silently discard half of what the user said.
    for (let i = 0; i < 3; i += 1) await write(RIVER_WALK);

    const found = await insights();
    const walking = found.patterns.filter((pattern) => pattern.topic === 'walking');

    expect(walking.map((pattern) => pattern.feeling).sort()).toEqual(['grateful', 'happy']);
    for (const pattern of walking) expect(pattern.occurrence_count).toBe(3);
  });

  it('points a positive correlation at keeping it and a negative one at changing it', async () => {
    for (let i = 0; i < 3; i += 1) await write(LATE_COFFEE);
    for (let i = 0; i < 3; i += 1) await write(RIVER_WALK);
    // P0-6: without these, "exhausted" only ever occurs alongside coffee and "happy" only ever
    // occurs alongside walking — a perfectly separated table, which is a division by zero on the
    // lift, not a weak one. One entry on each feeling's other side gives both a real, computable
    // ratio, which is what this test is actually about.
    await write({
      text: 'Felt exhausted for no particular reason today.',
      feelings: ['exhausted'],
    });
    await write({
      text: 'A happy moment out of nowhere, nothing special happened.',
      feelings: ['happy'],
    });

    const found = await insights();
    const direction = (topic: string, feeling: string) =>
      found.patterns.find((p) => p.topic === topic && p.feeling === feeling)?.direction;

    expect(direction('coffee', 'exhausted')).toBe('change');
    expect(direction('walking', 'happy')).toBe('keep');
  });

  it('describes a pattern in terms the reader can check against their own entries', async () => {
    for (let i = 0; i < 3; i += 1) await write(LATE_COFFEE);

    const found = await insights();
    const coffee = found.patterns.find((p) => p.topic === 'coffee');

    // The count in the sentence must be the count that was actually measured. A narrative that
    // says "4 recent entries" beside `occurrence_count: 3` is the app contradicting itself.
    expect(coffee?.occurrence_count).toBe(3);
    expect(coffee?.narrative_text).toContain('3');
    expect(coffee?.narrative_text).toContain('coffee');
    expect(coffee?.narrative_text).toContain('exhausted');
    expect(coffee?.suggestion_text).toContain('coffee');
  });

  it('reads as a finding about the reader, not as a row of statistics (FR-010)', async () => {
    // The scenario the product exists for: something the user did, something they felt, three
    // times over. What the Insights view then says is the entire deliverable.
    for (let i = 0; i < 3; i += 1) await write(WALK_WHEN_FLAT);

    const found = await insights();
    const walking = found.patterns.find((p) => p.topic === 'walking');

    expect(walking).toBeDefined();
    // I3-04: the sentence states the window it counted over, because the count *is* a windowed
    // count. The old wording said "3 recent entries" beside a lifetime total, which was false for
    // any diary older than a month.
    expect(walking?.narrative_text).toBe(
      `You felt energised in 3 of 3 entries mentioning walking in the last ${RECENCY_WINDOW_DAYS} ` +
        `days (100%). There are not enough entries without walking to compare.`,
    );
    // P0-6: "not enough entries ... to compare" is the sentence for a lift that could not be
    // computed (`comparisonReason: 'insufficient_comparison'`, `lift: null`) — the same undefined
    // ratio the reported bug showed a badge over. A three-entry diary with nothing else in it
    // cannot both say that sentence and carry a "keep" badge without contradicting itself, so this
    // card now carries neither badge, same as the "Work → anxious" card the ticket was filed for.
    expect(walking?.lift).toBeNull();
    expect(walking?.direction).toBe('none');
    expect(walking?.status).toBe('active');
  });

  it('states a number in the finding only when that number was measured', async () => {
    for (let i = 0; i < 4; i += 1) await write(WALK_WHEN_FLAT);

    const found = await insights();
    const walking = found.patterns.find((p) => p.topic === 'walking')!;

    // The count in the sentence and the count in the payload are the same number by construction,
    // because the sentence is built from it. This is what the phrasing is not allowed to loosen:
    // "several recent entries" would read more naturally and would stop being checkable.
    expect(walking.occurrence_count).toBe(4);
    expect(walking.narrative_text).toBe(
      observationFor(
        'energised',
        'walking',
        // Rebuilt from the payload's own four cells: if the sentence and the numbers beside it
        // could ever come apart, this is the assertion that would notice.
        associationFrom(
          walking.present_count,
          walking.present_total,
          walking.absent_count,
          walking.absent_total,
        ),
      ),
    );
    // I3-SC3: "recent" only ever appeared because the count was not windowed. It is gone.
    expect(walking.narrative_text).not.toContain('recent');
  });

  it('always carries a suggestion, even with no model anywhere near it', async () => {
    for (let i = 0; i < 3; i += 1) await write(WALK_WHEN_FLAT);

    const found = await insights();
    const walking = found.patterns.find((p) => p.topic === 'walking')!;

    // `GET /insights` never waits on the analyser: it writes the plain-language template and
    // returns. A better-worded suggestion lands later, on a background pass. An insight with no
    // advice on it at all would be the one outcome the user cannot use.
    expect(walking.suggestion_text).toBe(templateSuggestionFor('energised', 'walking'));
    expect(walking.suggestion_text).toContain('walking');
  });

  it('withdraws a pattern once the entries stop supporting it', async () => {
    for (let i = 0; i < 3; i += 1) await write(LATE_COFFEE);
    expect(pairsOf((await insights()).patterns)).toContain('coffee/exhausted');

    const listed = (
      await request(server())
        .get('/entries?date=' + localDateString(0))
        .expect(200)
    ).body as { entries: Array<{ id: string; version: number }> };
    const victim = listed.entries[0];
    await request(server()).delete(`/entries/${victim.id}?version=${victim.version}`).expect(204);

    // Down to two supporting entries, so the claim is no longer one the app can stand behind.
    const after = await insights();
    expect(pairsOf(after.patterns)).not.toContain('coffee/exhausted');
    expect(after.insufficient_data).toBe(true);
  });

  it('keeps an unconfirmed feeling out of the evidence entirely', async () => {
    // Written but never settled: the analyser's guess is not something the user said, and FR-012
    // says only what they acted on counts.
    for (let i = 0; i < 3; i += 1) {
      await request(server())
        .post('/entries')
        .send({ mode: 'freeform', raw_text: LATE_COFFEE.text })
        .expect(201);
    }

    expect((await insights()).insufficient_data).toBe(true);
  });
});
