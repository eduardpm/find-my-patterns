# API Contract Delta: Web Client

This documents **only what changes** against
[002's contract](../../002-mood-pattern-diary-mobile/contracts/api.md), which remains the base and
is otherwise unaffected. `GET /guiding-questions`, `GET /insights`, `GET /monthly-summary` and
`POST /entries`' request shape are untouched.

Still no authentication, still JSON over the home LAN, still the same error envelope. FastAPI's
generated OpenAPI schema remains the machine-readable source of truth; this document drives the
contract tests in `backend/tests/contract/`.

**Compatibility note (FR-018)**: every existing Android *request* shape stays valid, and every
existing endpoint keeps its path and meaning. The one behavioral break is deliberate and specified:
`PATCH`/`DELETE` now require `version`. The Android client is updated in this same feature
(FR-022), so no shipped client is left behind.

---

## NEW — `GET /feelings`

Serves the fixed feeling set so no client hardcodes it (constitution Principle VII, research.md §4).

**Response 200** (abridged — see `backend/src/db/feeling-vocabulary.ts` for the full list):
```json
{
  "groups": [
    { "key": "uplifted", "label": "Uplifted", "valence": "positive",
      "feelings": [
        { "key": "happy", "label": "Happy", "valence": "positive", "group_key": "uplifted" },
        { "key": "grateful", "label": "Grateful", "valence": "positive", "group_key": "uplifted" }
      ] },
    { "key": "steady", "label": "Steady", "valence": "neutral", "feelings": [ ... ] },
    { "key": "tense",  "label": "Tense",  "valence": "negative", "feelings": [ ... ] },
    { "key": "low",    "label": "Low",    "valence": "negative", "feelings": [ ... ] }
  ],
  "feelings": [
    { "key": "happy", "label": "Happy", "valence": "positive", "group_key": "uplifted" }
  ]
}
```

The same words are served twice on purpose. `groups` is what both clients render — the vocabulary
is around thirty words, far too many to put on screen at once without slowing the entry flow
(Principle VI), so a client shows the four groups and opens a group's own feelings on demand.
`feelings` is the flat lookup for resolving a stored `feeling_key`.

**Every feeling in a group carries that group's `valence`.** That invariant is what lets a client
tint an entire group with one accent colour without asserting anything the backend did not say —
and it is why there are four accent colours per theme rather than thirty.

Order is the backend's `sort_order` and is stable; clients render what they are given. Emoji and
accent colours are deliberately **not** included — presentation stays with the client.

---

## NEW — `GET /entries/{id}`

Fetch a single entry. Needed by the web client's entry-detail route (`/app/entry/{id}`), which can
be opened directly without having listed that day first.

**Response 200**: the entry object (including `version`).
**Response 404**: `{ "error": { "code": "not_found", "message": "Entry not found" } }`

---

## CHANGED — entry object gains `version`

Every response that returns an entry (`POST /entries`, `GET /entries`, `GET /entries/{id}`,
`PATCH /entries/{id}`) now includes an integer `version`:

```json
{
  "id": "uuid",
  "created_at": "2026-07-28T13:05:00Z",
  "entry_date": "2026-07-28",
  "mode": "guided",
  "raw_text": "...",
  "feeling_key": "sleepy",
  "feeling_keys": ["sleepy", "stressed"],
  "feeling_source": "suggested",
  "suggested_feeling": { "key": "sleepy", "confidence": 0.82 },
  "suggested_feelings": [
    { "key": "sleepy", "confidence": 0.82 },
    { "key": "stressed", "confidence": 0.41 }
  ],
  "version": 1
}
```

Additive: existing clients that ignore the field are unaffected on reads. An entry carries a **set**
of up to four feelings; `feeling_key` is `feeling_keys[0]`, the primary one, and both stay on the
wire so a client built before the vocabulary grew keeps working.

---

## CHANGED — `PATCH /entries/{id}` requires `version`

**Request**:
```json
{ "feeling_keys": ["sleepy", "stressed"], "raw_text": "edited text", "version": 3 }
```

`version` is **required**; `raw_text`, `feeling_keys` and `feeling_key` are all optional.

`feeling_keys` replaces the entry's whole set, in the order sent, and is capped at **4**. The
single-key `feeling_key` form is still accepted and means a set of one; sending both is not an
error and `feeling_keys` wins. An **absent or empty** list leaves the feelings unchanged — there is
no way to clear an entry's feelings, which is deliberate.

`feeling_source` becomes `confirmed` when the saved set matches what the analyser suggested and
`overridden` otherwise; the comparison ignores order.

- **200** — applied. Response is the entry with `version` incremented by 1.
- **409** — the entry changed since the client read it (FR-011). Nothing was modified.
- **422** — `version` missing.
- **404** — no such entry.

---

## CHANGED — `DELETE /entries/{id}` requires `version`

**Request**: `DELETE /entries/{id}?version=3`

A query parameter rather than a body, since DELETE bodies are unreliably supported (research.md §3).

- **204** — deleted.
- **409** — the entry changed since the client read it. Nothing was deleted (FR-021).
- **422** — `version` missing.
- **404** — no such entry.

---

## NEW — `409 Conflict` response shape

Returned by `PATCH` and `DELETE` when the supplied `version` is stale. It carries the **current**
server-side entry so the client can render FR-023's side-by-side comparison without a second
round trip:

```json
{
  "error": {
    "code": "stale_entry",
    "message": "This entry was changed somewhere else since you loaded it."
  },
  "current": {
    "id": "uuid",
    "created_at": "2026-07-28T13:05:00Z",
    "entry_date": "2026-07-28",
    "mode": "freeform",
    "raw_text": "the version that is actually stored",
    "feeling_key": "happy",
    "feeling_source": "confirmed",
    "version": 4
  }
}
```

The `error` envelope matches the existing shape; `current` is an additional sibling key present only
on `stale_entry` responses.

**If the entry was deleted elsewhere**, a `PATCH` returns `404`, not `409` — there is no current
version to compare against. Clients must treat this as its own case: the user's text is still
preserved on screen (FR-023) but the only meaningful actions are to discard it or save it as a new
entry.

**Contract guarantees for `stale_entry`** — these are what the contract tests assert:
1. The rejected mutation is a complete no-op; a subsequent read returns the entry unchanged.
2. The stored `version` is **not** incremented by a rejected attempt.
3. `current.version` in the body equals the stored version, so a client can retry immediately with it.

---

## Static assets — `GET /app/*`

The built web client is served by the same FastAPI process under the `/app` prefix, with SPA history
fallback (unknown sub-paths return `index.html`). No API path changes meaning; the prefix exists so
that SPA routes cannot collide with `/entries` or `/insights` (research.md §2).

Diary-bearing API responses are served with `Cache-Control: no-store` so entry content is not
written to the browser's disk cache (FR-025).
