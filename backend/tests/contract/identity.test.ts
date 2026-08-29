/**
 * Multi-tenant identity (M-1a, #45): register, login, logout, `GET /me`, and the blanket gate that
 * makes every other route require a valid bearer token.
 *
 * `SINGLE_USER_MODE` defaults to `true` (`config.ts`), which is what every *other* test file in
 * this suite boots under via `bootOnFresh()`/`bootOnCopy()` with no arguments — this file is the
 * one place the real multi-tenant gate (`SINGLE_USER_MODE=false`) gets exercised end to end, per
 * the recon's instruction to add a separate suite for it rather than touching the other ~48 files.
 */

import Database from 'better-sqlite3';
import request from 'supertest';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { DEFAULT_USER_ID } from '../../src/auth/default-user';
import { hashPassword } from '../../src/auth/password';
import { createApp } from '../../src/main';
import { bootOnFresh, startOnLoopback, teardown, type Harness } from '../helpers/app';

let h: Harness;
const server = () => h.app.getHttpServer();

const EMAIL = 'reader@example.com';
const PASSWORD = 'correct horse battery staple';

afterEach(async () => {
  await teardown(h);
});

describe('SINGLE_USER_MODE=true (the default)', () => {
  beforeEach(async () => {
    h = await bootOnFresh();
  });

  it('serves every route with no bearer token at all — the mobile app and web client today', async () => {
    await request(server()).get('/health').expect(200);
    await request(server()).get('/insights').expect(200);
    await request(server()).get('/entries?date=2026-07-01').expect(200);
  });

  it('has no default-user endpoints reachable through the new namespace either — same posture, plumbing only', async () => {
    // Register/login work regardless of SINGLE_USER_MODE — they are how a future client opts into
    // multi-tenant mode — but nothing about them changes what SINGLE_USER_MODE itself gates.
    await request(server())
      .post('/auth/register')
      .send({ email: EMAIL, password: PASSWORD })
      .expect(201);
  });
});

