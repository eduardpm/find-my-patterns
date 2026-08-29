import { createSign } from 'node:crypto';
import type { GooglePlayConfig } from '../config';
import { encodeDateTime } from '../db/codecs';

/**
 * What a Google Play product is: a subscription renews and reports an expiry, a one-time product
 * ("onetime") is a single purchase Play never expires on its own — the natural fit for a lifetime
 * unlock. The caller (`EntitlementsController`) decides which this purchase token names; nothing
 * here infers it, because the same numeric `purchaseState` field on a one-time product means
 * something different from a subscription's `expiryTimeMillis`, and guessing wrong would silently
 * grant the wrong entitlement shape.
 */
export type GooglePlayProductType = 'subscription' | 'onetime';

/**
 * What verifying one purchase token establishes, independent of *how* it was verified — this is
 * the one shape `GooglePlayVerifier`, `FakePlayVerifier` (`./fake-play-verifier.ts`) and
 * `ManualPlayVerifier` below all produce, and the one shape `EntitlementsService.grant` consumes.
 */
export interface PurchaseVerification {
  /** False for a token Play does not recognise, or reports as refunded/voided/pending — anything
   * that is not "this purchase is currently entitled to the product". */
  valid: boolean;
  /** Only meaningful when `valid` is true. `null` is a lifetime purchase (`schema.ts`'s "NULL
   * expiry = lifetime"); encoded per `db/codecs.ts` otherwise. */
  expiresAt: string | null;
}

/**
 * The seam the issue's task 2 asks for: "make the verifier an interface with a fake for tests."
 * Every caller — the controller, the guard, this file's own real and manual implementations —
 * depends on this and nothing more specific, which is what makes `FakePlayVerifier` a complete
 * stand-in rather than a partial mock. No test in this repository is permitted to reach the
 * network (recon), and this interface is the only thing that stands between a unit/e2e test and an
 * actual call to Google.
 */
export interface PlayPurchaseVerifier {
  verify(
    purchaseToken: string,
    productId: string,
    productType: GooglePlayProductType,
  ): Promise<PurchaseVerification>;
}

const OAUTH_SCOPE = 'https://www.googleapis.com/auth/androidpublisher';
const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const API_ROOT = 'https://androidpublisher.googleapis.com/androidpublisher/v3/applications';

/** Thrown by `GooglePlayVerifier` when Play or Google's token endpoint answers with anything this
 * code cannot interpret as "valid" or "invalid" — a network failure, a 5xx, a malformed body. This
 * is deliberately distinct from `{ valid: false }`: that return value means "Play looked at this
 * token and said no," which `EntitlementsController` turns into "purchase not verified." This
 * exception means "the question could not be asked," which the controller instead turns into a
 * 502 — conflating the two would let a Google outage silently read as every customer's
 * subscription having been revoked. */
export class GooglePlayVerificationError extends Error {}

/**
 * The real Google Play Developer API verifier (issue task 2).
 *
 * Authenticates as a service account via a hand-signed RS256 JWT bearer assertion (the standard
 * OAuth2 "JWT Bearer Token" flow) rather than pulling in `google-auth-library`: the whole exchange
 * is one signed JSON object and one token-endpoint POST, both of which Node's built-in `crypto` and
 * `fetch` already do, and adding a dependency whose only job is exactly that would cost more in
 * review surface than it saves in code here.
 *
 * No test constructs this against the real network (recon: "No test may reach the network") — it
 * is exercised only by the maintainer's own curl walkthrough, with real credentials, outside this
 * suite.
 *
 * `credentials` is `undefined` whenever `MANUAL_ENTITLEMENTS` was unset and the three
 * `GOOGLE_PLAY_*` env vars were never configured — `config.ts`'s `loadBillingConfig` does not fail
 * server startup over that, since a fresh deployment with no Play integration wired up yet (the
 * state of this project today) must still boot. The cost of deferring the check is paid only by
 * whoever actually calls `POST /billing/play/verify` without configuring it, as a clear error
 * instead of a crash at boot.
 */
export class GooglePlayVerifier implements PlayPurchaseVerifier {
  constructor(private readonly credentials: GooglePlayConfig | undefined) {}

