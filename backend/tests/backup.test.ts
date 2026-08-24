import Database from 'better-sqlite3';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { backupDiary } from '../src/db/backup';
import { GOLDEN } from './helpers/app';

let directory: string;
let source: string;
let destination: string;

beforeEach(() => {
  directory = fs.mkdtempSync(path.join(os.tmpdir(), 'diary-backup-'));
  source = path.join(directory, 'live.db');
  destination = path.join(directory, 'backup.db');
  fs.copyFileSync(GOLDEN, source);
});

afterEach(() => fs.rmSync(directory, { recursive: true, force: true }));

describe('diary backup', () => {
  it('creates a valid owner-only SQLite snapshot', async () => {
    await backupDiary(source, destination);
    const db = new Database(destination, { readonly: true });
    expect(db.pragma('integrity_check', { simple: true })).toBe('ok');
    expect(
      (db.prepare('SELECT COUNT(*) AS count FROM diary_entries').get() as { count: number }).count,
    ).toBeGreaterThan(0);
    db.close();
    if (process.platform !== 'win32') expect(fs.statSync(destination).mode & 0o777).toBe(0o600);
  });

  it('refuses to overwrite an existing backup', async () => {
    fs.writeFileSync(destination, 'keep me');
    await expect(backupDiary(source, destination)).rejects.toThrow(/Refusing to overwrite/);
    expect(fs.readFileSync(destination, 'utf8')).toBe('keep me');
  });
});
