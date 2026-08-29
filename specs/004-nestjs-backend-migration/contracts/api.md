# API Contract: Fidelity Specification

> **⚠️ Superseded in part (2026-07-29).** The Python backend was deleted, the differential test
> strategy was dropped, and the deliberately-ported topic-matching defect was fixed — because the
> **spec**, not the previous implementation, is the source of truth. The new backend now lives at
> `backend/`. Read the **Outcome** section at the top of [spec.md](./spec.md) before relying on
> anything here.

**This document adds nothing.** The contract is frozen (FR-005): the union of
[002's api.md](../../002-mood-pattern-diary-mobile/contracts/api.md) and
[003's delta](../../003-web-client/contracts/api.md) remains authoritative for *what* each endpoint
does. What follows pins down the details a re-implementation gets wrong — the ones that are invisible
in a schema and silent when broken.

**The consumer that makes this strict**: an Android app already installed on a phone. It cannot be
patched in step with the backend, so anything it parses is effectively immutable.

## Endpoint inventory (complete — nothing may be added or removed)

| Method | Path | Success | Notes |
|---|---|---|---|
| GET | `/feelings` | 200 | the vocabulary twice over: `groups` (nested) and `feelings` (flat), both in `sort_order` |
| GET | `/guiding-questions` | 200 | full library including `trigger_keywords` |
| POST | `/entries` | **201** | returns `suggested_feeling`, `version: 1` |
| GET | `/entries?date=YYYY-MM-DD` | 200 | ordered by `created_at` |
| GET | `/entries/{id}` | 200 / 404 | |
| PATCH | `/entries/{id}` | 200 / 404 / **409** / **422** | `version` required in body; `feeling_keys` (or legacy `feeling_key`) sets the whole set |
| DELETE | `/entries/{id}?version=N` | **204** / 404 / **409** / **422** | `version` required as query param |
| GET | `/insights` | 200 | recomputes patterns before reading |
| GET | `/monthly-summary?month=YYYY-MM` | 200 | |
| GET | `/app/*` | 200 | built web client, SPA fallback |

## Datetime serialization — the highest-risk detail

Every datetime on the wire is **naive ISO-8601 with microsecond precision and no timezone
designator**:

```
"created_at": "2026-07-28T12:33:49.248359"
```

Not `…248Z`, not `…248+00:00`, not `…248`. Six fractional digits, no suffix.

`entry_date` and `days[].date` are plain calendar dates: `"2026-07-28"`.

**Why this is the top risk**: `Date.prototype.toISOString()` produces `2026-07-28T12:33:49.248Z` —
millisecond precision and a `Z`. Both clients parse these fields, and the difference is silent: no
error, just a timestamp that is subtly wrong or a parse that shifts by the machine's UTC offset.

## Numeric formatting

- `average_entries_per_day` is an **unrounded** float: `1.4285714285714286`, `0.32142857142857145`.
  Clients do their own rounding for display — the Android app formats `%.1f`, the web client
  `toFixed(1)`. The backend must not round, or both clients silently start showing a different
  number.
- `confidence` on a suggested feeling is a float; the no-key fallback returns exactly `0.0`,
  serialized as `0.0`.
- `occurrence_count`, `version`, `order_index` are integers.

## Error envelope

Every non-2xx response except the conflict:

```json
{ "error": { "code": "not_found", "message": "Entry not found" } }
```

Code mapping — **400 → `bad_request`, 404 → `not_found`, 422 → `validation_error`**, anything else →
`error`.

**Validation failures are 422, not 400.** FastAPI returns 422 for a missing or malformed field, and
the contract tests assert it. NestJS's `ValidationPipe` defaults to **400**, so the status must be
overridden explicitly. This is a one-line difference that would fail the ported tests immediately —
which is the good case; the bad case is not porting those tests and shipping a 400 the clients don't
expect.

## The 409 conflict body

The one response whose shape is not the standard envelope. It carries the current entry as a sibling
of `error`:

```json
{
  "error": { "code": "stale_entry", "message": "This entry was changed somewhere else since you loaded it." },
  "current": { "id": "…", "raw_text": "…", "version": 4, "…": "…" }
}
```

**It must be returned directly, never thrown through the global error filter** — the filter rebuilds
the body as `{"error": …}` alone, which silently drops `current` and mislabels the code as `error`.
This exact trap was hit and documented in the Python implementation; the Nest equivalent is throwing
`HttpException` and letting an exception filter reshape it.

Three guarantees the contract tests assert:

1. The rejected mutation is a **complete no-op** — a subsequent read returns the entry unchanged.
2. The stored `version` is **not** incremented by a rejected attempt.
3. `current.version` is immediately reusable for a retry.

**A `PATCH` to an entry deleted elsewhere returns 404, not 409** — there is no current version to
compare against. Both clients treat this as its own case.

## Response field shapes

**Entry object** — every field present on every entry response:

```json
{ "id", "created_at", "entry_date", "mode", "raw_text",
  "feeling_key", "feeling_keys", "feeling_source",
  "suggested_feeling", "suggested_feelings", "analysis_pending", "version" }
```

`feeling_key` and `suggested_feeling` are nullable; the keys are always present. Omitting a null key
rather than emitting `null` is a real difference to a statically-typed Kotlin parser.

**An entry carries a set of feelings, not one.** `feeling_keys` is that set in the order it was
chosen, capped at **4**. `feeling_key` is `feeling_keys[0]` — the *primary* feeling, which is what
the calendar dot, the entry card's rail and every `patterns` row are keyed on. It is a
denormalisation, written only alongside the set; nothing may set one without the other. Both fields
stay on the wire so a client built before the vocabulary grew keeps working.

`suggested_feelings` is the analyser's whole proposal, strongest first; `suggested_feeling` is its
first element. Both are served on **every** entry read, not only on create, and are non-empty/
non-null **only when the analyser's proposal differs from the entry's current `feeling_keys`** —
there is nothing to propose when the two already agree. Order does not count as a difference.

`analysis_pending` is `true` while an `entry_analysis` job for that entry is queued or running.
Editing an entry's `raw_text` drops its `entry_topics` links and re-queues analysis, so a client that
has just saved an edit can poll the entry until `analysis_pending` turns `false` and then offer
`suggested_feeling` if one appeared. A feeling-only edit does not re-queue anything.

**Insights** — `{ "patterns": [...], "insufficient_data": bool }`. When no pattern qualifies,
`patterns` is `[]` **and** `insufficient_data` is `true`; the web client branches on the flag, not on
array length. Patterns are ordered by `last_updated_at` descending, **with `id` as a tiebreaker** —
without it, patterns written in the same recompute come back in arbitrary order and the two clients
display different orders (fixed in feature 003).

**Feeling vocabulary** — `GET /feelings` serves the same words twice:

```json
{ "groups": [ { "key", "label", "valence", "feelings": [ ... ] } ],
  "feelings": [ { "key", "label", "valence", "group_key" } ] }
```

`groups` is what both clients render — a short row of group chips that open onto that group's
feelings — and `feelings` is what a stored `feeling_key` is looked up in. Serving only the nested
shape would make every client flatten it for itself; serving only the flat one would make every
client rebuild the grouping. **Every feeling in a group carries that group's `valence`**, which is
what lets a client tint a whole group with one accent without asserting a rule of its own. Emoji and
accent colours are still absent: presentation belongs to each client (Principle VII).

**Monthly summary** — `days` contains an entry for **every day of the month**, including days with no
entries (`"feelings": []`), not just days with data. `feelings` within a day is the sorted distinct
set. `totals_by_feeling` counts **entry–feeling pairs**: an entry tagged with three feelings adds one
to each of their totals, so the totals no longer sum to the entry count.

## Headers

- `Cache-Control: no-store` on `/entries`, `/insights`, `/monthly-summary`, `/guiding-questions`.
- **Not** on `/app/*` static assets — they carry no diary content and benefit from caching.
- No CORS headers; the web client is same-origin by design.

## Static hosting

`/app` serves the built web client with SPA history fallback: any unmatched path under `/app`
returns `index.html`. API routes are registered **first** so `/entries` and `/insights` are never
shadowed. If the build directory is absent, log a warning and serve the API only — never fail to
start, because that would take down the Android app's backend over a missing web build.
