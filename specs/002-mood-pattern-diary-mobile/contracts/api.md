# API Contract: Mood Pattern Diary Backend

REST API exposed by the FastAPI backend on the home LAN. No authentication (spec FR-019). All
request/response bodies are JSON. This is the interface the Android app is built against; FastAPI's
generated OpenAPI schema is the machine-readable source of truth once implemented, this document is
the human-readable contract driving that implementation and the contract tests in
`backend/tests/contract/`.

## Guiding questions

### `GET /guiding-questions`

Returns the full question library so the client can cache it and do keyword-trigger matching
locally while the user types (research.md §1) — no network call needed mid-entry.

**Response 200**:
```json
{
  "questions": [
    {
      "key": "general_feeling",
      "category": "general",
      "prompt_text": "What's going on, and how are you feeling?",
      "trigger_keywords": [],
      "is_mandatory": true
    },
    {
      "key": "food_drink",
      "category": "food_drink",
      "prompt_text": "What did you eat or drink?",
      "trigger_keywords": ["ate", "drank", "food", "coffee", "coke"],
      "is_mandatory": false
    }
  ]
}
```

## Entries

### `POST /entries`

Create a new entry (FR-001/FR-002). Accepts either freeform text or guided answers. Synchronously
returns a Claude-suggested feeling (FR-007) for the client to show as a confirm/override step.

**Request**:
```json
{
  "mode": "guided",
  "raw_text": "Free text, or omitted if guided answers fully describe the entry",
  "guided_answers": [
    { "question_key": "general_feeling", "answer_text": "Felt sleepy after lunch" },
    { "question_key": "food_drink", "answer_text": "Drank a Coca-Cola" }
  ]
}
```

**Response 201**:
```json
{
  "id": "uuid",
  "created_at": "2026-07-27T13:05:00Z",
  "entry_date": "2026-07-27",
  "mode": "guided",
  "raw_text": "...",
  "suggested_feeling": { "key": "sleepy", "confidence": 0.82 },
  "feeling_source": "suggested"
}
```

### `PATCH /entries/{id}`

Confirm/override the feeling and/or edit entry text (FR-007/FR-008).

**Request** (all fields optional):
```json
{ "feeling_key": "sleepy", "raw_text": "edited text" }
```

**Response 200**: Same shape as the entry object above, with `feeling_source` updated to
`confirmed` or `overridden`.

### `DELETE /entries/{id}`

Deletes the entry (FR-008). Cascades to its guided answers and topic links; triggers pattern
recomputation for any Pattern that referenced it (see data-model.md, Edge Cases in spec.md).

**Response**: 204 No Content.

### `GET /entries?date=YYYY-MM-DD`

Lists entries for a given day, ordered by `created_at` (User Story 1, AC2).

**Response 200**: `{ "entries": [ <entry object>, ... ] }`

## Insights

### `GET /insights`

Returns currently active patterns (User Story 3 / FR-010/FR-011/FR-012).

**Response 200**:
```json
{
  "patterns": [
    {
      "id": "uuid",
      "topic": "coca cola",
      "feeling": "sleepy",
      "occurrence_count": 4,
      "direction": "change",
      "narrative_text": "You felt sleepy in 4 of the last 5 entries that mentioned Coca-Cola.",
      "suggestion_text": "Consider cutting back on Coca-Cola, especially earlier in the day.",
      "last_updated_at": "2026-07-27T13:05:00Z"
    }
  ],
  "insufficient_data": false
}
```

If no pattern has yet crossed the minimum-occurrence threshold, `patterns` is empty and
`insufficient_data` is `true`, so the client can show the "more entries needed" state (User Story 3,
AC4) instead of an empty list.

## Monthly summary

### `GET /monthly-summary?month=YYYY-MM`

Powers the calendar view (User Story 5 / FR-015/FR-016).

**Response 200**:
```json
{
  "month": "2026-07",
  "days": [
    { "date": "2026-07-01", "feelings": ["happy"] },
    { "date": "2026-07-02", "feelings": ["sleepy", "exhausted"] },
    { "date": "2026-07-03", "feelings": [] }
  ],
  "totals_by_feeling": { "happy": 12, "sleepy": 5, "exhausted": 3, "neutral": 10 },
  "average_entries_per_day": 1.4
}
```

`average_entries_per_day` = total entries in the month ÷ number of days elapsed in that month
(days in month for a past month; days-so-far for the current month).

## Error shape

All non-2xx responses:
```json
{ "error": { "code": "not_found", "message": "Entry not found" } }
```
