/**
 * T033 / T037 / T073 — the write path: the version rule, the 409 body, and the derived values a
 * guided entry produces.
 *
 * Ported from `backend/tests/unit/test_version_conflict.py`,
 * `backend/tests/contract/test_entries_{create,update,delete}.py` and `test_entries_conflict.py`.
 */

import request from 'supertest';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { bootOnCopy, teardown, type Harness } from '../helpers/app';
import { localDateString, utcDateString } from '../helpers/dates';

let h: Harness;
const server = () => h.app.getHttpServer();

beforeEach(async () => {
  h = await bootOnCopy();
});
afterEach(async () => {
  await teardown(h);
});

const create = async (raw_text: string) =>
  (await request(server()).post('/entries').send({ mode: 'freeform', raw_text }).expect(201)).body;

describe('POST /entries', () => {
  it('returns 201 with the full entry shape and version 1', async () => {
    const body = await create('A quiet day.');
    expect(body.version).toBe(1);
    expect(body.feeling_source).toBe('suggested');
    expect(body.suggested_feeling.key).toBe(body.feeling_key);
  });

  it('leaves an empty entry unclassified', async () => {
    const body = (await request(server()).post('/entries').send({ mode: 'freeform', raw_text: '' }))
      .body;
    expect(body.feeling_source).toBe('unset');
    expect(body.feeling_key).toBeNull();
  });

  it('stamps updated_at later than created_at once a feeling is suggested', async () => {
    // Two writes: the entry is stored first, then updated with the suggestion, so writing is never
    // blocked on the network — the entry survives even if the suggestion call fails.
    const body = await create('Coffee then a walk.');
    const listed = await request(server()).get(`/entries?date=${body.entry_date}`);
    expect(listed.body.entries.some((e: { id: string }) => e.id === body.id)).toBe(true);
  });
});

describe('POST /entries — entry_date (#36)', () => {
  it('omitted, files the entry under today, exactly as before', async () => {
    const body = await create('A quiet day.');
    expect(body.entry_date).toBe(localDateString(0));
  });

  it('accepts an explicit past date and files the entry under it, leaving created_at at now', async () => {
    const target = localDateString(-3);
    const body = (
      await request(server())
        .post('/entries')
        .send({ mode: 'freeform', raw_text: 'Backdated.', entry_date: target })
        .expect(201)
    ).body;

    expect(body.entry_date).toBe(target);
    // created_at is a full timestamp; only its date component is compared, against *today* (not
    // the backdated entry_date) — the two are independent (data-model.md's existing distinction).
    // #125: created_at is written with nowUtc() (codecs.ts), so it must be checked against the
    // UTC date, not localDateString(0) — the two disagree between local midnight and UTC midnight,
    // which is exactly the window this assertion used to get wrong.
    expect(String(body.created_at).slice(0, 10)).toBe(utcDateString(0));
  });

  it('accepts a date exactly 30 days back — the inclusive boundary', async () => {
    const target = localDateString(-30);
    const body = (
      await request(server())
        .post('/entries')
        .send({ mode: 'freeform', raw_text: 'Right at the edge.', entry_date: target })
        .expect(201)
    ).body;

    expect(body.entry_date).toBe(target);
  });

  it('rejects a date 31 days back with a clear 422', async () => {
    const target = localDateString(-31);
    const res = await request(server())
      .post('/entries')
      .send({ mode: 'freeform', raw_text: 'Too far.', entry_date: target })
      .expect(422);

    expect(String(res.body.error?.message)).toMatch(/past/i);
  });

  it('rejects a future date with a clear 422', async () => {
    const target = localDateString(1);
    const res = await request(server())
      .post('/entries')
      .send({ mode: 'freeform', raw_text: 'From tomorrow.', entry_date: target })
      .expect(422);

    expect(String(res.body.error?.message)).toMatch(/future/i);
  });

  it('rejects a malformed entry_date at the schema layer', async () => {
    await request(server())
      .post('/entries')
      .send({ mode: 'freeform', raw_text: 'Bad shape.', entry_date: '26-08-2026' })
      .expect(422);
  });

  it('a rejected entry_date stores nothing — the entry never appears on any day', async () => {
    const target = localDateString(-45);
    await request(server())
      .post('/entries')
      .send({ mode: 'freeform', raw_text: 'Never stored.', entry_date: target })
      .expect(422);

    const listed = await request(server()).get(`/entries?date=${target}`);
    expect(
      listed.body.entries.some((e: { raw_text: string }) => e.raw_text === 'Never stored.'),
    ).toBe(false);
  });
});

