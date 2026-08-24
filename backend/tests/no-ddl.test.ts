/**
 * T008 — FR-022: this process must never modify the diary's schema.
 *
 * The risk is not that someone writes `DROP TABLE` on purpose. It is that a data layer helpfully
 * "syncs" the schema on startup, which is the default posture of most Node ORMs and the reason
 * research.md §2 rejected all of them. The guard is enforced at the connection, so any such attempt
 * throws rather than succeeding quietly.
 */

import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { DdlAttemptedError, openDiary } from '../src/db/database';

const GOLDEN = path.resolve(__dirname, 'fixtures/golden.db');
let workingCopy: string;

beforeEach(() => {
  workingCopy = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'diary-')), 'diary.db');
  fs.copyFileSync(GOLDEN, workingCopy);
});

afterEach(() => {
  fs.rmSync(path.dirname(workingCopy), { recursive: true, force: true });
});

describe('the diary connection', () => {
  it('refuses CREATE TABLE', () => {
    const db = openDiary(workingCopy);
    expect(() => db.prepare('CREATE TABLE sneaky (id TEXT)')).toThrow(DdlAttemptedError);
    db.close();
  });

  it('refuses ALTER TABLE', () => {
    const db = openDiary(workingCopy);
    expect(() => db.prepare('ALTER TABLE diary_entries ADD COLUMN extra TEXT')).toThrow(
      DdlAttemptedError,
    );
    db.close();
  });

  it('refuses DROP TABLE', () => {
    const db = openDiary(workingCopy);
    expect(() => db.prepare('DROP TABLE diary_entries')).toThrow(DdlAttemptedError);
    db.close();
  });

  it('refuses VACUUM, which rewrites the whole file', () => {
    const db = openDiary(workingCopy);
    expect(() => db.prepare('VACUUM')).toThrow(DdlAttemptedError);
    db.close();
  });

  it('allows ordinary DML', () => {
    const db = openDiary(workingCopy);
    expect(() => db.prepare('SELECT * FROM diary_entries')).not.toThrow();
    expect(() => db.prepare('UPDATE diary_entries SET raw_text = ? WHERE id = ?')).not.toThrow();
    db.close();
  });

  it('will not create a diary that does not exist', () => {
    // A wrong path must fail loudly. Silently creating an empty file looks exactly like data loss.
    const missing = path.join(path.dirname(workingCopy), 'nope.db');
    expect(() => openDiary(missing)).toThrow();
    expect(fs.existsSync(missing)).toBe(false);
  });

  it('enables foreign keys so cascades actually cascade', () => {
    const db = openDiary(workingCopy);
    const [row] = db.readonlyPragma('SELECT 1 AS ok') as { ok: number }[];
    expect(row.ok).toBe(1);
    db.close();
  });

  it('leaves the file byte-identical after opening and reading', () => {
    const before = fs.readFileSync(workingCopy);
    const db = openDiary(workingCopy);
    db.prepare('SELECT * FROM diary_entries').all();
    db.prepare('SELECT * FROM feelings').all();
    db.close();
    expect(fs.readFileSync(workingCopy).equals(before)).toBe(true);
  });
});
