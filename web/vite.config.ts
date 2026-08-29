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
  // Guided drafts and transcriptions are separate top-level paths, not children of `/entries`, so
  // they need their own entries here. Without them `npm run dev` served index.html in place of the
  // API and the guided composer — the default way an entry is written — failed on load.
  '/guided-entry-drafts',
  '/guiding-questions',
  '/insights',
  '/monthly-summary',
  // The topic list and its alias editor (A4-04) are a top-level path for the same reason the
  // others are: the API keeps its shape so the shipped Android client keeps working (FR-018).
  '/topics',
  '/transcriptions',
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
