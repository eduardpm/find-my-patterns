/**
 * E-3 (#22): does topic identity actually merge everywhere it is supposed to?
 *
 * `canonicalization.ts` and the alias table exist and are unit-tested in isolation
 * (`unit/canonicalization.test.ts`), but a pure function being right proves nothing about the four
 * places that read topic identity through the database: the pattern engine, the entry echo, the
 * topics listing, and the timing of when an edit takes effect. This file is that verification, one
 * test per consumer, plus the hygiene rule (case never splits identity) and the acceptance
 * criterion's exact scenario end to end.
 *
 * Every scenario starts from an empty diary and goes through the real API — `bootOnFresh` plus
 * `startOnLoopback`, never a dev server — so a failure here means a consumer, not the test's setup.
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

interface Pattern {
  id: string;
  kind: 'forward' | 'inverse' | 'context';
  topic: string;
  feeling: string;
  status: 'active' | 'historical';
  occurrence_count: number;
  present_count: number;
  present_total: number;
  absent_count: number;
  absent_total: number;
}

interface InsightsBody {
  patterns: Pattern[];
  insufficient_data: boolean;
}

const insights = async (): Promise<InsightsBody> =>
  (await request(server()).get('/insights').expect(200)).body as InsightsBody;

const find = (body: InsightsBody, topic: string, kind: Pattern['kind'] = 'forward') =>
  body.patterns.find((pattern) => pattern.topic === topic && pattern.kind === kind);

interface TopicDetail {
  id: string;
  name: string;
  aliases: string[];
  entry_count: number;
}

const listTopics = async (): Promise<TopicDetail[]> =>
  ((await request(server()).get('/topics').expect(200)).body as { topics: TopicDetail[] }).topics;

const addAlias = async (topicId: string, alias: string): Promise<TopicDetail> =>
  (await request(server()).post(`/topics/${topicId}/aliases`).send({ alias }).expect(200))
    .body as TopicDetail;

interface EchoOut {
  topic: string;
  kind: string;
  status: string;
}

async function echoFor(entryId: string): Promise<EchoOut[]> {
  return (
    (await request(server()).get(`/entries/${entryId}/echo`).expect(200)).body as {
      echoes: EchoOut[];
    }
  ).echoes;
}

describe('E-3 — alias and canonicalization merge across consumers (#22)', () => {
  // -----------------------------------------------------------------------------------------
  // Consumer 1: the pattern engine
  // -----------------------------------------------------------------------------------------
  it('patterns: entries split between "walk" and "walking" produce one pattern with combined 2×2 counts', async () => {
    // Four entries, two different curated variants of the same canonical topic ("walking":
    // ['walk', 'walked', 'walking', 'hike', 'hiked', 'hiking']). If identity ever split on wording,
    // this would surface as two "walking" rows or a stray "walk" row.
    await write('A walk before breakfast.', ['content']);
    await write('Another walk after lunch.', ['content']);
    await write('Went walking after dinner.', ['content']);
    await write('A long walking loop around the park.', ['content']);
    // A comparison group so the 2×2 table has something on the "absent" side too.
    for (let index = 0; index < 4; index += 1) {
      await write(`A long day at work, number ${index}.`, ['stressed']);
    }

    const found = await insights();

    // Exactly one "walking" pattern — not one for "walk" and a separate one for "walking".
    const walkingPatterns = found.patterns.filter(
      (p) => p.topic === 'walking' && p.kind === 'forward',
    );
    expect(walkingPatterns).toHaveLength(1);
    expect(found.patterns.some((p) => p.topic === 'walk')).toBe(false);

    const walking = walkingPatterns[0];
    // The 2×2 table combines all four entries, whichever word they used.
    expect(walking.occurrence_count).toBe(4);
    expect(walking.present_count).toBe(4);
    expect(walking.present_total).toBe(4);
    expect(walking.absent_count).toBe(0);
    expect(walking.absent_total).toBe(4);
  });

  // -----------------------------------------------------------------------------------------
  // Consumer 2: the entry echo
  // -----------------------------------------------------------------------------------------
  it('echo: an entry mentioning a user alias matches the pattern stored under the canonical topic', async () => {
    for (let index = 0; index < 3; index += 1) {
      await write(`Went for a walk, day ${index}.`, ['content']);
    }
    for (let index = 0; index < 3; index += 1) {
      await write(`A long day at work, number ${index}.`, ['stressed']);
    }
    await insights(); // topics are written by the recompute, so ask for one before reading them

    const walking = (await listTopics()).find((topic) => topic.name === 'walking')!;
    await addAlias(walking.id, 'strolling');

    // A brand-new entry that never mentions "walk" or "walking" — only the alias.
    const created = (
      await request(server())
        .post('/entries')
        .send({ mode: 'freeform', raw_text: 'A slow strolling session by the lake.' })
        .expect(201)
    ).body as { id: string };

    const echoes = await echoFor(created.id);
    expect(
      echoes.some(
        (echo) => echo.topic === 'walking' && echo.kind === 'forward' && echo.status === 'active',
      ),
    ).toBe(true);
  });

  // -----------------------------------------------------------------------------------------
  // Consumer 3: the topics listing
  // -----------------------------------------------------------------------------------------
  it('topics listing: entry counts aggregate the canonical topic and its alias', async () => {
    for (let index = 0; index < 3; index += 1) {
      await write(`A walk, day ${index}.`, ['content']);
    }
    await insights();

    const before = await listTopics();
    const walking = before.find((topic) => topic.name === 'walking')!;
    expect(walking.entry_count).toBe(3);
    expect(before.some((topic) => topic.name === 'strolling')).toBe(false);

    await addAlias(walking.id, 'strolling');
    await write('A strolling loop by the lake.', ['content']);
    await insights(); // A4-04: the alias takes effect on this recompute

    const after = await listTopics();
    // Still one row for the idea — the alias never grew a topic row of its own.
    expect(after.some((topic) => topic.name === 'strolling')).toBe(false);
    const merged = after.find((topic) => topic.name === 'walking')!;
    expect(merged.aliases).toContain('strolling');
    expect(merged.entry_count).toBe(4);
  });

  // -----------------------------------------------------------------------------------------
  // Consumer 4: when the edit takes effect
  // -----------------------------------------------------------------------------------------
  it('context: an alias takes effect on the next insights computation, not before', async () => {
    for (let index = 0; index < 3; index += 1) {
      await write(`A walk, day ${index}.`, ['content']);
    }
    await insights();
    const walkingId = (await listTopics()).find((topic) => topic.name === 'walking')!.id;

    // Written before the alias exists: nothing recognises "strolling" yet, so this entry gets no
    // topic link at all (not even a fragment row of its own — the keyword extractor only creates a
    // row for a phrase it has a rule for).
    await write('A strolling loop by the lake.', ['content']);
    expect((await listTopics()).find((topic) => topic.name === 'walking')!.entry_count).toBe(3);

    await addAlias(walkingId, 'strolling');

    // The Topics screen promises "counted as one from the next time Insights is opened" — not
    // immediately. Adding the alias only edits the alias table; nothing has re-scanned the diary yet.
    const stillBefore = await listTopics();
    expect(stillBefore.find((topic) => topic.name === 'walking')!.entry_count).toBe(3);

    // The next insights computation is what applies it.
    await insights();
    const after = await listTopics();
    expect(after.find((topic) => topic.name === 'walking')!.entry_count).toBe(4);
  });

  // -----------------------------------------------------------------------------------------
  // Normalisation hygiene: case never splits identity
  // -----------------------------------------------------------------------------------------
  it('case variants of the same topic never split counts', async () => {
    await write('A WALK before breakfast.', ['content']);
    await write('Went Walking after dinner.', ['content']);
    await write('another walking loop.', ['content']);

    const found = await insights();
    const walkingPatterns = found.patterns.filter(
      (p) => p.topic === 'walking' && p.kind === 'forward',
    );
    expect(walkingPatterns).toHaveLength(1);
    expect(walkingPatterns[0].occurrence_count).toBe(3);

    // The same rule applies to an alias typed in a different case than it is stored in, and to
    // entry text in yet another case than either.
    await insights();
    const walkingId = (await listTopics()).find((topic) => topic.name === 'walking')!.id;
    const updated = await addAlias(walkingId, 'Strolling');
    expect(updated.aliases).toEqual(['strolling']); // stored lowercase, not "Strolling"

    await write('A STROLLING afternoon.', ['content']);
    await insights();

    const after = await listTopics();
    expect(after.some((topic) => topic.name === 'strolling')).toBe(false);
    expect(after.find((topic) => topic.name === 'walking')!.entry_count).toBe(4);
  });

  // -----------------------------------------------------------------------------------------
  // Acceptance criterion, verbatim: alias "strolling" → "walking", an entry mentioning the alias,
  // a recompute — the walking pattern's counts include it. (Replaces the issue's curl sequence —
  // see PR description.)
  // -----------------------------------------------------------------------------------------
  it('e2e: adding alias "strolling" → "walking" folds a new "strolling" entry into the walking pattern', async () => {
    for (let index = 0; index < 3; index += 1) {
      await write(`A walk, day ${index}.`, ['content']);
    }
    for (let index = 0; index < 3; index += 1) {
      await write(`A long day at work, number ${index}.`, ['stressed']);
    }

    const before = find(await insights(), 'walking')!;
    expect(before.occurrence_count).toBe(3);

    const walkingId = (await listTopics()).find((topic) => topic.name === 'walking')!.id;
    await addAlias(walkingId, 'strolling');

    await write('A long strolling session with the dog.', ['content']);

    const after = find(await insights(), 'walking')!;
    expect(after.occurrence_count).toBe(4);
    expect(after.present_count).toBe(4);
  });
});

// Note for a future reader: every alias exercised above is one whose text has not already become a
// topic row of its own. `TopicsService.addAlias` rejects an alias string that already names another
// topic (see roadmap-engine.test.ts, "rejects an alias already spoken for"), so two topic rows that
// already exist independently cannot be folded together through this endpoint. Merging pre-existing
// rows is `mergeFragmentedTopics`'s job, and it only does so automatically when `canonicalTopicName`
// finds a rule connecting them — curated membership, an existing alias, or shared stems — never on
// the strength of an unrelated pair of words like "walking" and "strolling". A merge-suggestion UI
// for that case is explicitly out of scope for #22.