describe('guided entries — derived values (data-model.md "Derived values")', () => {
  // This test boots on a *copy* of the golden fixture diary (`bootOnCopy`), not a fresh one --
  // deliberately, so the composed `raw_text` below is proof that the fixture's `guiding_questions`
  // come from the same seed a real diary gets. Before #95 this asserted the *old*, pre-#14 wording,
  // because the fixture generator forced three questions back to their pre-#14 prompt text to work
  // around `migrate.ts`'s guiding-question seeding being insert-only (a fixed-up copy change could
  // never reach an existing question row). #95 made that seeding refresh `prompt_text` on an
  // existing row the same way it already refreshed `feelings.label`, so the override is gone and
  // this fixture -- like any diary migrated with `npm run migrate-db` -- now carries current copy.
  // This assertion is therefore current #14 wording, not a special case.
  it('composes raw_text as one prompt/answer block per answer, blank line between', async () => {
    const body = (
      await request(server())
        .post('/entries')
        .send({
          mode: 'guided',
          raw_text: '',
          guided_answers: [
            { question_key: 'general_feeling', answer_text: 'Sluggish after lunch' },
            { question_key: 'mind_body', answer_text: 'Low energy and a little tense' },
          ],
        })
        .expect(201)
    ).body;

    expect(body.raw_text).toBe(
      'What happened since your last entry — and who was around?\n' +
        'Sluggish after lunch\n\n' +
        'What did you notice in your mind and body?\n' +
        'Low energy and a little tense',
    );
    expect(body.mode).toBe('guided');
  });

  it('falls back to the raw question key when the question is unknown', async () => {
    const body = (
      await request(server())
        .post('/entries')
        .send({
          mode: 'guided',
          raw_text: '',
          guided_answers: [{ question_key: 'not_a_real_question', answer_text: 'fallback case' }],
        })
        .expect(201)
    ).body;

    expect(body.raw_text).toBe('not_a_real_question\nfallback case');
  });

  it('keeps a submitted raw_text instead of composing over it', async () => {
    const body = (
      await request(server())
        .post('/entries')
        .send({
          mode: 'guided',
          raw_text: 'I wrote this myself',
          guided_answers: [{ question_key: 'general_feeling', answer_text: 'ignored' }],
        })
        .expect(201)
    ).body;

    expect(body.raw_text).toBe('I wrote this myself');
  });
});

describe('PATCH /entries/{id}', () => {
  it('confirms a suggested feeling', async () => {
    const entry = await create('Long day.');
    const res = await request(server())
      .patch(`/entries/${entry.id}`)
      .send({ feeling_key: entry.suggested_feeling.key, version: entry.version })
      .expect(200);
    expect(res.body.feeling_source).toBe('confirmed');
  });

  it('records a different choice as overridden', async () => {
    const entry = await create('Long day.');
    const other = entry.suggested_feeling.key === 'happy' ? 'sad' : 'happy';
    const res = await request(server())
      .patch(`/entries/${entry.id}`)
      .send({ feeling_key: other, version: entry.version })
      .expect(200);
    expect(res.body.feeling_key).toBe(other);
    expect(res.body.feeling_source).toBe('overridden');
  });

  it('increments the version on success', async () => {
    const entry = await create('Old text.');
    const res = await request(server())
      .patch(`/entries/${entry.id}`)
      .send({ raw_text: 'New text.', version: entry.version })
      .expect(200);
    expect(res.body.raw_text).toBe('New text.');
    expect(res.body.version).toBe(entry.version + 1);
  });

  it('rejects a missing version with 422', async () => {
    const entry = await create('x');
    const res = await request(server())
      .patch(`/entries/${entry.id}`)
      .send({ raw_text: 'no version' })
      .expect(422);
    expect(res.body.error.code).toBe('validation_error');
  });

  it('returns the contract 404 shape for an unknown entry', async () => {
    const res = await request(server())
      .patch('/entries/does-not-exist')
      .send({ raw_text: 'x', version: 1 })
      .expect(404);
    expect(res.body).toEqual({ error: { code: 'not_found', message: 'Entry not found' } });
  });

  it('rejects a feeling outside the backend-owned set', async () => {
    const entry = await create('Still valid.');
    await request(server())
      .patch(`/entries/${entry.id}`)
      .send({ feeling_key: 'invented-by-a-client', version: entry.version })
      .expect(422);
  });
});

