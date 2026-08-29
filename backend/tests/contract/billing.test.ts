/**
 * Server-side entitlements (M-2, #47): `POST /billing/play/verify` against a `FakePlayVerifier`
 * (never the network — recon: "No test may reach the network"), `GET /auth/me` reflecting tier and
 * expiry, the live-expiry check, the daily sweep, and the `MANUAL_ENTITLEMENTS=true` dev bypass —
 * this suite is the "curl walkthrough with MANUAL_ENTITLEMENTS=true" the issue's verification
 * section asks for, turned into an e2e test per the recon's instruction.
 */

import Database from 'better-sqlite3';
import request from 'supertest';
import { afterEach, describe, expect, it } from 'vitest';
import { DEFAULT_USER_ID } from '../../src/auth/default-user';
import { EntitlementsService } from '../../src/billing/entitlements.service';
import { FakePlayVerifier } from '../../src/billing/fake-play-verifier';
import {
  GooglePlayVerificationError,
  type PlayPurchaseVerifier,
} from '../../src/billing/play-verifier';
import { bootOnFresh, teardown, type Harness } from '../helpers/app';

let h: Harness;
const server = () => h.app.getHttpServer();

afterEach(async () => {
  await teardown(h);
});

const EMAIL = 'buyer@example.com';
const PASSWORD = 'correct horse battery staple';

async function registerAndLogin(): Promise<string> {
  await request(server())
    .post('/auth/register')
    .send({ email: EMAIL, password: PASSWORD })
    .expect(201);
  const login = await request(server())
    .post('/auth/token')
    .send({ email: EMAIL, password: PASSWORD })
    .expect(200);
  return login.body.token as string;
}

describe('POST /billing/play/verify with a fake verifier', () => {
  it('grants premium for a valid subscription token, and GET /auth/me reflects it', async () => {
    const verifier = new FakePlayVerifier().respondTo('good-token', {
      valid: true,
      expiresAt: '2030-01-01 00:00:00.000000',
    });
    h = await bootOnFresh({ singleUserMode: false, playVerifier: verifier });
    const token = await registerAndLogin();

    const before = await request(server())
      .get('/auth/me')
      .set('Authorization', `Bearer ${token}`)
      .expect(200);
    expect(before.body).toMatchObject({ email: EMAIL, tier: 'free', expires_at: null });

    const verify = await request(server())
      .post('/billing/play/verify')
      .set('Authorization', `Bearer ${token}`)
      .send({ purchase_token: 'good-token', product_id: 'premium_yearly' })
      .expect(200);
    expect(verify.body).toEqual({ tier: 'premium', expires_at: '2030-01-01 00:00:00.000000' });
    expect(verifier.calls).toEqual([
      { purchaseToken: 'good-token', productId: 'premium_yearly', productType: 'subscription' },
    ]);

    const after = await request(server())
      .get('/auth/me')
      .set('Authorization', `Bearer ${token}`)
      .expect(200);
    expect(after.body).toMatchObject({
      email: EMAIL,
      tier: 'premium',
      expires_at: '2030-01-01 00:00:00.000000',
    });
  });

  it('grants a lifetime one-time purchase that never expires', async () => {
    const verifier = new FakePlayVerifier().respondTo('lifetime-token', {
      valid: true,
      expiresAt: null,
    });
    h = await bootOnFresh({ singleUserMode: false, playVerifier: verifier });
    const token = await registerAndLogin();

    const res = await request(server())
      .post('/billing/play/verify')
      .set('Authorization', `Bearer ${token}`)
      .send({
        purchase_token: 'lifetime-token',
        product_id: 'premium_lifetime',
        product_type: 'onetime',
      })
      .expect(200);
    expect(res.body).toEqual({ tier: 'premium', expires_at: null });
    expect(verifier.calls).toEqual([
      { purchaseToken: 'lifetime-token', productId: 'premium_lifetime', productType: 'onetime' },
    ]);

    const me = await request(server())
      .get('/auth/me')
      .set('Authorization', `Bearer ${token}`)
      .expect(200);
    // A "now" far in the future must still read a lifetime grant as premium.
    expect(me.body).toMatchObject({ tier: 'premium', expires_at: null });
  });

  it('answers 422 for a token the verifier reports as invalid — a refused purchase, not an outage', async () => {
    const verifier = new FakePlayVerifier(); // unprogrammed tokens default to invalid
    h = await bootOnFresh({ singleUserMode: false, playVerifier: verifier });
    const token = await registerAndLogin();

    const res = await request(server())
      .post('/billing/play/verify')
      .set('Authorization', `Bearer ${token}`)
      .send({ purchase_token: 'bad-token', product_id: 'premium_yearly' })
      .expect(422);
    expect(res.body.error.code).toBe('validation_error');

    const me = await request(server())
      .get('/auth/me')
      .set('Authorization', `Bearer ${token}`)
      .expect(200);
    expect(me.body).toMatchObject({ tier: 'free', expires_at: null });
  });

  it('answers 502, not 422, when the verifier cannot even reach Google', async () => {
    class ThrowingVerifier implements PlayPurchaseVerifier {
      async verify(): Promise<never> {
        throw new GooglePlayVerificationError('simulated outage');
      }
    }
    h = await bootOnFresh({ singleUserMode: false, playVerifier: new ThrowingVerifier() });
    const token = await registerAndLogin();

    const res = await request(server())
      .post('/billing/play/verify')
      .set('Authorization', `Bearer ${token}`)
      .send({ purchase_token: 'x', product_id: 'y' })
      .expect(502);
    // 502 has no entry in `ErrorEnvelopeFilter`'s ERROR_CODES map, so it falls back to the generic
    // code — the point of this test is the status, not the code string.
    expect(res.body.error).toBeDefined();
  });

  it('rejects a malformed body with 422, before ever calling the verifier', async () => {
    const verifier = new FakePlayVerifier();
    h = await bootOnFresh({ singleUserMode: false, playVerifier: verifier });
    const token = await registerAndLogin();

    await request(server())
      .post('/billing/play/verify')
      .set('Authorization', `Bearer ${token}`)
      .send({})
      .expect(422);
    expect(verifier.calls).toEqual([]);
  });

  it('401s without a bearer token when SINGLE_USER_MODE is off', async () => {
    h = await bootOnFresh({ singleUserMode: false, playVerifier: new FakePlayVerifier() });
    await request(server())
      .post('/billing/play/verify')
      .send({ purchase_token: 'x', product_id: 'y' })
      .expect(401);
  });
});

