import type { INestApplication } from '@nestjs/common';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import request from 'supertest';
import { afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { hashPassword } from '../../src/auth/password';
import type { AuthConfig } from '../../src/config';
import { createApp } from '../../src/main';
import { GOLDEN } from '../helpers/app';

const EMAIL = 'owner@example.com';
const PASSWORD = 'correct horse diary staple';
let passwordHash: string;
let app: INestApplication | null = null;
let dir: string;

beforeAll(async () => {
  passwordHash = await hashPassword(PASSWORD);
});

beforeEach(() => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'diary-auth-'));
});

afterEach(async () => {
  await app?.close();
  app = null;
  fs.rmSync(dir, { recursive: true, force: true });
});

async function boot(overrides: Partial<AuthConfig> = {}): Promise<void> {
  const dbPath = path.join(dir, 'diary.db');
  fs.copyFileSync(GOLDEN, dbPath);
  const webDistPath = path.join(dir, 'dist');
  fs.mkdirSync(webDistPath);
  fs.writeFileSync(path.join(webDistPath, 'index.html'), '<!doctype html><title>diary</title>');
  app = await createApp({
    databasePath: dbPath,
    webDistPath,
    auth: {
      enabled: true,
      email: EMAIL,
      passwordHash,
      secureCookie: true,
      sessionHours: 12,
      ...overrides,
    },
  });
  await app.init();
}

function server() {
  return app!.getHttpServer();
}

describe('single-user authentication', () => {
  it('leaves health and login public but redirects app pages and rejects API calls', async () => {
    await boot();
    await request(server()).get('/health').expect(200);
    const login = await request(server()).get('/login').expect(200);
    expect(login.text).toContain('Welcome back');
    expect(login.headers['cache-control']).toBe('no-store');

    const page = await request(server()).get('/app/calendar?month=2026-08').expect(303);
    expect(page.headers.location).toBe('/login?next=%2Fapp%2Fcalendar%3Fmonth%3D2026-08');

    const api = await request(server()).get('/insights').expect(401);
    expect(api.body.error.code).toBe('unauthorized');
    expect(api.headers['cache-control']).toBe('no-store');
  });

  it('uses a generic failure, then issues a hardened cookie for valid credentials', async () => {
    await boot();
    const bad = await request(server())
      .post('/auth/login')
      .type('form')
      .send({ email: EMAIL, password: 'not the password', next: '/app/calendar' })
      .expect(401);
    expect(bad.text).toContain('Email or password is incorrect.');
    expect(bad.text).not.toContain(EMAIL);

    const good = await request(server())
      .post('/auth/login')
      .type('form')
      .send({ email: EMAIL.toUpperCase(), password: PASSWORD, next: '/app/calendar' })
      .expect(303);
    expect(good.headers.location).toBe('/app/calendar');
    const cookie = String(good.headers['set-cookie']);
    expect(cookie).toContain('diary_session=');
    expect(cookie).toContain('HttpOnly');
    expect(cookie).toContain('Secure');
    expect(cookie).toContain('SameSite=Strict');

    await request(server()).get('/insights').set('Cookie', cookie).expect(200);
  });

  it('revokes the session on logout and prevents an external return URL', async () => {
    await boot({ secureCookie: false });
    const agent = request.agent(server());
    await agent
      .post('/auth/login')
      .type('form')
      .send({ email: EMAIL, password: PASSWORD, next: 'https://attacker.example' })
      .expect('Location', '/app/today')
      .expect(303);
    await agent.get('/insights').expect(200);
    await agent.post('/auth/logout').expect('Location', '/login?signedOut=1').expect(303);
    await agent.get('/insights').expect(401);
  });

  it('protects only the configured tunnel hostname and rejects cross-origin writes', async () => {
    await boot({ publicHostname: 'diary.example.com', secureCookie: false });
    await request(server()).get('/insights').set('Host', '192.168.1.10:8000').expect(200);
    await request(server()).get('/insights').set('Host', 'diary.example.com').expect(401);

    const login = await request(server())
      .post('/auth/login')
      .set('Host', 'diary.example.com')
      .type('form')
      .send({ email: EMAIL, password: PASSWORD })
      .expect(303);
    const cookie = String(login.headers['set-cookie']);
    await request(server())
      .post('/entries')
      .set('Host', 'diary.example.com')
      .set('Origin', 'https://evil.example')
      .set('Cookie', cookie)
      .send({})
      .expect(403);
  });

  it('throttles repeated failures', async () => {
    await boot();
    for (let attempt = 0; attempt < 8; attempt += 1) {
      await request(server())
        .post('/auth/login')
        .type('form')
        .send({ email: EMAIL, password: 'wrong password value' })
        .expect(401);
    }
    const blocked = await request(server())
      .post('/auth/login')
      .type('form')
      .send({ email: EMAIL, password: PASSWORD })
      .expect(429);
    expect(blocked.headers['retry-after']).toBeDefined();
  });
});
