/**
 * E-1b (#26): the mixed-valence pairing rule, run against the real engine through the real API.
 *
 * §11.7 engine rule #4 in one sentence: a mixed-valence entry (its confirmed feelings span both
 * `positive` and `negative`) only feeds the topic×feeling pairs it explicitly confirmed through
 * `PUT /entries/:id/topic-feelings`; every other combination its own topics and feelings could
 * otherwise form is excluded from that pair's counting entirely, on both sides of the table. A
 * single-valence entry (the common case) is untouched — that half is already covered by
 * `pairing-insights-snapshot.test.ts`'s determinism guard on the seeded golden fixture, where
 * confirming a pairing on a single-feeling entry leaves `GET /insights` byte-for-byte identical.
 *
 * Feelings used here and their valence, read from `src/db/feeling-vocabulary.ts`'s `FEELING_SEED`
 * rather than guessed at (the vocabulary changed under #60 — several words that read as neutral no
 * longer are):
 *
 *  - `disappointed` — negative ("Low" group)
 *  - `happy` — positive ("Uplifted" group)
 *  - `energised` — positive ("Uplifted" group)
 *
 * Topics come from the curated keyword list (`src/topics/canonicalization.ts`), not invented
 * words: "workout"/"gym" → `exercise`, "parents" → `family`, "coffee" → `coffee`.
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

interface EntryTopic {
  id: string;
  name: string;
}

interface EntryPairing {
  topic_id: string;
  feeling_key: string;
  source: string;
}

interface EntryOut {
  id: string;
  feeling_keys: string[];
  topics: EntryTopic[];
  topic_feelings: EntryPairing[];
}

async function readEntry(entryId: string): Promise<EntryOut> {
  return (await request(server()).get(`/entries/${entryId}`).expect(200)).body as EntryOut;
}

/**
 * Topics are extracted by keyword during `recomputePatterns` (`PatternsService#loadEvidenceEntries`),
 * not on write — so `GET /insights` has to run at least once before an entry's `entry_topics` rows
 * exist for `PUT .../topic-feelings` to validate a pairing against.
 */
async function recompute(): Promise<InsightsBody> {
  return (await request(server()).get('/insights').expect(200)).body as InsightsBody;
}

async function confirmPairings(
  entryId: string,
  pairings: Array<{ topic_id: string; feeling_key: string }>,
): Promise<void> {
  await request(server()).put(`/entries/${entryId}/topic-feelings`).send({ pairings }).expect(200);
}

interface Pattern {
  topic: string;
  feeling: string;
  kind: 'forward' | 'inverse';
  occurrence_count: number;
  present_count: number;
  present_total: number;
  absent_count: number;
  absent_total: number;
  base_rate: number;
}

interface InsightsBody {
  patterns: Pattern[];
  excluded_unpaired: number;
}

function findPattern(patterns: Pattern[], topic: string, feeling: string): Pattern | undefined {
  return patterns.find((p) => p.topic === topic && p.feeling === feeling && p.kind === 'forward');
}

function describeFound(patterns: Pattern[]): string {
  if (patterns.length === 0) return '(no patterns)';
  return patterns.map((p) => `${p.kind}:${p.topic}/${p.feeling}x${p.occurrence_count}`).join('; ');
}

// ---------------------------------------------------------------------------------------------
// Criterion 1 — the §11.7 example, all four cells
// ---------------------------------------------------------------------------------------------

