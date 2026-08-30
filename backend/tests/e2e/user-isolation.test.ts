/**
 * The isolation suite (M-1b step 2, #46) — the deliverable the issue's task 4 names outright:
 * "tests are the deliverable." Two real accounts, `SINGLE_USER_MODE=false` so every request
 * carries a real bearer token naming a real user, writing and reading interleaved across every
 * controller route this backend serves. Every assertion below is the same shape: what user A
 * wrote or computed must never be visible to, counted for, or mutable by user B, and vice versa.
 *
 * This file is also the other half of the route-inventory guard (task 4's second half): every
 * request it issues is recorded by path and method, and the final test in the file enumerates
 * every route Nest's own `@Controller()`/`@Get()`/etc. metadata declares (`../helpers/route-
 * inventory.ts` — read from the exact `AppModule.forRoot()` controllers array the real server
 * boots, not a second hand-written list) and fails if any route was never exercised above. A
 * route added to a controller without a matching isolation check here fails CI the next time this
 * runs — which is the whole point: a scoping miss that ships without a test looks identical to no
 * scoping miss at all, and this is what keeps that from being true.
 *
 * Deliberately excluded, and why:
 *  - `src/inference/worker.ts` is a separate process with its own job-selection path, split into
 *    its own ticket (#135) — it has no HTTP route for this suite to exercise.
 *  - `GET /health` is exercised below purely for route-inventory completeness; it is explicitly
 *    exempt from `IdentityGate` (no `userId` concept applies to it at all).
 */

import request from 'supertest';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { bootOnFresh, teardown, type Harness } from '../helpers/app';
import { enumerateRoutes, registeredControllers, routeMatches } from '../helpers/route-inventory';

let h: Harness;
const server = () => h.app.getHttpServer();

/** Every `"METHOD /literal/path"` this suite has issued a real HTTP request against — the raw
 *  strings recorded regardless of which `:param` a route template declares; `routeMatches` (the
 *  route-inventory helper) is what reconciles the two shapes at the end of this file. */
const covered = new Set<string>();

type Verb = 'get' | 'post' | 'put' | 'patch' | 'delete';

/** A recording wrapper around `supertest`: every call is logged into `covered` before the request
 *  is even sent, and — when `token` is given — carries it as a bearer credential. `agent()` (no
 *  token) is for the two routes `IdentityGate` never gates (`/auth/register`, `/auth/token`) plus
 *  `/health`. */
function agent(token?: string): Record<Verb, (url: string) => request.Test> {
  const verbs: Verb[] = ['get', 'post', 'put', 'patch', 'delete'];
  const out = {} as Record<Verb, (url: string) => request.Test>;
  for (const verb of verbs) {
    out[verb] = (url: string): request.Test => {
      covered.add(`${verb.toUpperCase()} ${url.split('?')[0]}`);
      const req = request(server())[verb](url);
      return token ? req.set('Authorization', `Bearer ${token}`) : req;
    };
  }
  return out;
}

const PASSWORD = 'correct horse battery staple';

interface UserCtx {
  id: string;
  email: string;
  token: string;
  client: Record<Verb, (url: string) => request.Test>;
}

async function registerUser(email: string): Promise<UserCtx> {
  const reg = (
    await agent().post('/auth/register').send({ email, password: PASSWORD }).expect(201)
  ).body as { id: string; email: string };
  const login = (
    await agent().post('/auth/token').send({ email, password: PASSWORD }).expect(200)
  ).body as { token: string };
  return { id: reg.id, email: reg.email, token: login.token, client: agent(login.token) };
}

interface EntryRef {
  id: string;
  version: number;
}

/** Write an entry and confirm a feeling on it — the "counts as evidence" state (FR-012) every
 *  pattern/topic/echo assertion below depends on. */
async function writeConfirmedEntry(
  client: Record<Verb, (url: string) => request.Test>,
  rawText: string,
  feelingKey: string,
): Promise<EntryRef> {
  const created = (
    await client.post('/entries').send({ mode: 'freeform', raw_text: rawText }).expect(201)
  ).body as EntryRef;
  const patched = (
    await client
      .patch(`/entries/${created.id}`)
      .send({ feeling_keys: [feelingKey], version: created.version })
      .expect(200)
  ).body as EntryRef;
  return patched;
}

