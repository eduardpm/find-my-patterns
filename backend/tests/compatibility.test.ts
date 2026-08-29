/**
 * T074 — FR-018. Refuse to serve a diary that cannot be fully interpreted, rather than starting up
 * and presenting an incomplete one.
 */

import Database from 'better-sqlite3';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { assertCompatible, IncompatibleDiaryError } from '../src/db/compatibility';
import { openDiary } from '../src/db/database';

const GOLDEN = path.resolve(__dirname, 'fixtures/golden.db');
let dir: string;
let workingCopy: string;

beforeEach(() => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'diary-'));
  workingCopy = path.join(dir, 'diary.db');
  fs.copyFileSync(GOLDEN, workingCopy);
});

afterEach(() => {
  fs.rmSync(dir, { recursive: true, force: true });
});

describe('startup compatibility check', () => {
  it('accepts a real diary', () => {
    const db = openDiary(workingCopy);
    expect(() => assertCompatible(db)).not.toThrow();
    db.close();
  });

  it('refuses a diary with a missing table', () => {
    // Written with the raw driver on purpose: the guarded connection would rightly refuse to do this.
    const raw = new Database(workingCopy);
    raw.exec('DROP TABLE pattern_entries');
    raw.close();

    const db = openDiary(workingCopy);
    expect(() => assertCompatible(db)).toThrow(IncompatibleDiaryError);
    db.close();
  });

  it('refuses a diary missing a column this backend depends on', () => {
    const raw = new Database(workingCopy);
    raw.exec('ALTER TABLE diary_entries DROP COLUMN version');
    raw.close();

    const db = openDiary(workingCopy);
    expect(() => assertCompatible(db)).toThrow(/version/);
    db.close();
  });

  it('names every problem it found, not just the first', () => {
    const raw = new Database(workingCopy);
    raw.exec('DROP TABLE patterns');
    raw.exec('DROP TABLE topics');
    raw.close();

    const db = openDiary(workingCopy);
    try {
      assertCompatible(db);
      expect.unreachable('should have refused');
    } catch (err) {
      expect((err as IncompatibleDiaryError).problems.length).toBeGreaterThanOrEqual(2);
    }
    db.close();
  });

  it('says plainly that nothing was modified and the old backend still works', () => {
    const raw = new Database(workingCopy);
    raw.exec('DROP TABLE patterns');
    raw.close();

    const db = openDiary(workingCopy);
    expect(() => assertCompatible(db)).toThrow(/Nothing was modified/);
    db.close();
  });

  it('ignores alembic_version, left behind by an earlier migration tool', () => {
    const raw = new Database(workingCopy);
    raw.exec('DROP TABLE alembic_version');
    raw.close();

    const db = openDiary(workingCopy);
    expect(() => assertCompatible(db)).not.toThrow();
    db.close();
  });

  it('refuses malformed values before an endpoint discovers them', () => {
    const raw = new Database(workingCopy);
    raw
      .prepare(
        'UPDATE diary_entries SET created_at = ? WHERE id = (SELECT id FROM diary_entries LIMIT 1)',
      )
      .run('not-a-timestamp');
    raw.close();

    const db = openDiary(workingCopy);
    expect(() => assertCompatible(db)).toThrow(/unreadable row/);
    db.close();
  });

  describe('entry_topic_feelings (E-1a)', () => {
    it('refuses a pairing row naming a feeling key outside the vocabulary', () => {
      const raw = new Database(workingCopy);
      // Off for the same reason `db/database.ts` keeps it off on the guarded connection: a
      // deliberately invalid `feeling_key` is exactly what this test needs to write.
      raw.pragma('foreign_keys = OFF');
      const [entry, topic] = [
        raw.prepare('SELECT id FROM diary_entries LIMIT 1').get() as { id: string },
        raw.prepare('SELECT id FROM topics LIMIT 1').get() as { id: string },
      ];
      raw
        .prepare(
          `INSERT INTO entry_topic_feelings (entry_id, topic_id, feeling_key, source)
           VALUES (?, ?, 'not-a-real-feeling', 'suggested')`,
        )
        .run(entry.id, topic.id);
      raw.close();

      const db = openDiary(workingCopy);
      expect(() => assertCompatible(db)).toThrow(/unreadable row/);
      db.close();
    });

    it('refuses a pairing row whose source is outside suggested/confirmed/overridden', () => {
      const raw = new Database(workingCopy);
      const [entry, topic, feeling] = [
        raw.prepare('SELECT id FROM diary_entries LIMIT 1').get() as { id: string },
        raw.prepare('SELECT id FROM topics LIMIT 1').get() as { id: string },
        raw.prepare('SELECT "key" FROM feelings LIMIT 1').get() as { key: string },
      ];
      raw
        .prepare(
          `INSERT INTO entry_topic_feelings (entry_id, topic_id, feeling_key, source)
           VALUES (?, ?, ?, 'unset')`,
        )
        .run(entry.id, topic.id, feeling.key);
      raw.close();

      const db = openDiary(workingCopy);
      expect(() => assertCompatible(db)).toThrow(/unreadable row/);
      db.close();
    });

    it('accepts a well-formed pairing row', () => {
      const raw = new Database(workingCopy);
      const [entry, topic, feeling] = [
        raw.prepare('SELECT id FROM diary_entries LIMIT 1').get() as { id: string },
        raw.prepare('SELECT id FROM topics LIMIT 1').get() as { id: string },
        raw.prepare('SELECT "key" FROM feelings LIMIT 1').get() as { key: string },
      ];
      raw
        .prepare(
          `INSERT INTO entry_topic_feelings (entry_id, topic_id, feeling_key, source)
           VALUES (?, ?, ?, 'suggested')`,
        )
        .run(entry.id, topic.id, feeling.key);
      raw.close();

      const db = openDiary(workingCopy);
      expect(() => assertCompatible(db)).not.toThrow();
      db.close();
    });
  });
});