describe('§11.7: a confirmed mixed-valence entry counts only its confirmed pairs', () => {
  it('increments exactly the two confirmed pairs and neither cross pair (all four cells asserted)', async () => {
    const entryIds: string[] = [];
    for (const text of [
      'Skipped my workout and visited my parents.',
      'Missed the gym again, then saw my parents.',
      'No workout today, spent the evening with my parents.',
    ]) {
      const entry = await write(text, ['disappointed', 'happy']);
      entryIds.push(entry.id);
    }

    // Recompute once so `entry_topics` exists, then confirm the §11.7 pairing on every entry:
    // (exercise → disappointed) and (family → happy) — never the cross combinations.
    await recompute();
    for (const entryId of entryIds) {
      const before = await readEntry(entryId);
      const exercise = before.topics.find((t) => t.name === 'exercise');
      const family = before.topics.find((t) => t.name === 'family');
      expect(exercise, `exercise topic missing on ${entryId}`).toBeDefined();
      expect(family, `family topic missing on ${entryId}`).toBeDefined();
      await confirmPairings(entryId, [
        { topic_id: exercise!.id, feeling_key: 'disappointed' },
        { topic_id: family!.id, feeling_key: 'happy' },
      ]);
    }

    const { patterns, excluded_unpaired } = await recompute();
    const found = describeFound(patterns);

    // Cell 1 & 2: the confirmed pairs. All three entries are in-window and identical, so every
    // count and total is exact — no absent evidence exists at all (present_total === windowTotal).
    const exerciseDisappointed = findPattern(patterns, 'exercise', 'disappointed');
    const familyHappy = findPattern(patterns, 'family', 'happy');
    expect(exerciseDisappointed, found).toBeDefined();
    expect(familyHappy, found).toBeDefined();
    expect(exerciseDisappointed).toMatchObject({
      occurrence_count: 3,
      present_count: 3,
      present_total: 3,
      absent_count: 0,
      absent_total: 0,
    });
    expect(familyHappy).toMatchObject({
      occurrence_count: 3,
      present_count: 3,
      present_total: 3,
      absent_count: 0,
      absent_total: 0,
    });

    // Cell 3 & 4: the cross pairs. Every one of the three entries carries both `exercise` and
    // `happy`, and both `family` and `disappointed` — the old, unfixed engine would have counted
    // both of these to 3 as well. Under the pairing rule neither was ever confirmed, so their
    // lifetime count never leaves zero and neither appears in the payload at all.
    expect(findPattern(patterns, 'exercise', 'happy'), found).toBeUndefined();
    expect(findPattern(patterns, 'family', 'disappointed'), found).toBeUndefined();

    // Every entry confirmed a full pairing, so none of them was excluded from anything.
    expect(excluded_unpaired).toBe(0);
  });
});

// ---------------------------------------------------------------------------------------------
// Criterion 2 — an unconfirmed mixed entry contributes to no pair, and is reported as excluded
// ---------------------------------------------------------------------------------------------

describe('an unconfirmed mixed-valence entry', () => {
  it('contributes to no topic×feeling pair, still counts toward the feeling base rate, and is reported excluded', async () => {
    const entryIds: string[] = [];
    for (const text of [
      'Skipped my workout and visited my parents.',
      'Missed the gym again, then saw my parents.',
      'No workout today, spent the evening with my parents.',
    ]) {
      entryIds.push((await write(text, ['disappointed', 'happy'])).id);
    }
    await recompute();
    for (const entryId of entryIds) {
      const entry = await readEntry(entryId);
      const exercise = entry.topics.find((t) => t.name === 'exercise')!;
      const family = entry.topics.find((t) => t.name === 'family')!;
      await confirmPairings(entryId, [
        { topic_id: exercise.id, feeling_key: 'disappointed' },
        { topic_id: family.id, feeling_key: 'happy' },
      ]);
    }

    const before = await recompute();
    expect(findPattern(before.patterns, 'exercise', 'disappointed')?.occurrence_count).toBe(3);
    expect(findPattern(before.patterns, 'family', 'happy')?.occurrence_count).toBe(3);
    expect(before.excluded_unpaired).toBe(0);

    // A fourth entry, same topics and feelings — but its pairing step is skipped entirely (issue
    // rule 2's "skipped the pairing step entirely" branch, not the "left a pair unlinked" one).
    await write('Another day, no workout, saw my parents again.', ['disappointed', 'happy']);
    const after = await recompute();
    const found = describeFound(after.patterns);

    // Neither confirmed pair moved from 3 to 4 — the fourth entry contributed nothing to either.
    expect(findPattern(after.patterns, 'exercise', 'disappointed'), found).toMatchObject({
      occurrence_count: 3,
    });
    expect(findPattern(after.patterns, 'family', 'happy'), found).toMatchObject({
      occurrence_count: 3,
    });
    // Nor did it leak into the cross pairs — the conservative default is "counted nowhere", not
    // "counted wherever it happens to land".
    expect(findPattern(after.patterns, 'exercise', 'happy'), found).toBeUndefined();
    expect(findPattern(after.patterns, 'family', 'disappointed'), found).toBeUndefined();

    // Rule 2's second half: it still counts toward feeling base rates. All four entries carry
    // `disappointed`, so the base rate is 4/4 — the exclusion never touches `entriesWithFeeling`.
    expect(findPattern(after.patterns, 'exercise', 'disappointed')?.base_rate).toBe(1);

    // Criterion 5: exactly one entry lost at least one pair to the rule.
    expect(after.excluded_unpaired).toBe(1);
  });
});