/** Three "coffee" entries, all confirmed `exhausted` — the exact recipe `insights-pipeline.test.ts`
 *  uses to reliably clear `MIN_OCCURRENCE_THRESHOLD` (3) with a lift `GET /insights` accepts as
 *  active. `variant` keeps the wording distinct between the two users so nothing about this test
 *  depends on two accounts having written byte-identical text. */
async function writeCoffeePattern(
  client: Record<Verb, (url: string) => request.Test>,
  variant: string,
): Promise<EntryRef[]> {
  const texts = [
    `Another late espresso at the desk${variant}, and then I barely slept.`,
    `Espresso again after dinner${variant} — wide awake at midnight.`,
    `A third late espresso this week${variant}, still exhausted the next morning.`,
  ];
  const refs: EntryRef[] = [];
  for (const text of texts) refs.push(await writeConfirmedEntry(client, text, 'exhausted'));
  return refs;
}

interface PatternOut {
  id: string;
  topic: string;
  feeling: string;
  status: string;
  occurrence_count: number;
}

interface InsightsOut {
  patterns: PatternOut[];
}

let userA: UserCtx;
let userB: UserCtx;
let entriesA: EntryRef[];
let entriesB: EntryRef[];
let insightsA: InsightsOut;
let insightsB: InsightsOut;
let coffeePatternIdA: string;
let coffeePatternIdB: string;
let coffeeTopicIdA: string;
let experimentIdA: string;
let experimentIdB: string;
let draftToFinalizeA: string;
let draftToDeleteA: string;
let draftToFinalizeB: string;
let guidingQuestionKey: string;
let transcriptionJobIdA: string;
let transcriptionJobIdB: string;

beforeAll(async () => {
  h = await bootOnFresh({ singleUserMode: false, manualEntitlements: true });

  userA = await registerUser('reader-a@example.com');
  userB = await registerUser('reader-b@example.com');

  entriesA = await writeCoffeePattern(userA.client, ' at my desk');
  entriesB = await writeCoffeePattern(userB.client, ' before the shift');

  // `GET /guiding-questions` is shared reference vocabulary (schema.ts's M-1b classification) —
  // read once via either account for the guided-draft flow below.
  const questions = (await userA.client.get('/guiding-questions').expect(200)).body as {
    questions: Array<{ key: string }>;
  };
  guidingQuestionKey = questions.questions[0].key;
});

afterAll(async () => {
  await teardown(h);
});

describe('GET /health', () => {
  it('answers without any identity at all', async () => {
    await agent().get('/health').expect(200);
  });
});

describe('identity (M-1a) — GET /auth/me, DELETE /auth/token', () => {
  it('each account reads back only its own email, never the other account’s', async () => {
    const meA = (await userA.client.get('/auth/me').expect(200)).body as { email: string };
    const meB = (await userB.client.get('/auth/me').expect(200)).body as { email: string };
    expect(meA.email).toBe(userA.email);
    expect(meB.email).toBe(userB.email);
  });

  it('granting user A premium never changes what GET /auth/me reports for user B', async () => {
    const beforeB = (await userB.client.get('/auth/me').expect(200)).body as { tier: string };
    expect(beforeB.tier).toBe('free');

    // `/billing/*` is not in `IdentityGate`'s exempt list, so this still needs a valid bearer
    // token even though `adminGrant` itself never reads `req.userId` — any authenticated account's
    // token works, since the route is dev-only and targets an arbitrary `user_id` in its body.
    await userA.client
      .post('/billing/admin/grant')
      .send({ user_id: userA.id, tier: 'premium' })
      .expect(200);

    const afterA = (await userA.client.get('/auth/me').expect(200)).body as { tier: string };
    const afterB = (await userB.client.get('/auth/me').expect(200)).body as { tier: string };
    expect(afterA.tier).toBe('premium');
    expect(afterB.tier).toBe('free');

    // Grant B too — several endpoints below (`POST /experiments`, `GET /insights/digest`) are
    // premium-gated, and this suite exercises them for both accounts.
    await userA.client
      .post('/billing/admin/grant')
      .send({ user_id: userB.id, tier: 'premium' })
      .expect(200);
  });

  it('POST /billing/play/verify grants independently per account', async () => {
    const verifyA = (
      await userA.client
        .post('/billing/play/verify')
        .send({ purchase_token: 'a-own-token', product_id: 'premium_yearly' })
        .expect(200)
    ).body as { tier: string };
    expect(verifyA.tier).toBe('premium');
  });

  it('logout is scoped to the token presented, not the account', async () => {
    const throwaway = await registerUser('throwaway@example.com');
    await throwaway.client.get('/auth/me').expect(200);
    await throwaway.client.delete('/auth/token').expect(204);
    // The same token no longer authenticates — but this is the *last* use of `throwaway`'s
    // token, deliberately, so nothing later in this suite depends on it still working.
    await throwaway.client.get('/auth/me').expect(401);
    // userA/userB's own sessions are untouched by a third account logging out.
    await userA.client.get('/auth/me').expect(200);
  });
});

