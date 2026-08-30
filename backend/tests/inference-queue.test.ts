import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { encodeDate, encodeDateTime, nowUtc, todayLocal } from '../src/db/codecs';
import { initDiary } from '../src/db/init';
import { openDiary, type DiaryDatabase } from '../src/db/database';
import { createScopedDb } from '../src/db/scoped-db';
import { QueuedEntryInference } from '../src/inference/inference';
import { DEFAULT_USER_ID } from '../src/auth/default-user';

let dir: string;
let db: DiaryDatabase;

beforeEach(() => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'diary-inference-'));
  const target = path.join(dir, 'diary.db');
  initDiary(target);
  db = openDiary(target);
  const now = encodeDateTime(nowUtc());
  db.prepare(
    `INSERT INTO diary_entries
     (id, created_at, updated_at, entry_date, mode, raw_text, feeling_key, feeling_source, version)
     VALUES ('entry-1', ?, ?, ?, 'freeform', 'A local test entry', NULL, 'unset', 1)`,
  ).run(now, now, encodeDate(todayLocal()));
});

afterEach(() => {
  db.close();
  fs.rmSync(dir, { recursive: true, force: true });
});

describe('QueuedEntryInference', () => {
  it('durably queues analysis and returns immediately without polling for a result', () => {
    const started = performance.now();
    const result = new QueuedEntryInference(createScopedDb(db)).enqueueEntry(
      DEFAULT_USER_ID,
      'entry-1',
    );
    const elapsed = performance.now() - started;

    expect(result).toBeNull();
    expect(elapsed).toBeLessThan(100);
    expect(
      db
        .prepare(
          `SELECT kind, entry_id, status, attempts, started_at, completed_at
           FROM inference_jobs`,
        )
        .get(),
    ).toEqual({
      kind: 'entry_analysis',
      entry_id: 'entry-1',
      status: 'queued',
      attempts: 0,
      started_at: null,
      completed_at: null,
    });
  });
});