// ---------------------------------------------------------------------------------------------
// Criterion 3 — 2×2 internal consistency, checked for every reported pattern
// ---------------------------------------------------------------------------------------------

/**
 * An independent reference implementation of the counting rule, written from the issue's spec
 * rather than borrowed from `patterns.service.ts` — the point of a property test is to catch the
 * production code disagreeing with the *rule*, not to restate the production code back at itself.
 */
interface RefEntry {
  topicIds: string[];
  feelingKeys: string[];
  mixed: boolean;
  confirmedPairs: Set<string>;
}

interface RefAssociation {
  presentCount: number;
  presentTotal: number;
  absentCount: number;
  absentTotal: number;
}

function referenceForward(
  entries: RefEntry[],
  topicId: string,
  feelingKey: string,
): RefAssociation {
  const windowTotal = entries.length;
  let withTopic = 0;
  let withFeeling = 0;
  let rawPresent = 0;
  let excluded = 0;
  for (const entry of entries) {
    const hasTopic = entry.topicIds.includes(topicId);
    const hasFeeling = entry.feelingKeys.includes(feelingKey);
    if (hasTopic) withTopic += 1;
    if (hasFeeling) withFeeling += 1;
    if (hasTopic && hasFeeling) {
      rawPresent += 1;
      if (entry.mixed && !entry.confirmedPairs.has(`${topicId} ${feelingKey}`)) excluded += 1;
    }
  }
  return {
    presentCount: rawPresent - excluded,
    presentTotal: withTopic - excluded,
    absentCount: withFeeling - rawPresent,
    absentTotal: windowTotal - withTopic,
  };
}

/** `invert()`'s own transformation (`analysis.ts`) — a plain swap, uncontested by this rule. */
function referenceAssociation(
  entries: RefEntry[],
  topicId: string,
  feelingKey: string,
  kind: 'forward' | 'inverse',
): RefAssociation {
  const forward = referenceForward(entries, topicId, feelingKey);
  if (kind === 'forward') return forward;
  return {
    presentCount: forward.absentCount,
    presentTotal: forward.absentTotal,
    absentCount: forward.presentCount,
    absentTotal: forward.presentTotal,
  };
}

const VALENCE: Record<string, string> = {
  disappointed: 'negative',
  happy: 'positive',
  energised: 'positive',
};

function isMixed(feelingKeys: string[]): boolean {
  const hasPositive = feelingKeys.some((k) => VALENCE[k] === 'positive');
  const hasNegative = feelingKeys.some((k) => VALENCE[k] === 'negative');
  return hasPositive && hasNegative;
}

