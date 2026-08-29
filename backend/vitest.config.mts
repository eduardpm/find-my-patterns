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
  },
});