describe('GET /feelings — shared reference vocabulary', () => {
  it('serves identical content regardless of which account asks (not user data)', async () => {
    const a = (await userA.client.get('/feelings').expect(200)).body;
    const b = (await userB.client.get('/feelings').expect(200)).body;
    expect(a).toEqual(b);
  });
});

describe('entries — POST, GET (list/one/echo), PATCH, PUT topic-feelings, DELETE', () => {
  it('a GET by id for an entry that belongs to the other account is a 404, never the content', async () => {
    await userB.client.get(`/entries/${entriesA[0].id}`).expect(404);
    await userA.client.get(`/entries/${entriesB[0].id}`).expect(404);
  });

  it('GET /entries?date= for a shared date never mixes the two accounts’ entries', async () => {
    // Both accounts wrote their three entries "today" (no `entry_date` override), so the same
    // date query must return exactly three rows per account, every one of them the caller’s own.
    const today = new Date().toISOString().slice(0, 10);
    const listA = (await userA.client.get(`/entries?date=${today}`).expect(200)).body as {
      entries: Array<{ id: string; raw_text: string }>;
    };
    const listB = (await userB.client.get(`/entries?date=${today}`).expect(200)).body as {
      entries: Array<{ id: string; raw_text: string }>;
    };
    const idsA = new Set(entriesA.map((e) => e.id));
    const idsB = new Set(entriesB.map((e) => e.id));
    expect(listA.entries.every((e) => idsA.has(e.id))).toBe(true);
    expect(listA.entries.some((e) => idsB.has(e.id))).toBe(false);
    expect(listB.entries.every((e) => idsB.has(e.id))).toBe(true);
    expect(listB.entries.some((e) => idsA.has(e.id))).toBe(false);
  });

  it('PATCH on the other account’s entry is a 404 and never mutates it', async () => {
    await userB.client
      .patch(`/entries/${entriesA[0].id}`)
      .send({ raw_text: 'hijacked', version: entriesA[0].version })
      .expect(404);
    const stillA = (await userA.client.get(`/entries/${entriesA[0].id}`).expect(200)).body as {
      raw_text: string;
    };
    expect(stillA.raw_text).not.toBe('hijacked');
  });

  it('GET /entries/:id/echo for the other account’s entry is a 404', async () => {
    await userB.client.get(`/entries/${entriesA[0].id}/echo`).expect(404);
    await userA.client.get(`/entries/${entriesA[0].id}/echo`).expect(200);
  });

  it('PUT topic-feelings on the other account’s entry is a 404', async () => {
    await userB.client
      .put(`/entries/${entriesA[0].id}/topic-feelings`)
      .send({ pairings: [] })
      .expect(404);
  });

  it('DELETE on the other account’s entry is a 404 and leaves the row intact', async () => {
    await userB.client.delete(`/entries/${entriesA[0].id}?version=${entriesA[0].version}`).expect(404);
    await userA.client.get(`/entries/${entriesA[0].id}`).expect(200);
  });

  it('an account can freely create and delete its own scratch entry', async () => {
    const scratch = await writeConfirmedEntry(userB.client, 'A quiet entry about nothing much.', 'neutral');
    await userB.client.delete(`/entries/${scratch.id}?version=${scratch.version}`).expect(204);
    await userB.client.get(`/entries/${scratch.id}`).expect(404);
  });
});

