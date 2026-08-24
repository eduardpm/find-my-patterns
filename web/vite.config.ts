import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

/**
 * The built app is served by the FastAPI backend under `/app` (research.md §2), so every asset URL
 * must be prefixed. The prefix is load-bearing rather than cosmetic: the SPA's own routes would
 * otherwise collide with live API paths (`/entries`, `/insights`), and re-prefixing the API to
 * `/api` would break the already-shipped Android app (FR-018).
 */
const API_PATHS = [
  '/entries',
  '/feelings',
  '/guiding-questions',
  '/insights',
  '/monthly-summary',
  '/auth',
  '/login',
];

export default defineConfig({
  base: '/app/',
  plugins: [react()],
  build: {
    outDir: 'dist',
    emptyOutDir: true,
  },
  server: {
    // In dev the Vite server owns `/`, so API calls are proxied to the real backend.
    proxy: Object.fromEntries(
      API_PATHS.map((path) => [path, { target: 'http://localhost:8000', changeOrigin: false }]),
    ),
  },
});
