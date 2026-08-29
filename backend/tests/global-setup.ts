import * as path from 'node:path';
import { buildGoldenDb } from '../src/db/build-golden-db';

/**
 * Vitest global setup (#83) — runs once, before any test file, in the main process rather than a
 * worker.
 *
 * `golden.db` used to be a checked-in binary. It no longer is (see `build-golden-db.ts`'s doc
 * comment for why), which means a clean checkout has no fixture at all until something builds one.
 * Building it here, in TypeScript, run directly through Vitest's own transform, is what lets
 * `cd backend && npm test` keep working on a fresh checkout with no separate build step — a
 * `pretest` npm script calling the compiled `dist/db/build-golden-db.js` would work in CI, where
 * `npm run build` already ran, but would break the everyday `npm test` a developer runs against
 * source. `npm run build-golden-db` (the compiled entrypoint) exists for CI's `browser` job and for
 * regenerating the fixture by hand — both call the same `buildGoldenDb` this does.
 *
 * Once, not once per test file: Vitest runs `globalSetup` exactly once per `vitest run`/`vitest`
 * invocation, before the worker pool starts, regardless of how many test files or threads follow.
 */
export default function setup(): void {
  buildGoldenDb(path.resolve(__dirname, 'fixtures/golden.db'));
}