describe('2×2 internal consistency (property)', () => {
  it('present_total + absent_total matches an independent recount, for every reported pattern', async () => {
    const entryIds: string[] = [];

    // Group 1 — fully confirmed mixed entries (3×): both pairs linked, nothing excluded.
    for (let i = 0; i < 3; i += 1) {
      entryIds.push((await write(`Workout and parents, day ${i}.`, ['disappointed', 'happy'])).id);
    }
    // Group 2 — partially confirmed mixed entries (2×): only (exercise→disappointed) linked;
    // (family, happy) is left unlinked, exercising rule 2's "left unlinked" branch specifically.
    const partialIds: string[] = [];
    for (let i = 0; i < 2; i += 1) {
      const id = (await write(`Another workout, parents too, day ${i}.`, ['disappointed', 'happy']))
        .id;
      entryIds.push(id);
      partialIds.push(id);
    }
    // Group 3 — a fully unconfirmed mixed entry (1×): the pairing step is skipped entirely.
    const skippedId = (await write('Workout, then parents, unpaired.', ['disappointed', 'happy']))
      .id;
    entryIds.push(skippedId);
    // Group 4 — single-valence entries (3×): never paired, never excluded (rule 1).
    for (let i = 0; i < 3; i += 1) {
      entryIds.push((await write(`Good coffee this morning, day ${i}.`, ['energised'])).id);
    }

    await recompute();

    const topicIdByName = new Map<string, string>();
    const refByEntry = new Map<string, RefEntry>();
    for (const entryId of entryIds) {
      const entry = await readEntry(entryId);
      for (const topic of entry.topics) topicIdByName.set(topic.name, topic.id);
      refByEntry.set(entryId, {
        topicIds: entry.topics.map((t) => t.id),
        feelingKeys: entry.feeling_keys,
        mixed: isMixed(entry.feeling_keys),
        confirmedPairs: new Set(), // filled in once every pairing below has been written
      });
    }

    const exerciseId = topicIdByName.get('exercise');
    const familyId = topicIdByName.get('family');
    expect(exerciseId, 'exercise topic was not extracted').toBeDefined();
    expect(familyId, 'family topic was not extracted').toBeDefined();

    for (const entryId of entryIds.slice(0, 3)) {
      await confirmPairings(entryId, [
        { topic_id: exerciseId!, feeling_key: 'disappointed' },
        { topic_id: familyId!, feeling_key: 'happy' },
      ]);
    }
    for (const entryId of partialIds) {
      await confirmPairings(entryId, [{ topic_id: exerciseId!, feeling_key: 'disappointed' }]);
    }
    // `skippedId` gets no `PUT` at all — the skip case.

    // Read every entry's *actual, server-recorded* confirmed pairings back, rather than trusting
    // what this test intended to send — `CONFIRMED_FEELING_SOURCES` is `['confirmed',
    // 'overridden']` (never `'suggested'`, which only the worker ever writes).
    for (const entryId of entryIds) {
      const entry = await readEntry(entryId);
      const ref = refByEntry.get(entryId)!;
      for (const pairing of entry.topic_feelings) {
        if (pairing.source === 'confirmed' || pairing.source === 'overridden') {
          ref.confirmedPairs.add(`${pairing.topic_id} ${pairing.feeling_key}`);
        }
      }
    }

    const { patterns } = await recompute();
    expect(patterns.length).toBeGreaterThan(0);

    for (const pattern of patterns) {
      const topicId = topicIdByName.get(pattern.topic);
      expect(topicId, `unknown topic in payload: ${pattern.topic}`).toBeDefined();
      const expected = referenceAssociation(
        [...refByEntry.values()],
        topicId!,
        pattern.feeling,
        pattern.kind,
      );

      // The headline property: the pair's own denominator is self-consistent — never the
      // unadjusted window total once anything has been excluded from that specific pair, and
      // never inflated by silently reclassifying an excluded entry onto the absent side.
      expect(
        pattern.present_total + pattern.absent_total,
        `${pattern.kind}:${pattern.topic}/${pattern.feeling}`,
      ).toBe(expected.presentTotal + expected.absentTotal);

      // The individual cells too, not just their sum — a compensating pair of bugs could satisfy
      // the sum alone.
      expect(pattern.present_count, `${pattern.topic}/${pattern.feeling} present_count`).toBe(
        expected.presentCount,
      );
      expect(pattern.present_total, `${pattern.topic}/${pattern.feeling} present_total`).toBe(
        expected.presentTotal,
      );
      expect(pattern.absent_count, `${pattern.topic}/${pattern.feeling} absent_count`).toBe(
        expected.absentCount,
      );
      expect(pattern.absent_total, `${pattern.topic}/${pattern.feeling} absent_total`).toBe(
        expected.absentTotal,
      );

      // Cells never exceed their own totals.
      expect(pattern.present_count).toBeLessThanOrEqual(pattern.present_total);
      expect(pattern.absent_count).toBeLessThanOrEqual(pattern.absent_total);
    }
  });
});

