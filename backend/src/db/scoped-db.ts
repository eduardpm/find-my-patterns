import type { DiaryDatabase } from './database';

/**
 * The enforcement mechanism for M-1b step 2 (#46).
 *
 * The problem this exists to solve: #134 gave every user-data table a `user_id` column, but
 * `NOT NULL DEFAULT '<DEFAULT_USER_ID>'` (required so `ALTER TABLE ... ADD COLUMN` could backfill
 * existing rows — see `schema.ts`'s M-1b note). That default is not merely harmless, it is a trap:
 * an `INSERT` that forgets `user_id` does not fail, it silently assigns the row to the default
 * user. A `SELECT`/`UPDATE`/`DELETE` that forgets `WHERE user_id = ?` does not fail either — it
 * just touches every user's rows. Nothing at the SQLite layer objects to either mistake, so the
 * only thing standing between a forgotten parameter and a mis-owned or leaked row is this file.
 *
 * Two independent layers, deliberately not one:
 *
 *  1. **A type-level gate.** `DIARY_DB` (`database.provider.ts`) still injects the raw
 *     `DiaryDatabase` — `.prepare()` with no owner in sight — but only reference-vocabulary code
 *     (`feelings`, `feeling_groups`, `guiding_questions` — shared, not user data) and genuinely
 *     admin-level code (`seed.ts`, `migrate.ts`, `compatibility.ts`, `default-user.ts`,
 *     `build-golden-db.ts`, identity/entitlements services that already take an explicit `userId`
 *     parameter from #45/#47) are wired to it directly. Every repository or service that touches a
 *     per-user table is instead wired to `SCOPED_DB`, whose only method is `forUser(userId)` — there
 *     is no way to obtain a `Statement` from a `ScopedDb` without first presenting a user id. A
 *     service that forgets to thread `userId` through from its controller does not compile; this is
 *     the "compile-time requirement, not a convention" the issue's acceptance criterion 4 asks for,
 *     for the class of bug that is "forgot to think about ownership at all."
 *
 *  2. **A runtime text guard**, inside the handle `forUser` returns. It does not, and cannot, prove
 *     a query's `WHERE` clause is correct — verifying that is exactly what the isolation e2e suite
 *     (`tests/e2e/user-isolation.test.ts`) is for. What it catches is narrower and cheaper: any SQL
 *     statement whose text names one of `USER_DATA_TABLES` but never mentions `user_id` at all,
 *     which is precisely the shape of the footgun above — an `INSERT` whose column list forgot the
 *     owner, or a `SELECT`/`UPDATE`/`DELETE` whose `WHERE` forgot the filter. Because #134
 *     deliberately denormalised `user_id` onto every per-user table, including the five
 *     junction/child tables that are only transitively owned through a parent row (`schema.ts`'s
 *     top-of-file note), there is never a legitimate reason for a query against one of these tables
 *     to omit the column outright — a join back to the parent is not an excuse, since the child row
 *     itself always carries the same column. This is a blunt substring check, not a parser — it
 *     cannot tell a real `WHERE user_id = ?` from a red herring like a column named `user_id_hint`
 *     in a comment — but a blunt check that runs on every query is worth more than a precise one
 *     that only runs in review.
 *
 * What this does **not** guarantee, stated plainly rather than implied: that the bound parameter at
 * that `?` is the *right* user id, that a `JOIN` back to a parent table is itself correctly scoped,
 * or that a computed aggregate (a `COUNT`, a `SUM`) only summed one user's rows rather than several.
 * Those are correctness properties of the SQL text, not its presence, and they remain convention —
 * verified by review and by the isolation suite's cross-user assertions, not by this file.
 */

/**
 * Every table #134 added `user_id` to, in the classification `schema.ts`'s top-of-file comment
 * lays out: user-owned content plus the five denormalised junction/child tables. Deliberately
 * excludes `feelings`, `feeling_groups`, `guiding_questions` (shared reference vocabulary — no
 * `user_id` column exists to check for) and `users`/`sessions`/`entitlements` (already scoped by
 * #45/#47, whose services take `userId` as an explicit, conventional parameter rather than through
 * this wrapper — `alembic_version` is inert and out of `REQUIRED` entirely).
 */