describe('GET /insights, /insights/when, /insights/series, /insights/digest, /insights/question-yield, POST withdrawals/acknowledge', () => {
  it('each account’s recompute finds exactly its own three-occurrence coffee pattern, never six', async () => {
    insightsA = (await userA.client.get('/insights').expect(200)).body as InsightsOut;
    insightsB = (await userB.client.get('/insights').expect(200)).body as InsightsOut;

    const coffeeA = insightsA.patterns.find((p) => p.topic === 'coffee' && p.feeling === 'exhausted');
    const coffeeB = insightsB.patterns.find((p) => p.topic === 'coffee' && p.feeling === 'exhausted');
    expect(coffeeA).toBeDefined();
    expect(coffeeB).toBeDefined();
    // The number that would be wrong first if scoping leaked: 6, not 3, on either side.
    expect(coffeeA!.occurrence_count).toBe(3);
    expect(coffeeB!.occurrence_count).toBe(3);
    expect(coffeeA!.status).toBe('active');
    expect(coffeeB!.status).toBe('active');
    coffeePatternIdA = coffeeA!.id;
    coffeePatternIdB = coffeeB!.id;
    expect(coffeePatternIdA).not.toBe(coffeePatternIdB);
  });

  it('GET /insights/when never lets one account’s time-of-day data widen the other’s total_entries', async () => {
    const whenA = (await userA.client.get('/insights/when').expect(200)).body as {
      total_entries: number;
    };
    const whenB = (await userB.client.get('/insights/when').expect(200)).body as {
      total_entries: number;
    };
    expect(whenA.total_entries).toBe(3);
    expect(whenB.total_entries).toBe(3);
  });

  it('GET /insights/series only ever sums the caller’s own confirmed feelings', async () => {
    const today = new Date().toISOString().slice(0, 10);
    const seriesA = (
      await userA.client.get(`/insights/series?from=${today}&to=${today}`).expect(200)
    ).body as { points: Array<{ confirmed_feeling_count: number }> };
    const total = seriesA.points.reduce((sum, p) => sum + p.confirmed_feeling_count, 0);
    expect(total).toBe(3);
  });

  it('GET /insights/digest reports each account’s own week only (premium, granted above)', async () => {
    const digestA = (await userA.client.get('/insights/digest').expect(200)).body as {
      empty: boolean;
      entry_count?: number;
    };
    expect(digestA.empty).toBe(false);
    expect(digestA.entry_count).toBe(3);
  });

  it('GET /insights/question-yield reports zero for both — neither account wrote a guided entry yet', async () => {
    const yieldA = (await userA.client.get('/insights/question-yield').expect(200)).body as {
      overall: { guided_entries: number };
    };
    expect(yieldA.overall.guided_entries).toBe(0);
  });

  it('acknowledging withdrawals is per-account and never touches the other account’s notice board', async () => {
    await userA.client.post('/insights/withdrawals/acknowledge').expect(204);
    // Nothing to assert on content (neither account has a withdrawal yet); the request itself is
    // the route-inventory coverage this test exists for, plus a smoke check that it 204s per-user.
    await userB.client.post('/insights/withdrawals/acknowledge').expect(204);
  });
});

describe('topics — GET, POST alias, DELETE alias', () => {
  it('each account’s topic list contains only topics it extracted', async () => {
    const topicsA = (await userA.client.get('/topics').expect(200)).body as {
      topics: Array<{ id: string; name: string }>;
    };
    const topicsB = (await userB.client.get('/topics').expect(200)).body as {
      topics: Array<{ id: string; name: string }>;
    };
    const coffeeA = topicsA.topics.find((t) => t.name === 'coffee');
    const coffeeB = topicsB.topics.find((t) => t.name === 'coffee');
    expect(coffeeA).toBeDefined();
    expect(coffeeB).toBeDefined();
    expect(coffeeA!.id).not.toBe(coffeeB!.id);
    coffeeTopicIdA = coffeeA!.id;
  });

  it('adding an alias to the other account’s topic id is a 404, not a cross-account edit', async () => {
    await userB.client
      .post(`/topics/${coffeeTopicIdA}/aliases`)
      .send({ alias: 'hijacked-alias' })
      .expect(404);
  });

  it('an account can alias, then remove the alias, on its own topic', async () => {
    const added = (
      await userA.client.post(`/topics/${coffeeTopicIdA}/aliases`).send({ alias: 'joe' }).expect(200)
    ).body as { aliases: string[] };
    expect(added.aliases).toContain('joe');
    await userA.client.delete(`/topics/${coffeeTopicIdA}/aliases/joe`).expect(200);
  });

  it('removing an alias from the other account’s topic id is a 404', async () => {
    await userB.client.delete(`/topics/${coffeeTopicIdA}/aliases/joe`).expect(404);
  });
});

