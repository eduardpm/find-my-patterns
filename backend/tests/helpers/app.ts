import type { INestApplication } from '@nestjs/common';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { createApp } from '../../src/main';
import { initDiary } from '../../src/db/init';

export const GOLDEN = path.resolve(__dirname, '../fixtures/golden.db');

export interface Harness {
  app: INestApplication;
  dbPath: string;
  dir: string;
}

/**
 * Puts an app on a real loopback port and leaves it there for the whole test. Both boots below go
 * through this; a test that builds its own app with other options should too.
 *
 * Supertest only binds a port itself when the server it is handed is not already listening — and
 * when it does, it binds and closes one ephemeral port *per request*. Hundreds of those cycles a
 * second race: a `listen(0)` that starts before the previous `close()` has finished at the OS level
 * can be handed a port whose old socket is still going away, and the request then lands on the
 * dying socket instead of the live one. That is where the suite's `404`s, `501`s, `socket hang up`s
 * and `Parse Error: Expected HTTP/` came from — always connection-level, never about the response,
 * and never reproducible on a single file. Listening once here means supertest reuses the address
 * and never binds or closes anything, so the race has no window to open in.
 */
export async function startOnLoopback(app: INestApplication): Promise<void> {
  await app.listen(0, '127.0.0.1');
}

/**
 * Boots the app against a throwaway copy of the golden diary.
 *
 * `singleUserMode` defaults to unset, which `createApp` (`../../src/main.ts`) resolves to
 * `AppConfig.singleUserMode`'s own default (`true`) — every existing test that calls this with no
 * argument keeps running exactly as it did before M-1a (#45): no bearer token required, every
 * request resolves to the fixed default user. Pass `{ singleUserMode: false }` to boot the real
 * multi-tenant gate instead (`tests/contract/identity.test.ts`).
 */
export async function bootOnCopy(options: { singleUserMode?: boolean } = {}): Promise<Harness> {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'diary-test-'));
  const dbPath = path.join(dir, 'diary.db');
  fs.copyFileSync(GOLDEN, dbPath);
  const app = await createApp({ databasePath: dbPath, singleUserMode: options.singleUserMode });
  await startOnLoopback(app);
  return { app, dbPath, dir };
}

/**
 * Boots the app against a brand-new, empty diary.
 *
 * The golden fixture already carries entries, topics and two materialised patterns, which is what
 * makes it useful for read tests and useless for a test that wants to say "these entries produce
 * *exactly* these insights and nothing else". Starting empty is what lets those assertions be
 * closed rather than "contains at least".
 */
export async function bootOnFresh(options: { singleUserMode?: boolean } = {}): Promise<Harness> {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'diary-fresh-'));
  const dbPath = path.join(dir, 'diary.db');
  initDiary(dbPath);
  const app = await createApp({ databasePath: dbPath, singleUserMode: options.singleUserMode });
  await startOnLoopback(app);
  return { app, dbPath, dir };
}

export async function teardown(h: Harness): Promise<void> {
  await h.app.close();
  fs.rmSync(h.dir, { recursive: true, force: true });
}
