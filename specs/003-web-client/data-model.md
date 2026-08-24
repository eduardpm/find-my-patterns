# Phase 1 Data Model: Mood Pattern Diary Web App

This feature adds **no new persistent entity**. The full diary model is defined in
[002's data-model.md](../002-mood-pattern-diary-mobile/data-model.md) and remains authoritative;
this document records only the delta, plus the client-side shapes the web app holds in memory.

## Change 1 — `DiaryEntry.version` (new column)

The only schema change in this feature.

| Field | Type | Notes |
|---|---|---|
| `version` | int, NOT NULL, default `1` | Incremented by the backend on every mutation of the entry (text, feeling, or guided answers). Never set by a client. |

**Migration**: one additive Alembic revision. Existing rows backfill to `1`. No data is rewritten
and no column is dropped, so the migration is safe to apply to a live diary.

**Validation / rules**:
- `PATCH /entries/{id}` and `DELETE /entries/{id}` MUST carry the version the client last read
  (FR-011, FR-022).
- If the supplied version ≠ the stored version, the mutation is rejected with `409` and **no state
  changes** — the rejection must not partially apply an edit (FR-023's "never silently pick a
  winner" depends on the rejected write being a no-op).
- If the supplied version equals the stored version, the mutation applies and `version` increments
  by exactly 1.
- `POST /entries` returns `version: 1`.
- A rejected mutation does not increment the version — otherwise a client retrying twice against an
  unchanged entry would be rejected the second time for no reason.

**Why not `updated_at`**: that column already exists but is unsuitable as a concurrency token — see
[research.md §3](./research.md).

**Relationship to pattern detection**: none. `version` is metadata about client synchronization; it
carries no diary content and is never an input to topic extraction, feeling inference, or the
recurrence threshold. Bumping it does not invalidate or recompute any `Pattern`.

## Change 2 — `Feeling` becomes a served resource

The `Feeling` entity is unchanged (`key`, `label`, `valence`). What changes is **where clients get
it**: previously seeded in the backend and separately hardcoded in the Android app; now exposed via
`GET /feelings` and fetched by both clients (constitution Principle VII, research.md §4).

`valence` is a rule, not decoration — it determines each insight's `keep`/`change` direction — so it
MUST come from the backend. Per-feeling emoji and ordering remain client-side presentation and are
deliberately *not* added to the entity.

## Entry state transitions (unchanged, restated for the conflict path)

`feeling_source` still moves `unset → suggested → confirmed | overridden`. The new conflict path
does not add a state: a rejected mutation leaves the entry exactly as it was, including its
`feeling_source`. The conflict is resolved entirely in the client's UI, and any resulting change
arrives as an ordinary `PATCH` carrying the now-current version.

## Client-side shapes (web, in memory only)

Held in React state for the lifetime of the tab and never persisted (FR-025).

| Shape | Fields | Purpose |
|---|---|---|
| `Entry` | mirrors the API entry object, including `version` | Rendering and round-tripping. The client stores `version` opaquely and never computes with it. |
| `Feeling` | `key`, `label`, `valence` — fetched, not hardcoded | Feeling chips; valence used only for display grouping, never to derive a suggestion direction. |
| `GuidingQuestion` | `key`, `category`, `prompt_text`, `trigger_keywords`, `is_mandatory` | Fetched once per session; keyword matching runs client-side purely to decide *which prompt to show*, which is presentation, not a fact about the diary. |
| `Draft` | `text`, `guidedAnswers[]`, `dirty` | The composer's working state. `dirty` drives FR-026's guard. Discarded with the tab. |
| `Conflict` | `mine: Draft`, `theirs: Entry` | Populated from a 409 response. Holds both versions so FR-023 can show them side by side; cleared when the user retries, discards, or carries their text across. |

None of these shapes carries a threshold, a count, or an aggregate — every fact the web client
displays arrives from the backend already computed (Principle VII).

## Monthly summary and insights (unchanged)

Still derived on request by the backend and never persisted. The web client renders
`GET /monthly-summary` and `GET /insights` responses verbatim; it does not re-tally per-feeling
counts, recompute the daily average, or filter patterns by occurrence count. SC-005's
"identical on both clients" holds by construction because neither client computes anything.
