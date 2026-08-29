# Golden fixture

`golden.db` is a small diary used as test input. Tests copy it to a temp directory and work on the
copy, so it is never modified.

It deliberately contains one of everything that behaves differently:

| Case | Exercises |
|---|---|
| 3 × "coca cola … sleepy", confirmed | Enough to cross the 3-occurrence pattern threshold |
| An entry whose feeling was overridden | `feeling_source = overridden` |
| An entry left at `suggested` | The never-confirmed state |
| An entry with empty text | `feeling_source = unset`, `feeling_key = NULL` |
| A guided entry with two answers | `raw_text` composition, `question_text_snapshot`, `order_index` |
| A guided entry citing an **unknown** question key | The snapshot's fallback to the raw key |
| Materialised patterns | Real `patterns` and `pattern_entries` rows |

Contents: 8 entries, 3 guided answers, 6 topic links, 2 patterns, 2 topics.

It also carries an inert `alembic_version` table left by an earlier migration tool — kept on purpose,
because real diaries have one and the backend must ignore it.

## Regenerating

`golden.db` is not committed (#83) — a binary SQLite file is something git can only merge by
picking one side wholesale, which silently dropped a schema change more than once when two
branches each migrated it the same day. It is generated instead, on every `npm test` (a Vitest
[`globalSetup`](../global-setup.ts) builds it once before the suite runs) and by the `browser` CI
job, from two plain-text, git-mergeable ingredients:

- **Schema and reference vocabulary** (`feeling_groups`, `feelings`, `guiding_questions`) come from
  `initDiary` — the same code path `npm run init-db` uses — so the fixture tracks future vocabulary
  migrations automatically.
- **This fixture's own content** — the rows in the table above — lives in
  [`golden-seed.json`](golden-seed.json), including every id and timestamp verbatim. Nothing here
  regenerates fresh on each build, so the file is byte-stable across rebuilds: `entry_date`
  ('2026-07-28') and specific ids (`tests/e2e/pairing-insights-snapshot.test.ts`) are relied on
  by name elsewhere in the suite. The codec tests still use their own hardcoded values,
  independent of this file.

Both are assembled by [`../../src/db/build-golden-db.ts`](../../src/db/build-golden-db.ts) — see
its doc comment for the two things it has to do that `initDiary` alone cannot (the pre-#14 guiding
question wording, and the inert `alembic_version` table). See `backend/docs/golden-fixture.md` for
how to change the fixture's contents and regenerate it by hand.

## `insight-scenarios.json`

A corpus of 22 diary situations, each written to probe one way the Insights view could mislead
someone. Driven by `../e2e/insight-scenarios.test.ts`.

Every scenario carries the entries to write, the feelings the user settled on, and an `expect`
block describing **what the app should do** — never what it currently does. A `verdict` records
which of those two it is:

- `holds` (5) — the app already meets the expectation, and the test guards it.
- `defect` (17) — it does not. The test runs as a *failing* expectation, so the suite stays green
  while the problem exists and turns **red the moment it is fixed**, which forces this file to be
  updated in the same change rather than leaving a stale known-issues list behind.

A second block of tests re-runs every defect and checks it fails by *failing its expectation*
rather than by throwing — otherwise a misspelled topic in this file would masquerade as a known
defect and nobody would notice.

Scenarios are grouped by what they probe: statistical validity (base rate, confounding, reverse
causation, multiple comparisons, recency), text handling (negation, intention, attribution to
another person, word boundaries, non-English), safety and tone (medication, menstrual cycle,
illness, a partner, a reader in crisis, a neutral feeling), and presentation (ranking,
contradiction). Each names its `source`: the repo's own research under `specs/research`, the
n-of-1 self-tracking literature, or reasoning about a specific function.

Adding a scenario needs no code — add an object to `scenarios` and run the suite.

## `daylio-sample.csv`

A Daylio CSV export, exercising the Daylio importer (L-1b, #35). The column layout and quoting
conventions are adapted from a real export file, not invented — see
`../../src/import/daylio-mood-map.ts`'s doc comment for the sources (retrieved 2026-08-29):
`MichaelCurrin/daylio-csv-parser`'s `docs/csv-format.md` and its `dayliopy/sample.csv`, and
`daylio-parser`'s `config.html` for the five default mood names.

17 rows, deliberately containing:

| Case | Exercises |
|---|---|
| `rad`, `good`, `meh`, `bad`, `awful` | Every entry in `DAYLIO_MOOD_MAP` |
| `fantastic` (row 13) | A custom/renamed mood — skipped and reported, never guessed |
| `12:00 am` (row 6) | Midnight — the one point a 12-hour clock does not add 12 for "pm" |
| `12:00 pm` (row 9) | Noon, the same clock's other edge |
| Empty `activities`/`note_title`/`note` (row 10) | A logged mood with nothing else attached |
| A note with embedded commas (row 11) | Quoted-field CSV parsing |
| A `note_title` (rows 4, 7) | `note_title` + `note` composed into `raw_text` |
| "work" on 6 of 17 days, "bad"→`sad` on 5 of those 6 | A real lift once imported — `work`↔`sad`
  crosses `MIN_OCCURRENCE_THRESHOLD` (5 ≥ 3) with `present_rate` 5/6 against `absent_rate` 1/11,
  which the import e2e test uses to assert patterns actually compute over imported entries |
