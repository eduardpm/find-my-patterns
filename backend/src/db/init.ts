import Database from 'better-sqlite3';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { loadConfig } from '../config';
import { openDiary } from './database';
import { SCHEMA_STATEMENTS } from './schema';
import { seed } from './seed';

/**
 * Creates a new, empty diary — `npm run init-db`.
 *
 * Separate from the server on purpose. The server opens a diary and never creates one, because a
 * server that silently creates a missing file turns "wrong path" and "your diary is gone" into the
 * same, invisible outcome. Creating one is a thing you do once, deliberately.
 *
 * Refuses to touch an existing file. Migrating or repairing a diary is not this command's job.
 */
export function initDiary(targetPath: string): void {
  if (fs.existsSync(targetPath)) {
    throw new Error(
      `A diary already exists at ${targetPath}. This command only creates new ones — ` +
        `it will not modify or overwrite an existing diary.`,
    );
  }

  fs.mkdirSync(path.dirname(targetPath), { recursive: true });

  const db = new Database(targetPath);
  try {
    db.exec('BEGIN');
    for (const statement of SCHEMA_STATEMENTS) db.exec(statement);
    db.exec('COMMIT');
  } catch (err) {
    db.exec('ROLLBACK');
    db.close();
    fs.rmSync(targetPath, { force: true }); // never leave a half-built diary behind
    throw err;
  }
  db.close();

  // Seed through the normal connection, so the reference rows are written exactly as the running
  // server would write them.
  const diary = openDiary(targetPath);
  seed(diary);
  diary.close();

  // Diary prose is sensitive even on a single-user machine. Do not rely on a permissive umask.
  fs.chmodSync(targetPath, 0o600);
}

if (require.main === module) {
  const target = process.argv[2] ?? loadConfig().databasePath;
  try {
    initDiary(target);
    console.log(`Created a new diary at ${target}`);
  } catch (err) {
    console.error(err instanceof Error ? err.message : String(err));
    process.exit(1);
  }
}