describe('the 409 stale_entry response', () => {
  it('rejects a stale version', async () => {
    const entry = await create('Had a coke.');
    await request(server())
      .patch(`/entries/${entry.id}`)
      .send({ raw_text: 'First.', version: 1 })
      .expect(200);

    await request(server())
      .patch(`/entries/${entry.id}`)
      .send({ raw_text: 'Second.', version: 1 })
      .expect(409);
  });

  it('uses the stale_entry code and carries the current entry', async () => {
    const entry = await create('Had a coke.');
    await request(server())
      .patch(`/entries/${entry.id}`)
      .send({ raw_text: 'Server wins.', version: 1 });

    const res = await request(server())
      .patch(`/entries/${entry.id}`)
      .send({ raw_text: 'x', version: 1 });

    expect(res.body.error.code).toBe('stale_entry');
    expect(res.body.current.id).toBe(entry.id);
    expect(res.body.current.raw_text).toBe('Server wins.');
    expect(res.body.current.version).toBe(2);
  });

  // The three guarantees contracts/api.md makes.

  it('guarantee 1: a rejected mutation is a complete no-op', async () => {
    const entry = await create('Had a coke.');
    await request(server()).patch(`/entries/${entry.id}`).send({ raw_text: 'Kept.', version: 1 });

    await request(server())
      .patch(`/entries/${entry.id}`)
      .send({ raw_text: 'Discarded.', version: 1 });

    const current = await request(server()).get(`/entries/${entry.id}`);
    expect(current.body.raw_text).toBe('Kept.');
  });

  it('guarantee 2: a rejected attempt does not bump the stored version', async () => {
    const entry = await create('Had a coke.');
    await request(server()).patch(`/entries/${entry.id}`).send({ raw_text: 'Kept.', version: 1 });

    await request(server()).patch(`/entries/${entry.id}`).send({ raw_text: 'x', version: 1 });
    await request(server()).patch(`/entries/${entry.id}`).send({ raw_text: 'y', version: 1 });

    const current = await request(server()).get(`/entries/${entry.id}`);
    expect(current.body.version).toBe(2);
  });

  it('guarantee 3: the version from the 409 body is immediately reusable', async () => {
    const entry = await create('Had a coke.');
    await request(server()).patch(`/entries/${entry.id}`).send({ raw_text: 'Server.', version: 1 });
    const conflict = await request(server())
      .patch(`/entries/${entry.id}`)
      .send({ raw_text: 'Mine.', version: 1 });

    const retry = await request(server())
      .patch(`/entries/${entry.id}`)
      .send({ raw_text: 'Mine.', version: conflict.body.current.version })
      .expect(200);
    expect(retry.body.raw_text).toBe('Mine.');
  });
});

describe('DELETE /entries/{id}', () => {
  it('deletes with the current version', async () => {
    const entry = await create('Delete me.');
    await request(server()).delete(`/entries/${entry.id}?version=${entry.version}`).expect(204);
    await request(server()).get(`/entries/${entry.id}`).expect(404);
  });

  it('refuses a stale delete and keeps the entry (FR-021)', async () => {
    const entry = await create('Delete race.');
    await request(server())
      .patch(`/entries/${entry.id}`)
      .send({ raw_text: 'Changed.', version: 1 });

    const res = await request(server()).delete(`/entries/${entry.id}?version=1`).expect(409);
    expect(res.body.error.code).toBe('stale_entry');
    await request(server()).get(`/entries/${entry.id}`).expect(200);
  });

  it('rejects a missing version with 422 and keeps the entry', async () => {
    const entry = await create('Still here.');
    await request(server()).delete(`/entries/${entry.id}`).expect(422);
    await request(server()).get(`/entries/${entry.id}`).expect(200);
  });

  it('returns 404 for an unknown entry', async () => {
    await request(server()).delete('/entries/does-not-exist?version=1').expect(404);
  });

  it('cascades to guided answers rather than orphaning them', async () => {
    const entry = (
      await request(server())
        .post('/entries')
        .send({
          mode: 'guided',
          raw_text: '',
          guided_answers: [{ question_key: 'general_feeling', answer_text: 'gone soon' }],
        })
    ).body;

    await request(server()).delete(`/entries/${entry.id}?version=${entry.version}`).expect(204);
    // Foreign keys are off (see db/database.ts), so nothing removes these for us — orphaned rows
    // would accumulate silently and inflate later pattern counts.
    await request(server()).get(`/entries/${entry.id}`).expect(404);
  });
});

