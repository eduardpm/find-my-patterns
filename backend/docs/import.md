# Daylio CSV import (L-1b, #35)

A switcher from Daylio arrives with years of mood history — exactly what a threshold-based pattern
engine needs. This is a one-time, user-initiated import of a Daylio CSV export into the diary.
Backend only: there is no upload UI yet, only the two endpoints below (a review UI can follow once
this works end to end).

This is the round-trip partner to `GET /export` (`export.md`) — an entry this importer writes reads
back through the same `GET /entries` / `GET /export` paths every other entry does.

## Where the column layout comes from

The Daylio CSV column layout was **unverified** going into this ticket
(`specs/research/daylio-competitive-analysis.md` §10). It is verified now, against a real export
file and Daylio's own documented default mood names, retrieved 2026-08-29:

- https://github.com/MichaelCurrin/daylio-csv-parser/blob/master/docs/csv-format.md — the column
  layout itself: `full_date,date,weekday,time,mood,activities,note_title,note`, activities
  pipe-separated.
- https://github.com/MichaelCurrin/daylio-csv-parser/blob/master/dayliopy/sample.csv — a real
  export file. `tests/fixtures/daylio-sample.csv` adapts its format and quoting conventions.
- https://daylio-parser.readthedocs.io/en/latest/config.html — Daylio's five default mood names
  (`rad, good, meh, bad, awful`), corroborated by independent write-ups of the same five names.

**What is still not verifiable from outside Daylio**: the CSV carries no column naming which of the
five mood _groups_ a renamed or custom mood belongs to — see `src/import/daylio-mood-map.ts`'s doc
comment for what that means for mapping.

## Conservative mapping (constitution-level, not a preference)

1. **Moods → feelings.** `src/import/daylio-mood-map.ts`'s `DAYLIO_MOOD_MAP` covers exactly
   Daylio's five default mood names:

   | Daylio mood | Feeling key | Group (valence)        |
   | ----------- | ----------- | ---------------------- |
   | `rad`       | `happy`     | Uplifted (positive)    |
   | `good`      | `content`   | Steady (positive, #60) |
   | `meh`       | `neutral`   | Steady (neutral)       |
   | `bad`       | `sad`       | Low (negative)         |
   | `awful`     | `depressed` | Low (negative)         |

   Chosen against the vocabulary's _current_ valences (`src/db/feeling-vocabulary.ts`, post-#60:
   `calm`, `content`, `relaxed`, `focused`, `curious` are positive, not neutral). `awful → depressed`
   is the one genuine judgment call — the issue's own suggestion (`awful → miserable`) names a
   feeling that does not exist in this vocabulary.

   A mood that is not one of these five exact names — a rename, or a custom mood in any of the five
   groups — is **skipped and reported, never guessed**. The CSV has no honest way to say which group
   a custom mood belongs to, so guessing would be exactly the unaudited judgment the product's
   architecture excludes.

2. **Imported feelings are `overridden`, never `confirmed`.** A Daylio mood rating is a person's own
   words, not a model's guess, but the user did not confirm it _in this diary_ — `overridden` is
   the strongest provenance marker the vocabulary has for that distinction
   (`improvement-opportunities.md` §8: "nothing silently treated as evidence the user didn't see").

   **Consequence, stated explicitly**: `CONFIRMED_FEELING_SOURCES` (`src/insights/constants.ts`) is
   `['confirmed', 'overridden']`, so imported entries **do** count as pattern evidence the moment
   they are committed. That is this ticket's intended behaviour — the whole point of import is a
   pattern engine that starts warm — not an oversight.

3. **Activities → topics**, canonicalised through the same table every other topic goes through
   (`src/topics/canonicalization.ts`). Linked with provenance `'import'`
   (`TopicsService.linkTopics`) rather than `'keyword'`: `PatternsService` deletes and re-derives
   every `'keyword'` link from `raw_text` on each recompute, and an imported activity tag is
   usually not a word the note itself contains. `'import'` (like `'llm'`) is left alone by that
   sweep.

