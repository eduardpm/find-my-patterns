# Regenerating the golden test fixture (#83)

`tests/fixtures/golden.db` is a small diary used as test input for most of the backend suite and
for the Playwright `browser` CI job. It is **not committed** — a binary SQLite file is something
git can only merge by picking one side wholesale, and two branches that each added a migration
touching it collided this way three times in one day. It is built instead, from two plain-text
sources, every time it is needed:

1. **Schema and reference vocabulary** — `feeling_groups`, `feelings`, `guiding_questions` — come
   from `initDiary` (`src/db/init.ts`), the same function `npm run init-db` uses. This is what
   makes the fixture track future vocabulary migrations automatically instead of going stale.
2. **The fixture's own content** — its 8 diary entries, 2 topics, 2 materialised patterns and
   everything that hangs off them — lives in [`tests/fixtures/golden-seed.json`](../tests/fixtures/golden-seed.json),
   a plain JSON snapshot of exactly what the old binary fixture contained, including every id and
   timestamp verbatim. Two branches that each add a row to it now produce an ordinary JSON merge
   conflict — visible, resolvable — instead of a binary one git resolves by silently picking a
   side.

`src/db/build-golden-db.ts` assembles the two. Read its doc comment for the two things it does that
`initDiary` alone cannot: three of the seven `guiding_questions` need pre-#14 wording (the fixture
predates that copy change, and `seed()`/`migrate.ts` never rewrite an existing question's text), and
the inert `alembic_version` table needs to exist because real diaries may carry one.

## When you don't need to do anything

`npm test` builds the fixture itself, once, before the suite runs — a Vitest
[`globalSetup`](../tests/global-setup.ts) calls `buildGoldenDb` directly against the TypeScript
source. Nothing to run first; `cd backend && npm test` on a clean checkout is enough.

## Regenerating it by hand

```sh
cd backend
npm run build           # compiles src/ to dist/
npm run build-golden-db # writes tests/fixtures/golden.db
```

`build-golden-db` takes an optional path argument (`node dist/db/build-golden-db.js <path>`) and
defaults to `tests/fixtures/golden.db`. Running it is safe at any time: it deletes and rebuilds the
target file from scratch, and rebuilding without touching `golden-seed.json` is a no-op — the same
schema and the same seed data produce the same rows every time.

## Changing what the fixture contains

The issue that introduced this generator (#83) deliberately left the fixture's _content_ out of
scope — the goal was to stop committing a binary, not to change what any test reads. If a later
change does need to add or edit a row (a new case worth covering, a schema change that needs a
fixture row to exercise it):

1. Edit `tests/fixtures/golden-seed.json` directly. It is grouped by table (`topics`,
   `diaryEntries`, `entryFeelings`, `entryTopics`, `guidingQuestionAnswers`, `patterns`,
   `patternEntries`), each row using the same fields the corresponding table has, camelCased.
   `guidingQuestionOverrides` is the exception — it does not name a table, it holds the pre-#14
   prompt text for the three questions `build-golden-db.ts`'s doc comment explains.
2. Pick a fresh id (any UUID) for anything new. **Do not reuse or renumber an existing id** —
   several tests key off specific ids directly (`tests/e2e/pairing-insights-snapshot.test.ts`'s
   `PATTERNED_ENTRY_ID`/`PATTERNED_TOPIC_ID`, most concretely), so an id that looks unused today
   may not be.
3. Keep `entry_date`/`entryDate` inside July 2026. `tests/contract/read-endpoints.test.ts` queries
   `GET /monthly-summary?month=2026-07` and expects the fixture's entries to show up there.
4. Run `npm test` — it rebuilds the fixture from your edit automatically — and check the row counts
   in `tests/fixtures/README.md` still describe the file, updating the table there if they no
   longer do.

Adding a table that needs schema (a new column, a new table) still goes through the normal path:
add it to `SCHEMA_STATEMENTS`/`MIGRATION_STATEMENTS` in `src/db/schema.ts` first, the way any other
migration does. `build-golden-db.ts` only ever adds _rows_, never DDL of its own, apart from the one
sanctioned exception documented next to `ALEMBIC_VERSION_STATEMENT` in `schema.ts`.
