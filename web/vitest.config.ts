import react from '@vitejs/plugin-react';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./tests/setup.ts'],
    include: ['tests/**/*.test.{ts,tsx}'],
    css: {
      // Vitest stubs every `.css` import to an empty module by default, which also swallows the
      // `?raw` suffix contrast.test.ts (#152) relies on to read the literal token values out of
      // tokens.css/base.css. Scoped to `?raw` only, so ordinary component `.css` imports elsewhere
      // stay stubbed as before.
      include: [/\.css\?raw$/],
    },
  },
});
