import request from 'supertest';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { bootOnCopy, teardown, type Harness } from './helpers/app';

let h: Harness;
const server = () => h.app.getHttpServer();

beforeEach(async () => {
  h = await bootOnCopy();
});

afterEach(async () => {
  await teardown(h);
});

describe('pattern lifecycle after entry edits', () => {
  it('removes support for a topic that was edited out of an entry', async () => {
    const entries: Array<{ id: string; version: number }> = [];

    for (let index = 0; index < 3; index += 1) {
      const created = (
        await request(server())
          .post('/entries')
          .send({ mode: 'freeform', raw_text: `Tea break number ${index + 1}.` })
          .expect(201)
      ).body;
      const confirmed = (
        await request(server())
          .patch(`/entries/${created.id}`)
          .send({ feeling_key: created.suggested_feeling.key, version: created.version })
          .expect(200)
      ).body;
      entries.push(confirmed);
    }

    const before = (await request(server()).get('/insights').expect(200)).body;
    expect(before.patterns.some((pattern: { topic: string }) => pattern.topic === 'tea')).toBe(
      true,
    );

    await request(server())
      .patch(`/entries/${entries[0].id}`)
      .send({ raw_text: 'A quiet break with water.', version: entries[0].version })
      .expect(200);

    const after = (await request(server()).get('/insights').expect(200)).body;
    expect(after.patterns.some((pattern: { topic: string }) => pattern.topic === 'tea')).toBe(
      false,
    );
  });
});
