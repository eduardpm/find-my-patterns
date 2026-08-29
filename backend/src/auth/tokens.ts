import { createHash, randomBytes } from 'node:crypto';

/**
 * Opaque bearer tokens (M-1a, #45).
 *
 * **Opaque + server-stored, not a JWT.** A JWT would let this backend skip a database lookup per
 * request, but the only way to revoke one before it expires is to maintain a deny-list — which is
 * itself a server-stored revocation record, the exact thing an opaque token already gives for free.
 * A stolen or leaked token that must stop working *now* (the recon's stated concern) is one `DELETE
 * FROM sessions` away with this design; with a JWT it is a support ticket asking the user to wait
 * out the expiry. The one lookup this costs is on `sessions.token_hash`, which is the primary key —
 * cheap, and this backend already does a DB round trip per request for everything else.
 *
 * The raw token is 32 random bytes, base64url-encoded — 256 bits of entropy, unguessable and URL
 * safe for an `Authorization: Bearer …` header. Only `hashToken`'s output is ever stored
 * (`sessions.token_hash`): the same reasoning that keeps `password_hash` instead of a password
 * applies here — a leaked database row must not itself be a usable credential. SHA-256 rather than
 * `scrypt` (`./password.ts`) is deliberate and not a downgrade: `scrypt`'s cost defends a low-entropy
 * human password against offline guessing, but a 256-bit random token is never guessed, only stolen
 * — a fast, unsalted hash is exactly right for turning "the bearer of this string" into a lookup
 * key without also becoming a self-inflicted denial-of-service on every authenticated request.
 */

export function generateToken(): string {
  return randomBytes(32).toString('base64url');
}

export function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

/** How long a bearer token is valid for once issued. Long-lived on purpose: this authenticates a
 * mobile app a person expects to stay signed into for weeks, not a browser tab. Revocation is what
 * makes that safe (`DELETE /auth/token`) rather than the expiry doing the work. */
export const TOKEN_TTL_MS = 30 * 24 * 60 * 60 * 1000;

/** Parses `Authorization: Bearer <token>`. Returns `null` for anything else — a missing header, a
 * different scheme, or an empty token — so callers can treat "no token" and "malformed header" the
 * same way (both simply fail to authenticate). */
export function extractBearerToken(header: string | undefined): string | null {
  if (!header) return null;
  const [scheme, token] = header.split(' ');
  if (scheme?.toLowerCase() !== 'bearer' || !token) return null;
  return token;
}
