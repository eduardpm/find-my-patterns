/**
 * T026 — FR-022 / SC-011: merely starting the backend and reading the diary must not modify it.
 *
 * **`/insights` is deliberately excluded.** It recomputes patterns on read and rewrites
 * `pattern_entries` on every call, so it genuinely writes. SC-011 was corrected to cover read-only
 * endpoints for exactly this reason — see the SC-011 note in spec.md.
 *
 * What this test does guarantee is the part FR-022 is really about: connecting, verifying
 * compatibility, seeding, and serving every genuinely read-only endpoint touches nothing.
 */

import * as crypto from 'node:crypto';
import * as fs from 'node:fs';
import request from 'supertest';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { bootOnCopy, teardown, type Harness } from '../helpers/app';

const hash = (p: string): string =>
  crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

let h: Harness;

beforeEach(async () => {
  h = await bootOnCopy();
});
afterEach(async () => {
  await teardown(h);
});

describe('reading the diary', () => {
  it('leaves the file byte-identical after startup alone', async () => {
    // Startup already happened in beforeEach: open + compatibility check + seed.
    const before = hash(h.dbPath);
    await h.app.close();
    expect(hash(h.dbPath)).toBe(before);
  });

  it('leaves the file byte-identical after exercising every read-only endpoint', async () => {
    const before = hash(h.dbPath);
    const server = h.app.getHttpServer();
    const month = '2026-07';

    const summary = await request(server).get(`/monthly-summary?month=${month}`);
    const populated = summary.body.days.find((d: { feelings: string[] }) => d.feelings.length > 0);

    await request(server).get('/feelings').expect(200);
    await request(server).get('/guiding-questions').expect(200);
    await request(server).get(`/entries?date=${populated.date}`).expect(200);
    await request(server).get(`/monthly-summary?month=${month}`).expect(200);

    const listed = await request(server).get(`/entries?date=${populated.date}`);
    for (const entry of listed.body.entries) {
      await request(server).get(`/entries/${entry.id}`).expect(200);
    }

    expect(hash(h.dbPath)).toBe(before);
  });

  it('leaves the file byte-identical even after repeated reads', async () => {
    const before = hash(h.dbPath);
    const server = h.app.getHttpServer();
    for (let i = 0; i < 5; i += 1) {
      await request(server).get('/feelings');
      await request(server).get('/guiding-questions');
      await request(server).get('/monthly-summary?month=2026-07');
    }
    expect(hash(h.dbPath)).toBe(before);
  });

  it('does not create side files — no -wal, no -shm, no journal left behind', async () => {
    const server = h.app.getHttpServer();
    await request(server).get('/feelings');
    await h.app.close();

    const strays = fs.readdirSync(h.dir).filter((f) => f !== 'diary.db');
    expect(strays).toEqual([]);
  });
});