export const USER_DATA_TABLES = [
  'topics',
  'diary_entries',
  'entry_feelings',
  'guiding_question_answers',
  'entry_topics',
  'patterns',
  'pattern_entries',
  'pattern_withdrawals',
  'experiments',
  'inference_jobs',
  'entry_topic_feelings',
  'csv_imports',
  'diary_meta',
] as const;

const TABLE_PATTERNS = USER_DATA_TABLES.map((table) => new RegExp(`\\b${table}\\b`, 'i'));

const USER_ID_PATTERN = /user_id/i;

/**
 * Thrown by the handle `ScopedDb.forUser` returns when a query's SQL text names one of
 * `USER_DATA_TABLES` but never mentions `user_id` — see this file's top-of-file doc comment for
 * exactly what that does and does not prove. Deliberately thrown rather than logged: a query this
 * shape is exactly the ownership footgun #46 exists to close, and failing the request loudly in
 * every environment (test, dev, prod) is what makes it impossible to ship unnoticed, the same
 * posture `DdlAttemptedError` (`./database.ts`) already takes for the DDL rule.
 */
export class UnscopedQueryError extends Error {
  constructor(sql: string, table: string) {
    super(
      `Refused an unscoped query against "${table}", a per-user table (M-1b, #46): its SQL text ` +
        `never mentions "user_id". Every read or write against a per-user table must filter or set ` +
        `it — see ScopedDb's doc comment in src/db/scoped-db.ts. SQL: ${sql}`,
    );
  }
}

/** Returns the first `USER_DATA_TABLES` entry `sql` names, or `null` if it names none. */
function tableTouchedBy(sql: string): string | null {
  for (let i = 0; i < USER_DATA_TABLES.length; i++) {
    if (TABLE_PATTERNS[i].test(sql)) return USER_DATA_TABLES[i];
  }
  return null;
}

function assertScoped(sql: string): void {
  const table = tableTouchedBy(sql);
  if (table && !USER_ID_PATTERN.test(sql)) throw new UnscopedQueryError(sql, table);
}

/**
 * Injected in place of `DIARY_DB` by every repository and service that reads or writes a per-user
 * table. `forUser` is the only way in: there is no method here that hands back a `Statement`
 * without a `userId` in hand, which is what makes "forgot to scope this call" a compile error for
 * any caller that has no `userId` in scope at all, rather than a habit to remember.
 */
export interface ScopedDb {
  /**
   * A `DiaryDatabase` handle bound to `userId` for the query guard's purposes. It is still the same
   * underlying connection — `userId` is not silently injected as a bind parameter into every
   * statement, since this project's queries do not go through a query builder that could do that
   * safely — so a caller must still write `WHERE user_id = ?` (or `user_id` in an `INSERT`'s column
   * list) itself and pass `userId` as the matching bound parameter. What this method guarantees is
   * narrower and unconditional: every statement `.prepare()`d off the handle it returns is checked
   * against `USER_DATA_TABLES` before it ever reaches SQLite.
   */
  forUser(userId: string): DiaryDatabase;
}

export const SCOPED_DB = Symbol('SCOPED_DB');

/** Builds the `ScopedDb` wrapper around an already-open `DiaryDatabase` (`database.provider.ts` is
 * the sole caller in production; tests that need one directly construct it the same way). */
export function createScopedDb(raw: DiaryDatabase): ScopedDb {
  return {
    forUser(userId: string): DiaryDatabase {
      if (!userId) {
        throw new Error('ScopedDb.forUser requires a non-empty userId (M-1b, #46).');
      }
      return {
        prepare<T = unknown>(sql: string) {
          assertScoped(sql);
          return raw.prepare<T>(sql);
        },
        transaction<T>(fn: () => T): T {
          return raw.transaction(fn);
        },
        close(): void {
          raw.close();
        },
        readonlyPragma(sql: string): unknown[] {
          return raw.readonlyPragma(sql);
        },
      };
    },
  };
}