  async verify(
    purchaseToken: string,
    productId: string,
    productType: GooglePlayProductType,
  ): Promise<PurchaseVerification> {
    if (!this.credentials) {
      throw new GooglePlayVerificationError(
        'Google Play verification is not configured. Set GOOGLE_PLAY_SERVICE_ACCOUNT_EMAIL, ' +
          'GOOGLE_PLAY_SERVICE_ACCOUNT_KEY and GOOGLE_PLAY_PACKAGE_NAME, or set ' +
          'MANUAL_ENTITLEMENTS=true for local development.',
      );
    }
    const credentials = this.credentials;
    const accessToken = await this.getAccessToken(credentials);
    const path =
      productType === 'subscription'
        ? `purchases/subscriptions/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(purchaseToken)}`
        : `purchases/products/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(purchaseToken)}`;
    const url = `${API_ROOT}/${encodeURIComponent(credentials.packageName)}/${path}`;

    const response = await fetch(url, { headers: { Authorization: `Bearer ${accessToken}` } });

    // Play's documented "this token names no purchase it knows about" responses. Distinct from a
    // real failure below — a stolen or fabricated token is an everyday, expected `valid: false`,
    // not an outage.
    if (response.status === 404 || response.status === 410) {
      return { valid: false, expiresAt: null };
    }
    if (!response.ok) {
      throw new GooglePlayVerificationError(
        `Google Play purchase lookup failed with status ${response.status}.`,
      );
    }

    const body = (await response.json()) as Record<string, unknown>;

    if (productType === 'onetime') {
      // purchases.products.get: purchaseState 0 = purchased, 1 = canceled, 2 = pending. Only 0 is
      // a currently-valid, non-refunded purchase. One-time products never expire on their own —
      // this is exactly the "lifetime" shape `expiresAt: null` exists for.
      const purchaseState = Number(body.purchaseState ?? 1);
      return { valid: purchaseState === 0, expiresAt: null };
    }

    // purchases.subscriptions.get: expiryTimeMillis is a string epoch-millisecond field. A missing
    // or unparseable value cannot be trusted as "currently entitled," so it reads as invalid rather
    // than as a lifetime grant — the failure mode of guessing wrong here (silently unlimited
    // premium) is far worse than the failure mode of guessing conservatively (a support ticket).
    const expiryMillis = Number(body.expiryTimeMillis);
    if (!Number.isFinite(expiryMillis)) return { valid: false, expiresAt: null };
    return { valid: true, expiresAt: encodeEpochMillis(expiryMillis) };
  }

  private async getAccessToken(credentials: GooglePlayConfig): Promise<string> {
    const issuedAt = Math.floor(Date.now() / 1000);
    const header = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
    const claims = base64url(
      JSON.stringify({
        iss: credentials.serviceAccountEmail,
        scope: OAUTH_SCOPE,
        aud: TOKEN_URL,
        iat: issuedAt,
        // Google caps this at one hour; the token is used once, immediately, so there is no reason
        // to ask for longer.
        exp: issuedAt + 3600,
      }),
    );
    const signingInput = `${header}.${claims}`;
    let signature: string;
    try {
      signature = createSign('RSA-SHA256')
        .update(signingInput)
        .sign(credentials.privateKey, 'base64url');
    } catch (error) {
      throw new GooglePlayVerificationError(
        `GOOGLE_PLAY_SERVICE_ACCOUNT_KEY could not be used to sign a JWT: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    }
    const assertion = `${signingInput}.${signature}`;

    const response = await fetch(TOKEN_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion,
      }),
    });
    if (!response.ok) {
      // Never log `assertion` or the response body here — both can carry credential material
      // (recon: "Never log secrets"). The status code is enough to diagnose a misconfigured
      // service account from the server's own logs.
      throw new GooglePlayVerificationError(
        `Google OAuth2 token exchange failed with status ${response.status}.`,
      );
    }
    const body = (await response.json()) as { access_token?: string };
    if (!body.access_token) {
      throw new GooglePlayVerificationError('Google OAuth2 token response had no access_token.');
    }
    return body.access_token;
  }
}

function base64url(input: string): string {
  return Buffer.from(input).toString('base64url');
}

/** An epoch-millisecond timestamp, as `codecs.ts` wants it. Millisecond precision from Play (or
 * from an admin's ISO-8601 grant, `entitlements.controller.ts`) is already coarser than this
 * format's microsecond field, so the low three digits are always zero — fine, since nothing
 * compares an `expires_at` this coarse at sub-millisecond precision. Exported so
 * `EntitlementsController`'s admin grant endpoint shares this one conversion rather than growing
 * its own third copy alongside this one and `AuthService`'s private `encodeInstant`
 * (`../auth/identity.service.ts`). */
export function encodeEpochMillis(epochMs: number): string {
  const date = new Date(epochMs);
  return encodeDateTime({
    year: date.getUTCFullYear(),
    month: date.getUTCMonth() + 1,
    day: date.getUTCDate(),
    hour: date.getUTCHours(),
    minute: date.getUTCMinutes(),
    second: date.getUTCSeconds(),
    microsecond: date.getUTCMilliseconds() * 1000,
  });
}

/**
 * The `MANUAL_ENTITLEMENTS=true` dev-mode verifier (issue task 2's third bullet: "a dev mode that
 * skips Google entirely").
 *
 * Distinct from `FakePlayVerifier` (`./fake-play-verifier.ts`) even though both avoid the network:
 * the fake is a **test double**, constructed per-test with whatever canned result that test wants,
 * and is never wired up by `AppModule` outside a test overriding it. This is a **runtime mode**,
 * selected by an environment variable and used by a real running server — the thing the recon's
 * acceptance criterion 4 ("dev mode works with zero Google setup") and the maintainer's own curl
 * walkthrough exercise. It always succeeds, as a lifetime grant, for any token — there is no Google
 * to ask "is this real," and the point of this mode is exercising the entitlement plumbing (the
 * table, the sweep, `GET /auth/me`) without needing a Play Console service account at all.
 *
 * `EntitlementsController` records the resulting grant with `source: 'manual'`, not `'play'`, even
 * though the request arrived at `/billing/play/verify` — see that controller's doc comment for why
 * the source column, not the endpoint name, is what tells a real verified purchase apart from a dev
 * bypass.
 */
export class ManualPlayVerifier implements PlayPurchaseVerifier {
  async verify(): Promise<PurchaseVerification> {
    return { valid: true, expiresAt: null };
  }
}
