/**
 * T009 — FR-022: seeding an already-populated diary must change nothing.
 *
 * This is the most likely way this feature could quietly damage a real diary: a seed routine that
 * upserts rather than checks, silently rewriting the user's reference data on every start.
 */

import * as crypto from 'node:crypto';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { openDiary } from '../src/db/database';
import { FEELING_SEED } from '../src/db/feeling-vocabulary';
import { GUIDING_QUESTIONS, seed } from '../src/db/seed';

const GOLDEN = path.resolve(__dirname, 'fixtures/golden.db');
const hash = (p: string): string =>
  crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

let workingCopy: string;

beforeEach(() => {
  workingCopy = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'diary-')), 'diary.db');
  fs.copyFileSync(GOLDEN, workingCopy);
});

afterEach(() => {
  fs.rmSync(path.dirname(workingCopy), { recursive: true, force: true });
});

describe('seeding a populated diary', () => {
  it('leaves the file byte-identical', () => {
    const before = hash(workingCopy);
    const db = openDiary(workingCopy);
    seed(db);
    db.close();
    expect(hash(workingCopy)).toBe(before);
  });

  it('is still a no-op when run repeatedly', () => {
    const db = openDiary(workingCopy);
    seed(db);
    db.close();
    const after = hash(workingCopy);

    const db2 = openDiary(workingCopy);
    seed(db2);
    seed(db2);
    db2.close();
    expect(hash(workingCopy)).toBe(after);
  });

  it('does not duplicate the reference rows', () => {
    const db = openDiary(workingCopy);
    seed(db);
    const feelings = db.prepare<{ n: number }>('SELECT COUNT(*) AS n FROM feelings').get() as {
      n: number;
    };
    const questions = db
      .prepare<{ n: number }>('SELECT COUNT(*) AS n FROM guiding_questions')
      .get() as { n: number };
    db.close();
    expect(feelings.n).toBe(FEELING_SEED.length);
    expect(questions.n).toBe(GUIDING_QUESTIONS.length);
  });
});