4. **`note_title` + `note` → `raw_text`, mode `freeform`.** `note_title` is not in the issue's
   literal field list, but dropping a title the user actually typed would be silent data loss —
   the one thing this feature exists to avoid. When both are present they are composed as
   `{note_title}\n\n{note}`; either alone is used as-is.

5. **`entry_date` / `created_at` come from the CSV**, not from the moment the import runs
   (`full_date` + `time`; a 12-hour clock — `12:00 am` is midnight, `12:00 pm` is noon).

## Provenance marker

`diary_entries.origin` (`'app' | 'daylio_import'`) is a schema addition — every entry the normal
compose flow ever wrote defaults to `'app'`; the importer writes `'daylio_import'`. Served on every
entry read (`GET /entries`, `origin` field) — the visible provenance the ticket requires. Distinct
from `feeling_source`, which describes how the _feeling_ was decided, not where the _entry_ itself
came from.

## Two-phase API

### `POST /import/daylio/dry-run`

Multipart, field `file` (the CSV, up to 10MB). Parses and reports; **never writes**.

```json
{
  "content_hash": "…sha256 hex, 64 chars…",
  "report_hash": "…sha256 hex, 64 chars…",
  "total_rows": 17,
  "parseable_count": 17,
  "importable_count": 16,
  "unparseable_rows": [{ "row": 4, "reason": "Unrecognised time \"25:00\"." }],
  "mood_mapping": [{ "daylio_mood": "rad", "feeling_key": "happy" }, "…"],
  "unmapped_moods": [{ "mood": "fantastic", "count": 1, "sample_rows": [13] }],
  "date_range": { "start": "2026-07-01", "end": "2026-07-16" },
  "collisions": [
    {
      "row": 1,
      "entry_date": "2026-07-01",
      "reason": "An entry with this date and text already exists in the diary."
    }
  ],
  "already_imported": false,
  "previous_import": null
}
```

`report_hash` is hashed over everything above **except** `collisions`, `already_imported` and
`previous_import` — those depend on what is already in the diary when the request runs, and
committing changes exactly that. Hashing them in would make a file's own hash change the moment it
was imported, breaking the idempotency check `commit` performs against a repeated call. A collision
is informational only — it does not remove a row from `importable_count` (see `commit` below).

A 422 here means the file itself could not be read as a Daylio export at all (missing/wrong
columns, empty upload) — a bad _value_ in an otherwise well-formed row (an unparseable date) is
reported per row in `unparseable_rows` instead, and does not fail the request.

### `POST /import/daylio/commit`

Multipart, field `file` (the same CSV) plus a `report_hash` field — the value a `dry-run` of this
exact file returned. Writes through `EntriesService`/`TopicsService`, same as every other entry
point that creates diary content; no DDL, no direct-SQL bypass of validation.

```json
{
  "idempotent": false,
  "imported_count": 16,
  "skipped_unmapped_count": 1,
  "entry_ids": ["…"],
  "content_hash": "…",
  "previous_import": null
}
```

Two guards, in order:

1. **`report_hash` must match a fresh dry-run of this exact file.** `commit` never trusts a report
   the client remembers — it recomputes one from the posted file and refuses to write if the two
   disagree (a 422). This is what keeps "the file the report described" true even if the mood
   mapping or vocabulary changed between the two calls.
2. **`content_hash` must not already be in `csv_imports`.** A file already committed writes
   nothing and answers `idempotent: true` with the original `previous_import`
   (`imported_at`, `entry_count`) — re-posting the exact same export can never double-import. The
   whole write (every entry, every topic link, the `csv_imports` row) is one transaction, so a
   failure partway through cannot leave the file half-imported and unmarked.

A row whose mood did not map is skipped (`skipped_unmapped_count`) and never written. A row that
collided with an existing entry is **still written** — the collision is something a person reviewing
the dry-run report can see and decide about; silently dropping it on their behalf would be a worse
surprise than an occasional duplicate they can see and delete.

## Out of scope (per the issue)

Bearable CSV (a follow-up), a mobile/web upload UI, and backfilling suggested topic↔feeling
pairings for imported entries.
