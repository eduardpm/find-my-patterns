/**
 * `EntitlementsService` (M-2, #47): the one place "is this user premium right now" is decided.
 *
 * Runs against a real (throwaway) diary rather than a mock connection — the SQL itself (the
 * upsert, the live expiry check, the sweep's `WHERE`) is exactly what needs proving correct, and
 * `better-sqlite3` against a temp file is fast enough that mocking it buys nothing but risk of the
 * mock disagreeing with real SQLite. Mirrors `tests/seed-noop.test.ts`'s pattern: a fresh copy of
 * the golden fixture per test, `openDiary` directly, no HTTP layer.
 */

import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { DEFAULT_USER_ID } from '../../src/auth/default-user';
import { EntitlementsService } from '../../src/billing/entitlements.service';
import { openDiary, type DiaryDatabase } from '../../src/db/database';

const GOLDEN = path.resolve(__dirname, '../fixtures/golden.db');

let dir: string;
let db: DiaryDatabase;
let service: EntitlementsService;

beforeEach(() => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'diary-entitlements-'));
  const dbPath = path.join(dir, 'diary.db');
  fs.copyFileSync(GOLDEN, dbPath);
  db = openDiary(dbPath);
  service = new EntitlementsService(db);
});

afterEach(() => {
  db.close();
  fs.rmSync(dir, { recursive: true, force: true });
});

describe('getEntitlement', () => {
  it('reads free for a user with no row at all — absence means free', () => {
    expect(service.getEntitlement(DEFAULT_USER_ID)).toEqual({ tier: 'free', expires_at: null });
  });

  it('reads back a lifetime grant as premium with a null expiry, forever', () => {
    service.grant(DEFAULT_USER_ID, 'premium', 'manual', null);
    expect(service.getEntitlement(DEFAULT_USER_ID)).toEqual({ tier: 'premium', expires_at: null });
    // A "now" far in the future must not expire a lifetime grant — NULL is never a candidate.
    expect(service.getEntitlement(DEFAULT_USER_ID, '2999-01-01 00:00:00.000000')).toEqual({
      tier: 'premium',
      expires_at: null,
    });
  });

  it('reads a not-yet-expired subscription as premium', () => {
    service.grant(DEFAULT_USER_ID, 'premium', 'play', '2030-01-01 00:00:00.000000');
    expect(service.getEntitlement(DEFAULT_USER_ID, '2029-12-31 23:59:59.000000')).toEqual({
      tier: 'premium',
      expires_at: '2030-01-01 00:00:00.000000',
    });
  });

  it('reads an expired subscription as free the instant it lapses, even before any sweep runs', () => {
    service.grant(DEFAULT_USER_ID, 'premium', 'play', '2030-01-01 00:00:00.000000');
    expect(service.getEntitlement(DEFAULT_USER_ID, '2030-01-01 00:00:00.000000')).toEqual({
      tier: 'free',
      expires_at: null,
    });
    expect(service.getEntitlement(DEFAULT_USER_ID, '2030-06-01 00:00:00.000000')).toEqual({
      tier: 'free',
      expires_at: null,
    });
  });

  it('never expires an explicit free row (expires_at is meaningless once tier is free)', () => {
    service.grant(DEFAULT_USER_ID, 'free', 'manual', null);
    expect(service.getEntitlement(DEFAULT_USER_ID, '2999-01-01 00:00:00.000000')).toEqual({
      tier: 'free',
      expires_at: null,
    });
  });
});

describe('grant', () => {
  it('refuses to grant an entitlement to a user id that does not exist', () => {
    expect(() => service.grant('not-a-real-user', 'premium', 'manual', null)).toThrow(
      /No user with id/,
    );
    expect(db.prepare('SELECT COUNT(*) AS n FROM entitlements').get()).toEqual({ n: 0 });
  });

  it('upserts — a second grant replaces the first outright, not alongside it', () => {
    service.grant(DEFAULT_USER_ID, 'premium', 'play', '2030-01-01 00:00:00.000000');
    service.grant(DEFAULT_USER_ID, 'premium', 'manual', null);
    expect(service.getEntitlement(DEFAULT_USER_ID)).toEqual({ tier: 'premium', expires_at: null });

    const rows = db.prepare('SELECT COUNT(*) AS n FROM entitlements').get() as { n: number };
    expect(rows.n).toBe(1);
  });
});

describe('sweepExpired', () => {
  it('drops an expired premium row to free and clears its expiry', () => {
    service.grant(DEFAULT_USER_ID, 'premium', 'play', '2030-01-01 00:00:00.000000');

    const changed = service.sweepExpired('2030-01-01 00:00:00.000000');
    expect(changed).toBe(1);
    expect(service.getEntitlement(DEFAULT_USER_ID)).toEqual({ tier: 'free', expires_at: null });

    const row = db
      .prepare('SELECT tier, expires_at FROM entitlements WHERE user_id = ?')
      .get(DEFAULT_USER_ID) as { tier: string; expires_at: string | null };
    expect(row).toEqual({ tier: 'free', expires_at: null });
  });

  it('leaves a subscription with time remaining untouched', () => {
    service.grant(DEFAULT_USER_ID, 'premium', 'play', '2030-01-01 00:00:00.000000');
    const changed = service.sweepExpired('2029-12-31 23:59:59.999999');
    expect(changed).toBe(0);
    expect(service.getEntitlement(DEFAULT_USER_ID).tier).toBe('premium');
  });

  it('never touches a lifetime (NULL expiry) grant, no matter how far in the future "now" is', () => {
    service.grant(DEFAULT_USER_ID, 'premium', 'manual', null);
    const changed = service.sweepExpired('2999-01-01 00:00:00.000000');
    expect(changed).toBe(0);
    expect(service.getEntitlement(DEFAULT_USER_ID)).toEqual({ tier: 'premium', expires_at: null });
  });

  it('is a no-op on a diary with no entitlement rows at all', () => {
    expect(service.sweepExpired()).toBe(0);
  });
});