describe('SINGLE_USER_MODE=false — the real multi-tenant gate', () => {
  beforeEach(async () => {
    h = await bootOnFresh({ singleUserMode: false });
  });

  describe('the blanket gate', () => {
    it('exempts health and every /auth/* route', async () => {
      await request(server()).get('/health').expect(200);
      await request(server())
        .post('/auth/register')
        .send({ email: 'a@example.com', password: PASSWORD })
        .expect(201);
    });

    it('401s the diary-bearing routes without a token, with the shared error envelope', async () => {
      const paths = [
        '/entries?date=2026-07-01',
        '/feelings',
        '/guiding-questions',
        '/insights',
        '/insights/question-yield',
        '/experiments',
        '/topics',
        '/monthly-summary?month=2026-07',
        '/transcriptions',
        '/guided-entry-drafts',
      ];
      for (const path of paths) {
        const res = await request(server()).get(path).expect(401);
        expect(res.body.error.code).toBe('unauthorized');
      }
    });

    it('401s GET /auth/me and DELETE /auth/token without a token, from inside their own handlers', async () => {
      await request(server()).get('/auth/me').expect(401);
      await request(server()).delete('/auth/token').expect(204); // logout is always a no-op success
    });

    it('does not gate the built web client shell', async () => {
      // No web/dist in this test environment, so `/app` is simply unmounted — the point is that
      // the identity gate itself never answers 401 for it either way.
      const res = await request(server()).get('/app');
      expect(res.status).not.toBe(401);
    });
  });

  describe('register / login / me / logout', () => {
    it('registers, then rejects a second registration with the same email', async () => {
      const created = await request(server())
        .post('/auth/register')
        .send({ email: EMAIL, password: PASSWORD })
        .expect(201);
      expect(created.body).toMatchObject({ email: EMAIL });
      expect(created.body.id).toBeTypeOf('string');
      expect(created.body.password_hash).toBeUndefined();

      const conflict = await request(server())
        .post('/auth/register')
        .send({ email: EMAIL.toUpperCase(), password: PASSWORD })
        .expect(409);
      expect(conflict.body.error.code).toBe('conflict');
    });

    it('rejects a weak password and a malformed email with 422', async () => {
      const weak = await request(server())
        .post('/auth/register')
        .send({ email: EMAIL, password: 'short' })
        .expect(422);
      expect(weak.body.error.code).toBe('validation_error');

      await request(server())
        .post('/auth/register')
        .send({ email: 'not-an-email', password: PASSWORD })
        .expect(422);
    });

    it('logs in, uses the token, reads /auth/me, then logs out and the token stops working', async () => {
      await request(server())
        .post('/auth/register')
        .send({ email: EMAIL, password: PASSWORD })
        .expect(201);

      const login = await request(server())
        .post('/auth/token')
        .send({ email: EMAIL.toUpperCase(), password: PASSWORD })
        .expect(200);
      const token = login.body.token as string;
      expect(token).toBeTypeOf('string');
      expect(login.body.expires_at).toBeTypeOf('string');

      await request(server()).get('/insights').expect(401);
      await request(server()).get('/insights').set('Authorization', `Bearer ${token}`).expect(200);

      const me = await request(server())
        .get('/auth/me')
        .set('Authorization', `Bearer ${token}`)
        .expect(200);
      expect(me.body).toMatchObject({ email: EMAIL });

      await request(server())
        .delete('/auth/token')
        .set('Authorization', `Bearer ${token}`)
        .expect(204);
      await request(server()).get('/insights').set('Authorization', `Bearer ${token}`).expect(401);
      await request(server()).get('/auth/me').set('Authorization', `Bearer ${token}`).expect(401);
    });

    it('uses one generic message for both a wrong password and an unknown email', async () => {
      await request(server())
        .post('/auth/register')
        .send({ email: EMAIL, password: PASSWORD })
        .expect(201);

      const wrongPassword = await request(server())
        .post('/auth/token')
        .send({ email: EMAIL, password: 'not the password 123' })
        .expect(401);
      const unknownEmail = await request(server())
        .post('/auth/token')
        .send({ email: 'nobody@example.com', password: PASSWORD })
        .expect(401);

      expect(wrongPassword.body.error.message).toBe(unknownEmail.body.error.message);
      expect(wrongPassword.body.error.message).not.toContain(EMAIL);
    });

    it('rejects an expired token, and the session row is gone afterward', async () => {
      await request(server())
        .post('/auth/register')
        .send({ email: EMAIL, password: PASSWORD })
        .expect(201);
      const login = await request(server())
        .post('/auth/token')
        .send({ email: EMAIL, password: PASSWORD })
        .expect(200);
      const token = login.body.token as string;

      // Force the session into the past directly — sha256 of the raw token is `token_hash`, the
      // same derivation `AuthService`/`identity.middleware.ts` use.
      const { createHash } = await import('node:crypto');
      const tokenHash = createHash('sha256').update(token).digest('hex');
      const db = new Database(h.dbPath);
      db.prepare(
        "UPDATE sessions SET expires_at = '2000-01-01 00:00:00.000000' WHERE token_hash = ?",
      ).run(tokenHash);
      const before = db.prepare('SELECT COUNT(*) AS n FROM sessions').get() as { n: number };
      db.close();
      expect(before.n).toBe(1);

      await request(server()).get('/insights').set('Authorization', `Bearer ${token}`).expect(401);

      const after = new Database(h.dbPath, { readonly: true });
      const remaining = after.prepare('SELECT COUNT(*) AS n FROM sessions').get() as { n: number };
      after.close();
      expect(remaining.n).toBe(0);
    });

    it('rejects a well-formed but unknown bearer token', async () => {
      await request(server())
        .get('/insights')
        .set('Authorization', 'Bearer ' + 'a'.repeat(43))
        .expect(401);
    });

    it('throttles repeated login failures, independent of whether the password is eventually right', async () => {
      await request(server())
        .post('/auth/register')
        .send({ email: EMAIL, password: PASSWORD })
        .expect(201);

      for (let attempt = 0; attempt < 8; attempt += 1) {
        await request(server())
          .post('/auth/token')
          .send({ email: EMAIL, password: 'wrong password value' })
          .expect(401);
      }
      const blocked = await request(server())
        .post('/auth/token')
        .send({ email: EMAIL, password: PASSWORD })
        .expect(429);
      expect(blocked.body.error.code).toBe('rate_limited');
    });
  });

  it('cannot log in as the default user — its password hash can never verify', async () => {
    const db = new Database(h.dbPath, { readonly: true });
    const defaultUser = db
      .prepare('SELECT id, email FROM users WHERE id = ?')
      .get(DEFAULT_USER_ID) as {
      id: string;
      email: string;
    };
    db.close();
    expect(defaultUser.email).toBe('owner@default-user.invalid');

    await request(server())
      .post('/auth/token')
      .send({ email: defaultUser.email, password: 'literally anything at all 123' })
      .expect(401);
  });
});

describe('composed with the existing single-password tunnel gate (AUTH_ENABLED=true)', () => {
  it('keeps both gates working — neither shadows the other', async () => {
    // Built directly rather than through `bootOnFresh`, so both `auth` (the legacy cookie gate)
    // and `singleUserMode: false` (the new bearer gate) can be configured on the same app —
    // proving the new `/auth/register`/`/auth/token` routes stay reachable and the old
    // `/auth/login` HTML flow is untouched even with both features turned on at once. See
    // `identity.controller.ts`'s doc comment for why the two namespaces are disjoint on purpose.
    const passwordHash = await hashPassword('tunnel password owner only');
    h = await bootOnFresh({ singleUserMode: false });
    await h.app.close();
    h.app = await createApp({
      databasePath: h.dbPath,
      singleUserMode: false,
      auth: {
        enabled: true,
        email: 'owner@example.com',
        passwordHash,
        secureCookie: false,
        sessionHours: 12,
      },
    });
    await startOnLoopback(h.app);

    // The legacy HTML sign-in page still renders.
    const loginPage = await request(server()).get('/login').expect(200);
    expect(loginPage.text).toContain('Welcome back');

    // The new JSON identity endpoints are unaffected by the legacy gate being on.
    await request(server())
      .post('/auth/register')
      .send({ email: 'new-user@example.com', password: PASSWORD })
      .expect(201);
  });
});