describe('expiry: live on read, and the daily sweep', () => {
  it('GET /auth/me reads an expired subscription as free immediately, before any sweep runs', async () => {
    const verifier = new FakePlayVerifier().respondTo('short-token', {
      valid: true,
      // Already in the past relative to any real clock this test runs under.
      expiresAt: '2000-01-01 00:00:00.000000',
    });
    h = await bootOnFresh({ singleUserMode: false, playVerifier: verifier });
    const token = await registerAndLogin();

    await request(server())
      .post('/billing/play/verify')
      .set('Authorization', `Bearer ${token}`)
      .send({ purchase_token: 'short-token', product_id: 'premium_yearly' })
      .expect(200);

    const me = await request(server())
      .get('/auth/me')
      .set('Authorization', `Bearer ${token}`)
      .expect(200);
    expect(me.body).toMatchObject({ tier: 'free', expires_at: null });
  });

  it('sweepExpired normalises the stored row from premium to free, and is a no-op on a second run', async () => {
    const verifier = new FakePlayVerifier().respondTo('short-token', {
      valid: true,
      expiresAt: '2000-01-01 00:00:00.000000',
    });
    h = await bootOnFresh({ singleUserMode: false, playVerifier: verifier });
    const token = await registerAndLogin();
    await request(server())
      .post('/billing/play/verify')
      .set('Authorization', `Bearer ${token}`)
      .send({ purchase_token: 'short-token', product_id: 'premium_yearly' })
      .expect(200);

    // Before the sweep, `getEntitlement` already reads free (previous test), but the stored row
    // still says premium — that gap is exactly what the sweep exists to close.
    const before = new Database(h.dbPath, { readonly: true });
    const storedBefore = before.prepare('SELECT tier FROM entitlements').get() as { tier: string };
    before.close();
    expect(storedBefore.tier).toBe('premium');

    const entitlements = h.app.get(EntitlementsService);
    expect(entitlements.sweepExpired()).toBe(1);

    const after = new Database(h.dbPath, { readonly: true });
    const storedAfter = after.prepare('SELECT tier, expires_at FROM entitlements').get() as {
      tier: string;
      expires_at: string | null;
    };
    after.close();
    expect(storedAfter).toEqual({ tier: 'free', expires_at: null });

    expect(entitlements.sweepExpired()).toBe(0);
  });

  it('never sweeps a lifetime (NULL expiry) grant', async () => {
    const verifier = new FakePlayVerifier().respondTo('lifetime-token', {
      valid: true,
      expiresAt: null,
    });
    h = await bootOnFresh({ singleUserMode: false, playVerifier: verifier });
    const token = await registerAndLogin();
    await request(server())
      .post('/billing/play/verify')
      .set('Authorization', `Bearer ${token}`)
      .send({
        purchase_token: 'lifetime-token',
        product_id: 'premium_lifetime',
        product_type: 'onetime',
      })
      .expect(200);

    expect(h.app.get(EntitlementsService).sweepExpired()).toBe(0);
    const me = await request(server())
      .get('/auth/me')
      .set('Authorization', `Bearer ${token}`)
      .expect(200);
    expect(me.body).toMatchObject({ tier: 'premium', expires_at: null });
  });
});

