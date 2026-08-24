import Database from 'better-sqlite3';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { loadConfig } from '../config';

/** Create a transactionally consistent SQLite snapshot, including while the backend is running. */
export async function backupDiary(sourcePath: string, destinationPath: string): Promise<void> {
  const source = path.resolve(sourcePath);
  const destination = path.resolve(destinationPath);
  if (source === destination)
    throw new Error('Backup destination must differ from the live diary.');
  if (!fs.existsSync(source)) throw new Error(`Diary does not exist at ${source}`);
  if (fs.existsSync(destination)) throw new Error(`Refusing to overwrite ${destination}`);

  fs.mkdirSync(path.dirname(destination), { recursive: true, mode: 0o700 });
  const db = new Database(source, { readonly: true, fileMustExist: true });
  try {
    await db.backup(destination);
  } catch (error) {
    fs.rmSync(destination, { force: true });
    throw error;
  } finally {
    db.close();
  }
  if (process.platform !== 'win32') fs.chmodSync(destination, 0o600);
}

if (require.main === module) {
  const destination = process.argv[2];
  if (!destination) {
    console.error('Usage: npm run backup -- /secure/path/diary-YYYY-MM-DD.db');
    process.exit(1);
  }
  backupDiary(loadConfig().databasePath, destination)
    .then(() => console.log(`Created a consistent diary backup at ${path.resolve(destination)}`))
    .catch((error: unknown) => {
      console.error(error instanceof Error ? error.message : String(error));
      process.exit(1);
    });
}
