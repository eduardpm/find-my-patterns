/**
 * T048 / T049 — static hosting and cache headers.
 *
 * All three behaviours here were bugs in feature 003 before they were tests: the prefix collision,
 * the SPA fallback (which failed because `StaticFiles` *raises* rather than returning a 404), and
 * the unconditional mount that took the API down when the web client hadn't been built.
 */

import type { INestApplication } from '@nestjs/common';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import request from 'supertest';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { createApp } from '../../src/main';
import { GOLDEN, startOnLoopback } from '../helpers/app';

let dir: string;
let dbPath: string;
let distPath: string;
let app: INestApplication | null = null;

beforeEach(() => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'diary-static-'));
  dbPath = path.join(dir, 'diary.db');
  fs.copyFileSync(GOLDEN, dbPath);

  distPath = path.join(dir, 'dist');
  fs.mkdirSync(path.join(distPath, 'assets'), { recursive: true });
  fs.writeFileSync(path.join(distPath, 'index.html'), '<!doctype html><title>diary</title>');
  fs.writeFileSync(path.join(distPath, 'assets', 'app.js'), 'console.log("app")');
});

afterEach(async () => {
  await app?.close();
  app = null;
  fs.rmSync(dir, { recursive: true, force: true });
});

describe('with the web client built', () => {
  beforeEach(async () => {
    app = await createApp({ databasePath: dbPath, webDistPath: distPath });
    await startOnLoopback(app);
  });

  it('serves the app at /app', async () => {
    const res = await request(app!.getHttpServer()).get('/app/').expect(200);
    expect(res.text).toContain('<!doctype html>');
  });

  it('serves real asset files', async () => {
    const res = await request(app!.getHttpServer()).get('/app/assets/app.js').expect(200);
    expect(res.text).toContain('console.log');
  });

  it('falls back to index.html for a client route, not a JSON 404', async () => {
    const res = await request(app!.getHttpServer()).get('/app/calendar').expect(200);
    expect(res.text).toContain('<!doctype html>');
  });

  it('falls back for a deep client route with an id in it', async () => {
    const res = await request(app!.getHttpServer()).get('/app/entry/abc-123').expect(200);
    expect(res.text).toContain('<!doctype html>');
  });

  it('does not shadow the API — /insights still returns JSON', async () => {
    const res = await request(app!.getHttpServer()).get('/insights').expect(200);
    expect(res.body).toHaveProperty('patterns');
  });

  it('does not shadow /entries', async () => {
    const res = await request(app!.getHttpServer()).get('/entries').expect(422);
    expect(res.body.error.code).toBe('validation_error');
  });

  it('leaves an unknown API path as a JSON 404', async () => {
    const res = await request(app!.getHttpServer()).get('/nope').expect(404);
    expect(res.body.error).toBeDefined();
  });
});

describe('with the web client NOT built', () => {
  beforeEach(async () => {
    app = await createApp({ databasePath: dbPath, webDistPath: path.join(dir, 'missing') });
    await startOnLoopback(app);
  });

  it('still starts and serves the API', async () => {
    // A backend that refuses to start over a missing browser bundle would break the Android app
    // for a reason that has nothing to do with the phone (FR-016).
    await request(app!.getHttpServer()).get('/feelings').expect(200);
  });
});

describe('cache headers (FR-025)', () => {
  beforeEach(async () => {
    app = await createApp({ databasePath: dbPath, webDistPath: distPath });
    await startOnLoopback(app);
  });

  it('sets baseline browser security headers', async () => {
    const res = await request(app!.getHttpServer()).get('/app/').expect(200);
    expect(res.headers['content-security-policy']).toContain("default-src 'self'");
    expect(res.headers['x-content-type-options']).toBe('nosniff');
    expect(res.headers['referrer-policy']).toBe('no-referrer');
    expect(res.headers['x-frame-options']).toBe('DENY');
  });

  it('sets no-store on every diary-bearing endpoint', async () => {
    const month = new Date().toISOString().slice(0, 7);
    for (const url of [
      '/entries?date=2026-07-28',
      '/insights',
      `/monthly-summary?month=${month}`,
      '/guiding-questions',
    ]) {
      const res = await request(app!.getHttpServer()).get(url);
      expect(res.headers['cache-control']).toBe('no-store');
    }
  });

  it('does not set no-store on static assets, which carry no diary content', async () => {
    const res = await request(app!.getHttpServer()).get('/app/assets/app.js');
    expect(res.headers['cache-control']).not.toBe('no-store');
  });
});