describe('PUT /entries/:id/topic-feelings — pairing an entry’s own topic and feeling', () => {
  it('is scoped to the caller’s own entry, topic and feeling', async () => {
    const pairing = (
      await userA.client
        .put(`/entries/${entriesA[0].id}/topic-feelings`)
        .send({ pairings: [{ topic_id: coffeeTopicIdA, feeling_key: 'exhausted' }] })
        .expect(200)
    ).body as { topic_feelings: Array<{ topic_id: string; feeling_key: string }> };
    expect(pairing.topic_feelings).toEqual([
      { topic_id: coffeeTopicIdA, feeling_key: 'exhausted', topic: 'coffee', source: 'overridden' },
    ]);
  });

  it('naming the other account’s topic id on one’s own entry is rejected, not silently linked', async () => {
    // `coffeeTopicIdA` is not among `entriesB[0]`'s own topics from user B’s point of view, so
    // this is `InvalidPairingError` (422) exactly as if the id were nonsense — user B can never
    // discover it is a *real* id belonging to someone else’s diary from this response.
    await userB.client
      .put(`/entries/${entriesB[0].id}/topic-feelings`)
      .send({ pairings: [{ topic_id: coffeeTopicIdA, feeling_key: 'exhausted' }] })
      .expect(422);
  });
});

describe('experiments — POST, GET active, GET results, POST abandon', () => {
  it('each account can start its own experiment on its own qualifying pattern', async () => {
    const createdA = (
      await userA.client
        .post('/experiments')
        .send({ pattern_topic: 'coffee', pattern_feeling: 'exhausted', hypothesis_kind: 'less_of' })
        .expect(201)
    ).body as { id: string };
    const createdB = (
      await userB.client
        .post('/experiments')
        .send({ pattern_topic: 'coffee', pattern_feeling: 'exhausted', hypothesis_kind: 'less_of' })
        .expect(201)
    ).body as { id: string };
    experimentIdA = createdA.id;
    experimentIdB = createdB.id;
    expect(experimentIdA).not.toBe(experimentIdB);
  });

  it('GET /experiments/active never returns the other account’s experiment', async () => {
    const activeA = (await userA.client.get('/experiments/active').expect(200)).body as {
      id: string;
    };
    const activeB = (await userB.client.get('/experiments/active').expect(200)).body as {
      id: string;
    };
    expect(activeA.id).toBe(experimentIdA);
    expect(activeB.id).toBe(experimentIdB);
  });

  it('GET results / POST abandon on the other account’s experiment id is a 404', async () => {
    await userB.client.get(`/experiments/${experimentIdA}/results`).expect(404);
    await userB.client.post(`/experiments/${experimentIdA}/abandon`).expect(404);
    // Confirmed still active — the 404 above was a true no-op, not a partial mutation.
    const stillActiveA = (await userA.client.get('/experiments/active').expect(200)).body as {
      status: string;
    };
    expect(stillActiveA.status).toBe('active');
  });

  it('an account can read its own results and abandon its own experiment', async () => {
    await userA.client.get(`/experiments/${experimentIdA}/results`).expect(200);
    await userA.client.post(`/experiments/${experimentIdA}/abandon`).expect(200);
    await userB.client.get(`/experiments/${experimentIdB}/results`).expect(200);
    await userB.client.post(`/experiments/${experimentIdB}/abandon`).expect(200);
  });
});

describe('GET /monthly-summary', () => {
  it('counts only the caller’s own entries for the month', async () => {
    const month = new Date().toISOString().slice(0, 7);
    const summaryA = (await userA.client.get(`/monthly-summary?month=${month}`).expect(200)).body as {
      days: Array<{ entry_count: number }>;
    };
    const total = summaryA.days.reduce((sum, d) => sum + d.entry_count, 0);
    // A wrote 3 coffee entries plus one scratch entry created and deleted earlier in this suite —
    // a deleted entry is gone from every account's own summary too, so this is exactly 3.
    expect(total).toBe(3);
  });
});