describe('MANUAL_ENTITLEMENTS dev mode (acceptance criterion 4: zero Google setup)', () => {
  it('POST /billing/admin/grant is a 404 — not reachable — when the flag is off', async () => {
    // `singleUserMode` defaults to on here specifically so this 404 is not confounded with the
    // identity gate's own 401 for a missing bearer token — the point of this test is that the
    // *route itself* answers 404 when `manualEntitlements` is off, regardless of who is asking.
    h = await bootOnFresh();
    await request(server())
      .post('/billing/admin/grant')
      .send({ user_id: DEFAULT_USER_ID, tier: 'premium' })
      .expect(404);
  });

  it('grants premium for any token with no verifier configured at all, recorded as source "manual"', async () => {
    // No `playVerifier` override — `AppModule` must pick `ManualPlayVerifier` on its own from
    // `manualEntitlements: true`, exactly as a real deployment with `MANUAL_ENTITLEMENTS=true` and
    // no `GOOGLE_PLAY_*` variables set at all would.
    h = await bootOnFresh({ manualEntitlements: true });

    const res = await request(server())
      .post('/billing/play/verify')
      .send({ purchase_token: 'anything-at-all', product_id: 'anything' })
      .expect(200);
    expect(res.body).toEqual({ tier: 'premium', expires_at: null });

    const db = new Database(h.dbPath, { readonly: true });
    const row = db
      .prepare('SELECT source FROM entitlements WHERE user_id = ?')
      .get(DEFAULT_USER_ID) as {
      source: string;
    };
    db.close();
    // Recorded as 'manual', not 'play' — see `ManualPlayVerifier`'s doc comment: the source column
    // is what tells a dev bypass apart from a real verified purchase, not which endpoint was hit.
    expect(row.source).toBe('manual');
  });

  it('POST /billing/admin/grant sets an arbitrary tier and ISO-8601 expiry for a named user', async () => {
    h = await bootOnFresh({ manualEntitlements: true });

    const grant = await request(server())
      .post('/billing/admin/grant')
      .send({ user_id: DEFAULT_USER_ID, tier: 'premium', expires_at: '2030-06-15T00:00:00.000Z' })
      .expect(200);
    expect(grant.body).toEqual({ tier: 'premium', expires_at: '2030-06-15 00:00:00.000000' });
  });

  it('POST /billing/admin/grant answers 404 for a user id that does not exist', async () => {
    h = await bootOnFresh({ manualEntitlements: true });
    await request(server())
      .post('/billing/admin/grant')
      .send({ user_id: 'not-a-real-user-id', tier: 'premium' })
      .expect(404);
  });

  it('POST /billing/admin/grant back to free ignores any expires_at sent for it', async () => {
    h = await bootOnFresh({ manualEntitlements: true });
    await request(server())
      .post('/billing/admin/grant')
      .send({ user_id: DEFAULT_USER_ID, tier: 'premium', expires_at: '2030-06-15T00:00:00.000Z' })
      .expect(200);

    const grant = await request(server())
      .post('/billing/admin/grant')
      .send({ user_id: DEFAULT_USER_ID, tier: 'free', expires_at: '2030-06-15T00:00:00.000Z' })
      .expect(200);
    expect(grant.body).toEqual({ tier: 'free', expires_at: null });
  });
});
