import request from 'supertest';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { bootOnCopy, teardown, type Harness } from '../helpers/app';

let h: Harness;
const server = () => h.app.getHttpServer();

beforeEach(async () => {
  h = await bootOnCopy();
});
afterEach(async () => {
  await teardown(h);
});

describe('guided entry drafts', () => {
  it('creates a backend-owned key and persists each answer independently', async () => {
    const created = await request(server()).post('/guided-entry-drafts').send({}).expect(201);
    const key = created.body.draft_key;
    expect(key).toMatch(/^[0-9a-f-]{36}$/);

    await request(server())
      .put(`/guided-entry-drafts/${key}/questions/general_feeling`)
      .send({ answer_text: 'First version', order_index: 0 })
      .expect(204);
    await request(server())
      .put(`/guided-entry-drafts/${key}/questions/general_feeling`)
      .send({ answer_text: 'Corrected version', order_index: 0 })
      .expect(204);

    const draft = await request(server()).get(`/guided-entry-drafts/${key}`).expect(200);
    expect(draft.body.answers).toEqual([
      { question_key: 'general_feeling', answer_text: 'Corrected version' },
    ]);
  });

  it('returns the same unfinished draft key after a refresh-style second start', async () => {
    const first = await request(server()).post('/guided-entry-drafts').send({}).expect(201);
    const second = await request(server()).post('/guided-entry-drafts').send({}).expect(201);
    expect(second.body.draft_key).toBe(first.body.draft_key);
  });

  it('finalizes the same entry only after its answers have been assembled', async () => {
    const created = await request(server()).post('/guided-entry-drafts').send({}).expect(201);
    const key = created.body.draft_key;
    await request(server())
      .put(`/guided-entry-drafts/${key}/questions/general_feeling`)
      .send({ answer_text: 'A persisted answer', order_index: 0 })
      .expect(204);

    const finalized = await request(server())
      .post(`/guided-entry-drafts/${key}/finalize`)
      .send({})
      .expect(201);
    expect(finalized.body.id).toBe(key);
    expect(finalized.body.raw_text).toContain('A persisted answer');
    await request(server()).get(`/guided-entry-drafts/${key}`).expect(404);
  });

  it('can discard an unfinished draft without creating a visible entry', async () => {
    const created = await request(server()).post('/guided-entry-drafts').send({}).expect(201);
    const key = created.body.draft_key;
    await request(server()).delete(`/guided-entry-drafts/${key}`).expect(204);
    await request(server()).get(`/guided-entry-drafts/${key}`).expect(404);
    await request(server()).get(`/entries/${key}`).expect(404);
  });
});
