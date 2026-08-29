/**
 * Creating a new diary.
 *
 * The server deliberately never creates one — a server that invents a missing file makes "wrong
 * path" and "your diary is gone" look identical. So creation is its own explicit command, and the
 * rules that make it safe are worth pinning: it refuses to touch anything that already exists, and
 * it leaves nothing behind if it fails part-way.
 */

import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { assertCompatible } from '../src/db/compatibility';
import { openDiary } from '../src/db/database';
import { FEELING_GROUP_SEED, FEELING_SEED } from '../src/db/feeling-vocabulary';
import { initDiary } from '../src/db/init';
import { GUIDING_QUESTIONS } from '../src/db/seed';

let dir: string;

beforeEach(() => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'diary-init-'));
});
afterEach(() => {
  fs.rmSync(dir, { recursive: true, force: true });
});

describe('initDiary', () => {
  it('creates a diary the server can actually open', () => {
    const target = path.join(dir, 'diary.db');
    initDiary(target);

    const db = openDiary(target);
    expect(() => assertCompatible(db)).not.toThrow();
    db.close();
  });

  it('creates the schema the current code expects, including `version`', () => {
    const target = path.join(dir, 'diary.db');
    initDiary(target);

    const db = openDiary(target);
    const columns = (
      db.readonlyPragma("SELECT name FROM pragma_table_info('diary_entries')") as {
        name: string;
      }[]
    ).map((r) => r.name);
    db.close();

    expect(columns).toContain('version');
  });

  it('seeds the reference data so the clients have feelings and questions', () => {
    const target = path.join(dir, 'diary.db');
    initDiary(target);

    const db = openDiary(target);
    const feelings = db.prepare<{ n: number }>('SELECT COUNT(*) AS n FROM feelings').get() as {
      n: number;
    };
    const questions = db
      .prepare<{ n: number }>('SELECT COUNT(*) AS n FROM guiding_questions')
      .get() as { n: number };
    const groups = db.prepare<{ n: number }>('SELECT COUNT(*) AS n FROM feeling_groups').get() as {
      n: number;
    };
    db.close();

    expect(feelings.n).toBe(FEELING_SEED.length);
    expect(groups.n).toBe(FEELING_GROUP_SEED.length);
    expect(questions.n).toBe(GUIDING_QUESTIONS.length);
  });

  it('starts empty — no entries invented', () => {
    const target = path.join(dir, 'diary.db');
    initDiary(target);

    const db = openDiary(target);
    const entries = db.prepare<{ n: number }>('SELECT COUNT(*) AS n FROM diary_entries').get() as {
      n: number;
    };
    db.close();

    expect(entries.n).toBe(0);
  });

  it('refuses to touch a diary that already exists', () => {
    const target = path.join(dir, 'diary.db');
    initDiary(target);
    const before = fs.readFileSync(target);

    expect(() => initDiary(target)).toThrow(/already exists/);
    expect(fs.readFileSync(target).equals(before)).toBe(true);
  });

  it('creates missing parent directories', () => {
    const target = path.join(dir, 'nested', 'deeper', 'diary.db');
    initDiary(target);
    expect(fs.existsSync(target)).toBe(true);
  });

  it('does not leave a half-built diary behind if creation fails', () => {
    // A directory where the file should go makes better-sqlite3 fail on open.
    const target = path.join(dir, 'diary.db');
    fs.mkdirSync(target);
    expect(() => initDiary(target)).toThrow();
    // The directory is still a directory — nothing was replaced with a broken file.
    expect(fs.statSync(target).isDirectory()).toBe(true);
  });
});