// ---------------------------------------------------------------------------------------------
// Criterion 4 — the echo obeys the same rule
// ---------------------------------------------------------------------------------------------

interface Echo {
  topic: string;
  feeling: string;
}

async function echoFor(entryId: string): Promise<Echo[]> {
  return (
    (await request(server()).get(`/entries/${entryId}/echo`).expect(200)).body as {
      echoes: Echo[];
    }
  ).echoes;
}

/** Materialises the two §11.7 patterns as *active* — three confirmed, fully-paired entries. */
async function establishBothPatterns(): Promise<void> {
  const entryIds: string[] = [];
  for (const text of [
    'Skipped my workout and visited my parents.',
    'Missed the gym again, then saw my parents.',
    'No workout today, spent the evening with my parents.',
  ]) {
    entryIds.push((await write(text, ['disappointed', 'happy'])).id);
  }
  await recompute();
  for (const entryId of entryIds) {
    const entry = await readEntry(entryId);
    const exercise = entry.topics.find((t) => t.name === 'exercise')!;
    const family = entry.topics.find((t) => t.name === 'family')!;
    await confirmPairings(entryId, [
      { topic_id: exercise.id, feeling_key: 'disappointed' },
      { topic_id: family.id, feeling_key: 'happy' },
    ]);
  }
  await recompute();
}

describe('the pattern echo obeys the same pairing rule (task 3)', () => {
  it('shows no echo for either pattern on an entry whose own pairing is unconfirmed', async () => {
    await establishBothPatterns();

    // A new entry, same topics and feelings as the two active patterns — but its own pairing step
    // is never touched. Its own occurrence would not itself have contributed to either pattern
    // (rule 2), so echoing it either one would be a contaminated match (task 3).
    const written = await write('Another skipped workout, saw my parents again.', [
      'disappointed',
      'happy',
    ]);
    const echoes = await echoFor(written.id);

    expect(
      echoes.find((e) => e.topic === 'exercise' && e.feeling === 'disappointed'),
    ).toBeUndefined();
    expect(echoes.find((e) => e.topic === 'family' && e.feeling === 'happy')).toBeUndefined();
  });

  it('shows the echo once the entry confirms its own pairing', async () => {
    await establishBothPatterns();

    const written = await write('Another skipped workout, saw my parents again.', [
      'disappointed',
      'happy',
    ]);
    await recompute();
    const entry = await readEntry(written.id);
    const exercise = entry.topics.find((t) => t.name === 'exercise')!;
    // Confirm only the exercise/disappointed side, deliberately, to show the rule applies per
    // pair — not as an all-or-nothing switch on the entry.
    await confirmPairings(written.id, [{ topic_id: exercise.id, feeling_key: 'disappointed' }]);

    const echoes = await echoFor(written.id);
    expect(
      echoes.find((e) => e.topic === 'exercise' && e.feeling === 'disappointed'),
    ).toBeDefined();
    // family/happy was never confirmed for this entry, so it stays suppressed exactly as before.
    expect(echoes.find((e) => e.topic === 'family' && e.feeling === 'happy')).toBeUndefined();
  });

  it('needs no pairing at all for a single-valence entry — rule 1, unaffected', async () => {
    // Three single-feeling entries are enough on their own to make (exercise, disappointed)
    // active, with no pairing step involved anywhere.
    for (let i = 0; i < 3; i += 1) {
      await write(`Skipped my workout, day ${i}.`, ['disappointed']);
    }
    await recompute();

    const written = await write('Another skipped workout.', ['disappointed']);
    const echoes = await echoFor(written.id);
    expect(
      echoes.find((e) => e.topic === 'exercise' && e.feeling === 'disappointed'),
    ).toBeDefined();
  });
});
