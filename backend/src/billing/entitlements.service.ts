import { Inject, Injectable, NotFoundException } from '@nestjs/common';
import type { DiaryDatabase } from '../db/database';
import { DIARY_DB } from '../db/database.provider';
import { encodeDateTime, nowUtc } from '../db/codecs';

/** Every value `entitlements.tier` is allowed to hold (`schema.ts`). */
export type Tier = 'free' | 'premium';

/** Every value `entitlements.source` is allowed to hold (`schema.ts`) — which system asserted this
 * entitlement, kept for audit even though nothing branches on it today: `'play'` for anything a
 * `PlayPurchaseVerifier` (`./play-verifier.ts`) — real or fake — actually confirmed, `'manual'` for
 * a grant made through the dev-only admin escape hatch (`./entitlements.controller.ts`) or through
 * `MANUAL_ENTITLEMENTS=true`'s bypass of Google entirely. */
export type EntitlementSource = 'play' | 'manual';

/** What `GET /auth/me` and `POST /billing/play/verify` both hand back — the shape a client renders
 * state from. `expires_at` is this row's own column, encoded the same way every other datetime in
 * this API is (`db/codecs.ts`'s `YYYY-MM-DD HH:MM:SS.ffffff`); `null` means lifetime. */
export interface EntitlementOut {
  tier: Tier;
  expires_at: string | null;
}

interface EntitlementRow {
  user_id: string;
  tier: Tier;
  source: EntitlementSource;
  expires_at: string | null;
  updated_at: string;
}

const FREE: EntitlementOut = { tier: 'free', expires_at: null };

/**
 * Server-side entitlement state (M-2, #47).
 *
 * Deliberately the only place that decides "is this user premium right now" — `requiresPremium`
 * (`./requires-premium.guard.ts`), `GET /auth/me` (`../auth/identity.controller.ts`) and the daily
 * sweep (`./entitlements-sweep.ts`) all read through `getEntitlement`, so an expiry rule written
 * once cannot drift between a guard that blocks a request and a response that renders a badge.
 *
 * **Absence means free.** There is no row-per-user invariant to maintain: a user who has never
 * verified a purchase (every account today, including the M-1a default user) simply has no row,
 * and `getEntitlement` treats that identically to an explicit `tier = 'free'` row. See `schema.ts`'s
 * comment on the `entitlements` table for why this, not a seeded free row, is what "everyone
 * defaults to free" (the issue's task 1) means in practice.
 *
 * **Expiry is checked twice, on purpose.** `getEntitlement` computes the *true* answer live —
 * `expires_at <= now` reads as free even if the stored `tier` column still says `'premium'` —
 * so a client is never told a lapsed subscription is still active during the window between two
 * sweeps. The sweep (`sweepExpired`) then normalises the stored row itself, which matters for
 * anything that might query `entitlements.tier` directly with raw SQL instead of going through this
 * service (an admin report, a future analytics query) and for keeping `updated_at` honest. Neither
 * check alone would be enough: the live check without a sweep would leave stale `'premium'` rows on
 * disk forever; a sweep without the live check would let a lapsed subscriber stay premium for up to
 * one sweep interval.
 */
@Injectable()
export class EntitlementsService {
  constructor(@Inject(DIARY_DB) private readonly db: DiaryDatabase) {}

  /**
   * The effective entitlement for a user, right now.
   *
   * `now` defaults to the real clock and is only ever overridden by this service's own unit tests
   * (`tests/unit/entitlements-service.test.ts`) — the encoded-string comparison is the same trick
   * `AuthService.resolveToken` uses (`../auth/identity.service.ts`): `codecs.ts`'s fixed-width
   * `YYYY-MM-DD HH:MM:SS.ffffff` sorts lexically exactly the way the instants it represents do, so
   * there is no need to parse either side back into a `Date` just to compare them.
   */
  getEntitlement(userId: string, now: string = encodeDateTime(nowUtc())): EntitlementOut {
    const row = this.db
      .prepare(
        'SELECT user_id, tier, source, expires_at, updated_at FROM entitlements WHERE user_id = ?',
      )
      .get(userId) as EntitlementRow | undefined;
    if (!row) return FREE;
    if (row.tier === 'premium' && row.expires_at !== null && row.expires_at <= now) return FREE;
    return { tier: row.tier, expires_at: row.expires_at };
  }

  /**
   * Records a verified or manually-granted entitlement, replacing whatever this user held before.
   *
   * One row per user by construction — `entitlements.user_id` is the primary key (`schema.ts`), so
   * this is a plain upsert rather than an insert-then-update pair, and there is no read-modify-write
   * race for two concurrent grants to interleave badly on: whichever `INSERT` commits last simply
   * wins, which is the correct outcome for "the current state of this user's purchase".
   *
   * Throws if `userId` names no row in `users`. `POST /billing/play/verify`'s caller can never
   * trigger this — its `userId` always comes from `IdentityGate` (`../auth/identity.middleware.ts`),
   * which only ever attaches a real user id — but `POST /billing/admin/grant`'s caller supplies an
   * arbitrary `user_id`, and `entitlements.user_id` has no enforced foreign key at the SQLite level
   * (`database.ts` runs with `foreign_keys = OFF`, the same posture every other table in this diary
   * has). Without this check, a typo'd admin grant would write a row `assertCompatible`
   * (`../db/compatibility.ts`) rejects on the next boot — turning a bad API call into a backend
   * that refuses to start (FR-018) is exactly the failure mode this guards against.
   */
  grant(
    userId: string,
    tier: Tier,
    source: EntitlementSource,
    expiresAt: string | null,
  ): EntitlementOut {
    const userExists = this.db.prepare('SELECT 1 FROM users WHERE id = ?').get(userId);
    if (!userExists) throw new NotFoundException(`No user with id "${userId}".`);

    const now = encodeDateTime(nowUtc());
    this.db
      .prepare(
        `INSERT INTO entitlements (user_id, tier, source, expires_at, updated_at)
         VALUES (?, ?, ?, ?, ?)
         ON CONFLICT(user_id) DO UPDATE SET
           tier = excluded.tier,
           source = excluded.source,
           expires_at = excluded.expires_at,
           updated_at = excluded.updated_at`,
      )
      .run(userId, tier, source, expiresAt, now);
    return { tier, expires_at: expiresAt };
  }

  /**
   * Drops every expired premium entitlement to free. Returns the number of rows changed, purely so
   * a caller (the CLI sweep script, a test) can report or assert on it.
   *
   * `now` is injectable for the same reason `getEntitlement`'s is: `tests/unit/entitlements-sweep.
   * test.ts` asserts "a subscription 1ms past its expiry is swept, one 1ms before it is not" by
   * passing two fixed strings, never by sleeping across a real expiry boundary.
   *
   * `expires_at` is cleared to NULL on the rows this touches rather than left holding a stale past
   * timestamp — once a row reads `tier = 'free'`, `expires_at` has no meaning (`getEntitlement`
   * never looks at it for a free row), and clearing it keeps a swept row indistinguishable from one
   * that was always free, which is the correct history: a lapsed free-tier user is not "premium
   * that expired," they are simply free again.
   */
  sweepExpired(now: string = encodeDateTime(nowUtc())): number {
    const result = this.db
      .prepare(
        `UPDATE entitlements SET tier = 'free', expires_at = NULL, updated_at = ?
         WHERE tier = 'premium' AND expires_at IS NOT NULL AND expires_at <= ?`,
      )
      .run(now, now);
    return result.changes;
  }
}
