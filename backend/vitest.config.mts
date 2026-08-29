import swc from 'unplugin-swc';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  plugins: [swc.vite({ module: { type: 'es6' } })],
  test: {
    globals: true,
    environment: 'node',
    include: ['tests/**/*.test.ts'],
    pool: 'threads',
    poolOptions: { threads: { singleThread: true } },
    // Builds tests/fixtures/golden.db once before any test file runs (#83) — it is no longer
    // committed, so a clean checkout needs it built before `bootOnCopy` and friends can copy it.
    globalSetup: ['tests/global-setup.ts'],
    // The e2e suite (tests/e2e/**) boots a real Nest app per test via startOnLoopback and drives
    // it over HTTP — genuine end-to-end cost, not the unit-test workload Vitest's 5000ms default
    // testTimeout assumes. Measured locally (idle machine, 579 tests): every test in
    // roadmap-engine.test.ts and experiments.test.ts — the two files #105 named — finishes in
    // under 135ms; the slowest test anywhere in the suite is 818ms. Under the CI contention #105
    // documents (two full duplicate workflow runs racing on the same commit), individual tests in
    // those two files that normally take ~50-90ms took over 5000ms and were killed mid-run; the
    // whole roadmap-engine.test.ts file — normally ~1-2s — took 40396ms in that run. That
    // contention is the real bug and #105 removes its source (the duplicate run); this timeout is
    // a defensive ceiling sized well above the worst legitimate boot-and-drive cost that remains
    // (a cold Nest boot on a loaded shared runner), not a substitute for that fix. hookTimeout is
    // raised alongside testTimeout since beforeEach does the app boot and could hit its own
    // (higher, 10000ms-default) ceiling under the same contention before the test body's timeout
    // ever fires.
    testTimeout: 20000,
    hookTimeout: 20000,
  },
});