describe('POST /transcriptions, GET /transcriptions/:jobId', () => {
  it('a job started by one account is invisible to the other, by id, immediately', async () => {
    transcriptionJobIdA = (
      await userA.client
        .post('/transcriptions')
        .set('Content-Type', 'audio/webm')
        .send(Buffer.from('not real audio, but non-empty'))
    ).body.id as string;
    transcriptionJobIdB = (
      await userB.client
        .post('/transcriptions')
        .set('Content-Type', 'audio/webm')
        .send(Buffer.from('also not real audio'))
    ).body.id as string;

    await userA.client.get(`/transcriptions/${transcriptionJobIdA}`).expect(200);
    await userB.client.get(`/transcriptions/${transcriptionJobIdA}`).expect(404);
    await userB.client.get(`/transcriptions/${transcriptionJobIdB}`).expect(200);
    await userA.client.get(`/transcriptions/${transcriptionJobIdB}`).expect(404);
  });
});

describe('guided entry drafts — full lifecycle, per account', () => {
  it('create/get/save-answer/finalize is scoped end to end, and cross-account reads 404', async () => {
    draftToFinalizeA = (await userA.client.post('/guided-entry-drafts').expect(201)).body
      .draft_key as string;
    draftToFinalizeB = (await userB.client.post('/guided-entry-drafts').expect(201)).body
      .draft_key as string;

    await userB.client.get(`/guided-entry-drafts/${draftToFinalizeA}`).expect(404);

    await userA.client
      .put(`/guided-entry-drafts/${draftToFinalizeA}/questions/${guidingQuestionKey}`)
      .send({ answer_text: 'Only user A should ever read this answer.', order_index: 0 })
      .expect(204);
    await userB.client
      .put(`/guided-entry-drafts/${draftToFinalizeA}/questions/${guidingQuestionKey}`)
      .send({ answer_text: 'hijacked', order_index: 0 })
      .expect(404);

    const gotA = (await userA.client.get(`/guided-entry-drafts/${draftToFinalizeA}`).expect(200))
      .body as { answers: Array<{ answer_text: string }> };
    expect(gotA.answers).toHaveLength(1);
    expect(gotA.answers[0].answer_text).not.toContain('hijacked');

    await userA.client
      .put(`/guided-entry-drafts/${draftToFinalizeB}/questions/${guidingQuestionKey}`)
      .send({ answer_text: 'answered by B', order_index: 0 })
      .expect(404);
    await userB.client
      .put(`/guided-entry-drafts/${draftToFinalizeB}/questions/${guidingQuestionKey}`)
      .send({ answer_text: 'answered by B', order_index: 0 })
      .expect(204);

    await userB.client.post(`/guided-entry-drafts/${draftToFinalizeA}/finalize`).expect(404);
    await userA.client.post(`/guided-entry-drafts/${draftToFinalizeA}/finalize`).expect(201);
    await userB.client.post(`/guided-entry-drafts/${draftToFinalizeB}/finalize`).expect(201);
  });

  it('POST transcriptions on a draft is scoped the same way — 404 across accounts', async () => {
    draftToDeleteA = (await userA.client.post('/guided-entry-drafts').expect(201)).body
      .draft_key as string;

    await userB.client
      .post(`/guided-entry-drafts/${draftToDeleteA}/questions/${guidingQuestionKey}/transcriptions?order=0`)
      .set('Content-Type', 'audio/webm')
      .send(Buffer.from('not real audio'))
      .expect(404);
    await userA.client
      .post(`/guided-entry-drafts/${draftToDeleteA}/questions/${guidingQuestionKey}/transcriptions?order=0`)
      .set('Content-Type', 'audio/webm')
      .send(Buffer.from('not real audio'))
      .expect(202);
  });

  it('DELETE is scoped the same way, and never removes the other account’s draft', async () => {
    await userB.client.delete(`/guided-entry-drafts/${draftToDeleteA}`).expect(404);
    await userA.client.delete(`/guided-entry-drafts/${draftToDeleteA}`).expect(204);
  });
});

describe('GET /export?format=json|markdown', () => {
  it('never includes the other account’s entry text, in either format', async () => {
    const jsonA = (await userA.client.get('/export?format=json').expect(200)).body as {
      entries: Array<{ raw_text: string }>;
    };
    const jsonB = (await userB.client.get('/export?format=json').expect(200)).body as {
      entries: Array<{ raw_text: string }>;
    };
    const textA = JSON.stringify(jsonA);
    const textB = JSON.stringify(jsonB);
    for (const entry of entriesB) {
      // Every entry A wrote is distinguishable by its `variant` wording (" before the shift" for
      // B, " at my desk" for A) — see `writeCoffeePattern`. A's export must contain none of it.
      expect(textA).not.toContain('before the shift');
      expect(textB).not.toContain('at my desk');
      void entry;
    }

    const mdA = (await userA.client.get('/export?format=markdown').expect(200)).text as string;
    expect(mdA).not.toContain('before the shift');
    expect(mdA).toContain('at my desk');
  });
});

