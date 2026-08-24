import Database from 'better-sqlite3';
import type { Database as Db, Statement } from 'better-sqlite3';
import * as fs from 'node:fs';

/**
 * The diary connection.
 *
 * Two rules govern this file, both from FR-022:
 *
 *  1. **It never issues DDL.** No CREATE, no ALTER, no DROP, no schema sync. The schema is adopted
 *     exactly as it stands and is owned by nothing in this process. `guard()` enforces it at
 *     runtime rather than trusting discipline.
 *  2. **It never creates the file.** Opening with `fileMustExist` means a wrong path fails loudly
 *     instead of silently producing an empty diary that looks like data loss.
 *
 * Existing diaries carry an `alembic_version` table left by an earlier migration tool. It is
 * inert here: never read, never written, never reasoned about.
 */

const FORBIDDEN_SQL = /\b(CREATE|ALTER|DROP|TRUNCATE|REINDEX|VACUUM)\b/i;

export class DdlAttemptedError extends Error {
  constructor(sql: string) {
    super(
      `Refused to execute schema-modifying SQL against the diary (FR-022). ` +
        `The schema is adopted as-is and must never be altered by this process. SQL: ${sql}`,
    );
  }
}

export interface DiaryDatabase {
  prepare<T = unknown>(sql: string): Statement<unknown[], T>;
  transaction<T>(fn: () => T): T;
  close(): void;
  /** Escape hatch for the compatibility check, which needs to read sqlite_master. */
  readonlyPragma(sql: string): unknown[];
}

export function openDiary(path: string): DiaryDatabase {
  if (process.platform !== 'win32') {
    const permissions = fs.statSync(path).mode & 0o777;
    if ((permissions & 0o077) !== 0) fs.chmodSync(path, 0o600);
  }
  const db: Db = new Database(path, { fileMustExist: true });

  // Explicitly OFF. better-sqlite3 turns foreign keys ON by default, and enabling them would
  // reject rows existing diaries already contain — a guided answer whose `question_key` is not in
  // the question library, for instance. Enforcement here would turn reading a real diary into an
  // error.
  db.pragma('foreign_keys = OFF');

  // The consequence is that cascades are not automatic: `EntriesService.delete` removes an entry's
  // children explicitly.

  const guard = (sql: string): void => {
    if (FORBIDDEN_SQL.test(sql)) throw new DdlAttemptedError(sql);
  };

  return {
    prepare<T = unknown>(sql: string): Statement<unknown[], T> {
      guard(sql);
      return db.prepare(sql) as Statement<unknown[], T>;
    },
    transaction<T>(fn: () => T): T {
      return db.transaction(fn)();
    },
    close(): void {
      db.close();
    },
    readonlyPragma(sql: string): unknown[] {
      if (!/^\s*SELECT\b/i.test(sql)) {
        throw new Error(`readonlyPragma accepts SELECT only, got: ${sql}`);
      }
      return db.prepare(sql).all();
    },
  };
}
