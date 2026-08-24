import type { INestApplication } from '@nestjs/common';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { createApp } from '../../src/main';

export const GOLDEN = path.resolve(__dirname, '../fixtures/golden.db');

export interface Harness {
  app: INestApplication;
  dbPath: string;
  dir: string;
}

/** Boots the app against a throwaway copy of the golden diary. */
export async function bootOnCopy(): Promise<Harness> {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'diary-test-'));
  const dbPath = path.join(dir, 'diary.db');
  fs.copyFileSync(GOLDEN, dbPath);
  const app = await createApp(dbPath);
  await app.init();
  return { app, dbPath, dir };
}

export async function teardown(h: Harness): Promise<void> {
  await h.app.close();
  fs.rmSync(h.dir, { recursive: true, force: true });
}