describe('PATCH /entries/{id} — a set of feelings', () => {
  it('stores every feeling sent, in the order it was sent', async () => {
    const created = await create('Rough morning, but the evening was lovely.');
    const patched = await request(server())
      .patch(`/entries/${created.id}`)
      .send({ feeling_keys: ['stressed', 'grateful', 'relieved'], version: created.version })
      .expect(422);
    // `relieved` is not in the vocabulary — the whole request is rejected rather than partly
    // applied, so the client never has to guess which of its feelings landed.
    expect(patched.body.error.code).toBe('validation_error');

    const ok = await request(server())
      .patch(`/entries/${created.id}`)
      .send({ feeling_keys: ['stressed', 'grateful'], version: created.version })
      .expect(200);
    expect(ok.body.feeling_keys).toEqual(['stressed', 'grateful']);
  });

  it('makes the first feeling the entry’s primary one', async () => {
    const created = await create('Tired but proud of the work.');
    const ok = await request(server())
      .patch(`/entries/${created.id}`)
      .send({ feeling_keys: ['proud', 'exhausted'], version: created.version })
      .expect(200);
    expect(ok.body.feeling_key).toBe('proud');
    expect(ok.body.feeling_keys[0]).toBe('proud');
  });

  it('still accepts the single-feeling form as a set of one', async () => {
    const created = await create('A flat, ordinary day.');
    const ok = await request(server())
      .patch(`/entries/${created.id}`)
      .send({ feeling_key: 'neutral', version: created.version })
      .expect(200);
    expect(ok.body.feeling_keys).toEqual(['neutral']);
    expect(ok.body.feeling_key).toBe('neutral');
  });

  it('de-duplicates a repeated feeling instead of failing', async () => {
    const created = await create('Anxious, really quite anxious.');
    const ok = await request(server())
      .patch(`/entries/${created.id}`)
      .send({ feeling_keys: ['anxious', 'anxious'], version: created.version })
      .expect(200);
    expect(ok.body.feeling_keys).toEqual(['anxious']);
  });

  it('records confirming the suggested set, and overriding it, differently', async () => {
    const created = await create('A calm afternoon.');
    expect(created.feeling_source).toBe('suggested');

    const confirmed = await request(server())
      .patch(`/entries/${created.id}`)
      .send({ feeling_keys: created.feeling_keys, version: created.version })
      .expect(200);
    expect(confirmed.body.feeling_source).toBe('confirmed');

    const overridden = await request(server())
      .patch(`/entries/${created.id}`)
      .send({ feeling_keys: ['angry'], version: confirmed.body.version })
      .expect(200);
    expect(overridden.body.feeling_source).toBe('overridden');
  });

  it('rejects more feelings than an entry may carry', async () => {
    const created = await create('Everything at once.');
    const res = await request(server())
      .patch(`/entries/${created.id}`)
      .send({
        feeling_keys: ['happy', 'sad', 'angry', 'calm', 'proud'],
        version: created.version,
      })
      .expect(422);
    expect(res.body.error.code).toBe('validation_error');
  });

  it('leaves the feelings alone when the edit does not mention them', async () => {
    const created = await create('First draft.');
    const withFeelings = await request(server())
      .patch(`/entries/${created.id}`)
      .send({ feeling_keys: ['hopeful', 'restless'], version: created.version })
      .expect(200);

    const textOnly = await request(server())
      .patch(`/entries/${created.id}`)
      .send({ raw_text: 'Second draft.', version: withFeelings.body.version })
      .expect(200);
    expect(textOnly.body.feeling_keys).toEqual(['hopeful', 'restless']);
  });
});
