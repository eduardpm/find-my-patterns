import request from 'supertest';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { openDiary } from '../src/db/database';
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

  // #88: `recomputePatterns` resets a pattern's suggestion to the template whenever its narrative
  // changes (a count that moved). It must reset the narration attempt state (`narration_attempts`,
  // `narration_next_attempt_at`) in the same place — otherwise a pattern that exhausted its retries
  // under an old count stays permanently un-narratable even after the count that made it eligible
  // again changes, which is the acceptance criterion this test pins down.
  it('resets narration attempt state when a changed count makes the pattern eligible again', async () => {
    const entries: Array<{ id: string; version: number }> = [];
    for (let index = 0; index < 3; index += 1) {
      const created = (
        await request(server())
          .post('/entries')
          .send({ mode: 'freeform', raw_text: `Coffee break number ${index + 1}.` })
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
    const coffeePattern = before.patterns.find(
      (pattern: { topic: string }) => pattern.topic === 'coffee',
    );
    expect(coffeePattern).toBeDefined();

    // Simulate a pattern that has already exhausted its narration retries under this count — the
    // state the worker would leave behind after `MAX_NARRATION_ATTEMPTS` rejected attempts.
    const db = openDiary(h.dbPath);
    db.prepare(
      `UPDATE patterns SET narration_attempts = 5,
       narration_next_attempt_at = '2099-01-01 00:00:00.000000' WHERE id = ?`,
    ).run(coffeePattern.id);
    const beforeReset = db
      .prepare('SELECT narration_attempts, narration_next_attempt_at FROM patterns WHERE id = ?')
      .get(coffeePattern.id) as { narration_attempts: number; narration_next_attempt_at: string };
    expect(beforeReset.narration_attempts).toBe(5);
    db.close();

    // A fourth confirmed entry moves the occurrence count, which is what makes
    // `recomputePatterns` treat the pattern's narrative — and, with this fix, its attempt state —
    // as stale.
    const created = (
      await request(server())
        .post('/entries')
        .send({ mode: 'freeform', raw_text: 'Coffee break number 4.' })
        .expect(201)
    ).body;
    await request(server())
      .patch(`/entries/${created.id}`)
      .send({ feeling_key: created.suggested_feeling.key, version: created.version })
      .expect(200);

    const after = (await request(server()).get('/insights').expect(200)).body;
    const coffeeAfter = after.patterns.find(
      (pattern: { topic: string }) => pattern.topic === 'coffee',
    );
    expect(coffeeAfter).toBeDefined();
    expect(coffeeAfter.id).toBe(coffeePattern.id);

    const readBack = openDiary(h.dbPath);
    const reset = readBack
      .prepare('SELECT narration_attempts, narration_next_attempt_at FROM patterns WHERE id = ?')
      .get(coffeePattern.id) as {
      narration_attempts: number;
      narration_next_attempt_at: string | null;
    };
    readBack.close();
    expect(reset.narration_attempts).toBe(0);
    expect(reset.narration_next_attempt_at).toBeNull();
  });
});
