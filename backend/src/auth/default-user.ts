import { encodeDateTime, nowUtc } from '../db/codecs';

/**
 * The multi-tenant migration's fixed "user zero" (M-1a, #45).
 *
 * A `VARCHAR(36)` UUID, not the small integer the issue that introduced this file describes ("a
 * default user (id 1)") — every other id in `src/db/schema.ts` is a UUID, and #46 adds a
 * `user_id VARCHAR(36)` foreign key to nearly every table in this diary. Making this one table an
 * integer would force every join #46 writes to special-case a single column's type for no benefit:
 * nothing about "the user every pre-existing row belongs to" requires a small integer, and a UUID
 * keeps the schema uniform. Fixed rather than randomly generated at seed time because both this
 * ticket and #46 need to name "the pre-multi-tenant single user" as a literal, stable constant —
 * a random id would make that impossible to write down in code or in a migration.
 */
export const DEFAULT_USER_ID = '00000000-0000-0000-0000-000000000001';

/**
 * A placeholder mailbox, not a real one. Every diary this backend already manages predates
 * accounts entirely — there is no email address to migrate, only a `NOT NULL UNIQUE` column that
 * needs something to hold. `.invalid` is the domain suffix RFC 2606 reserves exactly for this: a
 * value guaranteed to never be a real, resolvable mailbox — and, usefully, one that still passes
 * ordinary email-shape validation (`owner@localhost` does not: it has no dot in the domain part),
 * so this row behaves like any other `users` row everywhere shape is checked.
 */
export const DEFAULT_USER_EMAIL = 'owner@default-user.invalid';

/**
 * A `password_hash` value `verifyPassword` (`./password.ts`) can never accept: it does not start
 * with `scrypt$`, so the format check fails before any key is ever derived, for any input
 * password. The default user must exist as a real row the moment a diary gains this table — #46's
 * `user_id` foreign keys need somewhere to point, immediately, on a diary nobody has touched since
 * migrating — but it must not be a login a stranger can brute-force, since no one has set a real
 * password for it. Claiming this account for real is a password-reset flow, explicitly out of
 * scope for this ticket (see the issue's "Out of scope" section).
 */
const DEFAULT_USER_PASSWORD_MARKER = 'disabled:no-password-set';

/** Minimal shape both the guarded `DiaryDatabase` and a raw `better-sqlite3.Database` satisfy. */
interface UserTableAccess {
  prepare(sql: string): {
    get(...params: unknown[]): unknown;
    run(...params: unknown[]): { changes: number };
  };
}

/**
 * Ensures the default user row exists, without touching it if it already does.
 *
 * Called from two places that each need it idempotent for a different reason: `seed()`
 * (`../db/seed.ts`) runs on every server boot against a diary that may already carry this row
 * (FR-022 — never rewrite what is already there); `migrateDiary()` (`../db/migrate.ts`) runs
 * against a diary that had no `users` table at all until the migration created it moments earlier
 * in the same transaction, and the ticket's acceptance criteria require the row to exist
 * immediately after migration, independent of whether the server has booted since.
 */
export function ensureDefaultUser(db: UserTableAccess): void {
  const exists = db.prepare('SELECT 1 FROM users WHERE id = ?').get(DEFAULT_USER_ID);
  if (exists) return;
  db.prepare('INSERT INTO users (id, email, password_hash, created_at) VALUES (?, ?, ?, ?)').run(
    DEFAULT_USER_ID,
    DEFAULT_USER_EMAIL,
    DEFAULT_USER_PASSWORD_MARKER,
    encodeDateTime(nowUtc()),
  );
}