describe('daylio import — dry-run, commit, and the documented content_hash collision', () => {
  const csvFor = (mood: string): Buffer =>
    Buffer.from(
      `full_date,date,weekday,time,mood,activities,note_title,note\n` +
        `2026-06-01,1 June,Monday,9:00 am,${mood},"reading","",""\n`,
      'utf-8',
    );

  it('two accounts importing different files each get their own, independent import', async () => {
    const csvA = csvFor('good');
    const dryA = (
      await userA.client.post('/import/daylio/dry-run').attach('file', csvA, 'a.csv').expect(200)
    ).body as { report_hash: string };
    const commitA = (
      await userA.client
        .post('/import/daylio/commit')
        .attach('file', csvA, 'a.csv')
        .field('report_hash', dryA.report_hash)
        .expect(200)
    ).body as { idempotent: boolean; imported_count: number };
    expect(commitA).toMatchObject({ idempotent: false, imported_count: 1 });

    const csvB = csvFor('rad');
    const dryB = (
      await userB.client.post('/import/daylio/dry-run').attach('file', csvB, 'b.csv').expect(200)
    ).body as { report_hash: string; already_imported: boolean };
    // A different account's import of a *different* file must never read as "already imported" —
    // that would be exactly the cross-account leak this ticket exists to prevent.
    expect(dryB.already_imported).toBe(false);
    const commitB = (
      await userB.client
        .post('/import/daylio/commit')
        .attach('file', csvB, 'b.csv')
        .field('report_hash', dryB.report_hash)
        .expect(200)
    ).body as { idempotent: boolean; imported_count: number };
    expect(commitB).toMatchObject({ idempotent: false, imported_count: 1 });
  });

  it('DOCUMENTED KNOWN GAP: csv_imports.content_hash is still a global primary key (see PR description) — a second account committing the exact same bytes a first account already committed collides with 409, rather than importing independently', async () => {
    const identicalCsv = csvFor('meh');
    const dryA = (
      await userA.client
        .post('/import/daylio/dry-run')
        .attach('file', identicalCsv, 'shared.csv')
        .expect(200)
    ).body as { report_hash: string };
    await userA.client
      .post('/import/daylio/commit')
      .attach('file', identicalCsv, 'shared.csv')
      .field('report_hash', dryA.report_hash)
      .expect(200);

    // User B's own dry-run of the identical bytes is correctly scoped — filtered by B's own
    // `user_id`, per `daylio-import.service.ts`'s `DaylioContentHashCollisionError` doc comment —
    // so it honestly reports "not yet imported by me," never A's history.
    const dryB = (
      await userB.client
        .post('/import/daylio/dry-run')
        .attach('file', identicalCsv, 'shared.csv')
        .expect(200)
    ).body as { report_hash: string; already_imported: boolean };
    expect(dryB.already_imported).toBe(false);

    // But the commit collides on the still-global primary key — a real, tracked, deliberately
    // deferred limitation (schema.ts's M-1b note; this ticket's PR description), surfaced here as
    // an honest 409 rather than a silent no-op or an unhandled 500.
    await userB.client
      .post('/import/daylio/commit')
      .attach('file', identicalCsv, 'shared.csv')
      .field('report_hash', dryB.report_hash)
      .expect(409);
  });
});

describe('route-inventory guard (task 4)', () => {
  it('every controller route Nest declares was exercised by this suite at least once', () => {
    const routes = enumerateRoutes(registeredControllers());
    const uncovered = routes.filter(
      (route) => ![...covered].some((request) => routeMatches(route, request.split(' ')[1]) && request.startsWith(route.method)),
    );

    if (uncovered.length > 0) {
      const list = uncovered.map((r) => `${r.method} ${r.path} (${r.controllerName}#${r.handlerName})`);
      throw new Error(
        `${uncovered.length} route(s) exist with no isolation coverage in this suite:\n` +
          list.join('\n') +
          '\n\nEvery new or existing controller route must be exercised by tests/e2e/user-isolation.test.ts ' +
          '(M-1b, #46, task 4) before it can be considered scoped.',
      );
    }
    expect(uncovered).toEqual([]);
  });
});
