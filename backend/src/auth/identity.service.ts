import { randomUUID } from 'node:crypto';
import {
  ConflictException,
  HttpException,
  HttpStatus,
  Inject,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import type { DiaryDatabase } from '../db/database';
import { DIARY_DB } from '../db/database.provider';
import { encodeDateTime, nowUtc, type NaiveDateTime } from '../db/codecs';
import { LoginRateLimiter } from './login-rate-limiter';
import { hashPassword, verifyPassword } from './password';
import { generateToken, hashToken, TOKEN_TTL_MS } from './tokens';

const LOGIN_WINDOW_MS = 15 * 60 * 1000;
const MAX_LOGIN_FAILURES = 8;

/**
 * A syntactically valid `scrypt$…` hash that is not, and was never, any real account's password.
 * `login` verifies against this whenever the email does not match a row, so a request against an
 * unknown address pays exactly the same `scrypt` cost as one against a real account with the wrong
 * password — mirroring the existing single-user `AuthManager`'s "always perform the expensive hash
 * verification, even when the email is wrong" (`./auth.ts`), extended to a table of emails instead
 * of one fixed one. Without this, timing alone would tell an attacker which emails are registered.
 */
const DUMMY_HASH_FOR_TIMING =
  'scrypt$16384$8$1$ez5NFoEVxSoQC2V277_psw$K-GfbVja2jyY87JBNCB0szIS5Bk9t5aNLT-p3Bxt3Ds';

export interface UserOut {
  id: string;
  email: string;
  created_at: string;
}

export interface TokenOut {
  token: string;
  expires_at: string;
}

interface UserRow {
  id: string;
  email: string;
  password_hash: string;
  created_at: string;
}

/**
 * Registration, login, logout and identity lookup for the multi-tenant rewrite (M-1a, #45).
 *
 * Deliberately not touched by anything else in this ticket: no route reads `req.userId` to scope a
 * query yet (that is M-1b), and this service does not know that field exists. It only answers "who
 * is this token" — `IdentityGate` (`./identity.middleware.ts`) is what turns that answer into
 * request context.
 */
@Injectable()
export class AuthService {
  private readonly rateLimiter = new LoginRateLimiter({
    maxAttempts: MAX_LOGIN_FAILURES,
    windowMs: LOGIN_WINDOW_MS,
  });

  constructor(@Inject(DIARY_DB) private readonly db: DiaryDatabase) {}

  async register(email: string, password: string): Promise<UserOut> {
    const normalizedEmail = email.trim().toLowerCase();
    const existing = this.db.prepare('SELECT 1 FROM users WHERE email = ?').get(normalizedEmail);
    if (existing) {
      throw new ConflictException('An account with this email already exists.');
    }

    const passwordHash = await hashPassword(password);
    const id = randomUUID();
    const createdAt = encodeDateTime(nowUtc());
    try {
      this.db
        .prepare('INSERT INTO users (id, email, password_hash, created_at) VALUES (?, ?, ?, ?)')
        .run(id, normalizedEmail, passwordHash, createdAt);
    } catch (error) {
      // Backstop for the register-register race the SELECT above cannot close on its own — two
      // requests for the same email can both pass the check before either inserts. The UNIQUE
      // constraint on `users.email` is the real guard; this only turns its raw SQLite error into
      // the same 409 the pre-check gives everyone else.
      if (error instanceof Error && /UNIQUE/.test(error.message)) {
        throw new ConflictException('An account with this email already exists.');
      }
      throw error;
    }

    return { id, email: normalizedEmail, created_at: createdAt };
  }

  async login(email: string, password: string): Promise<TokenOut> {
    const normalizedEmail = email.trim().toLowerCase();
    if (this.rateLimiter.isBlocked(normalizedEmail)) {
      // 429, mirroring the existing single-user `AuthManager` (`./auth.ts`), not 401 — this is
      // "you're being throttled", a different condition from "those credentials are wrong" and one
      // a client can legitimately act on differently (back off and retry, rather than re-prompt).
      throw new HttpException(
        'Too many attempts. Try again in 15 minutes.',
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }

    const user = this.db
      .prepare('SELECT id, email, password_hash, created_at FROM users WHERE email = ?')
      .get(normalizedEmail) as UserRow | undefined;

    // Always spend the scrypt cost, even against a hash that cannot possibly match — see
    // `DUMMY_HASH_FOR_TIMING`'s doc comment.
    const passwordOk = await verifyPassword(password, user?.password_hash ?? DUMMY_HASH_FOR_TIMING);
    if (!user || !passwordOk) {
      this.rateLimiter.recordFailure(normalizedEmail);
      throw new UnauthorizedException('Email or password is incorrect.');
    }

    this.rateLimiter.reset(normalizedEmail);

    const token = generateToken();
    const now = encodeDateTime(nowUtc());
    const expiresAt = encodeDateTime(encodeInstant(Date.now() + TOKEN_TTL_MS));
    // Opportunistic cleanup, same spirit as `AuthManager.pruneFailures` — a login is a convenient,
    // already-paid-for moment to drop sessions nobody will present again, without a scheduled job.
    this.db.prepare('DELETE FROM sessions WHERE expires_at <= ?').run(now);
    this.db
      .prepare(
        'INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, ?, ?)',
      )
      .run(hashToken(token), user.id, now, expiresAt);

    return { token, expires_at: expiresAt };
  }

  /** Revokes a token. Idempotent and silent on a token that is already gone or was never valid —
   * "logged out" is the correct end state either way, and there is nothing a caller can do
   * differently on hearing that a token they no longer hold was already gone. */
  logout(rawToken: string): void {
    this.db.prepare('DELETE FROM sessions WHERE token_hash = ?').run(hashToken(rawToken));
  }

  /** Resolves a bearer token to the user id it authenticates, or `null` if it is missing, unknown,
   * or expired. The one function both `IdentityGate` and `GET /auth/me` build on, so "what makes a
   * token valid" is answered in exactly one place. */
  resolveToken(rawToken: string): string | null {
    const row = this.db
      .prepare('SELECT user_id, expires_at FROM sessions WHERE token_hash = ?')
      .get(hashToken(rawToken)) as { user_id: string; expires_at: string } | undefined;
    if (!row) return null;

    // `expires_at` is `codecs.ts`'s fixed-width, zero-padded `YYYY-MM-DD HH:MM:SS.ffffff` — the
    // same format a plain string comparison already relies on to sort correctly, so comparing two
    // encoded values lexically agrees with comparing the instants they represent.
    if (row.expires_at <= encodeDateTime(nowUtc())) {
      this.db.prepare('DELETE FROM sessions WHERE token_hash = ?').run(hashToken(rawToken));
      return null;
    }
    return row.user_id;
  }

  async me(rawToken: string): Promise<UserOut> {
    const userId = this.resolveToken(rawToken);
    if (!userId)
      throw new UnauthorizedException('The bearer token is missing, unknown or expired.');
    const user = this.db
      .prepare('SELECT id, email, created_at FROM users WHERE id = ?')
      .get(userId) as UserOut | undefined;
    // The session outlived its user only if something else deleted the user row directly — there
    // is no such route yet, but `sessions.user_id` cascades on delete (`schema.ts`) for the day
    // there is one, so this stays consistent rather than serving a session for nobody.
    if (!user) throw new UnauthorizedException('The bearer token is missing, unknown or expired.');
    return user;
  }
}

/** A future or past instant, expressed the way `codecs.ts` wants it. Millisecond precision is
 * plenty for a session expiry — nothing here needs the microsecond precision diary timestamps
 * carry, so this does not round-trip through `nowUtc()`'s sub-millisecond clock at all. */
function encodeInstant(epochMs: number): NaiveDateTime {
  const date = new Date(epochMs);
  return {
    year: date.getUTCFullYear(),
    month: date.getUTCMonth() + 1,
    day: date.getUTCDate(),
    hour: date.getUTCHours(),
    minute: date.getUTCMinutes(),
    second: date.getUTCSeconds(),
    microsecond: date.getUTCMilliseconds() * 1000,
  };
}
