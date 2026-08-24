# Quickstart: Mood Pattern Diary Mobile App

> **⚠️ Backend commands below are historical.** The backend was re-platformed from Python/FastAPI to
> NestJS in feature 004, so `uvicorn`, `alembic` and `pytest` no longer exist here. Everything about
> the *product* below still holds — only the commands changed. Current instructions:
> [`backend/README.md`](../../backend/README.md).

Validates the feature end-to-end once implemented, following the priority order of the user
stories in [spec.md](./spec.md). Uses the contract in [contracts/api.md](./contracts/api.md).

## Prerequisites

- Backend host: Python 3.11, dependencies installed (`pip install -r backend/requirements.txt`),
  a `CLAUDE_API_KEY` (or equivalent) environment variable set for the Anthropic API.
- Backend and phone are on the same home Wi-Fi network (per FR-020 — no offline mode).
- Android app installed on a physical device or emulator with network access to the backend host,
  with the backend's LAN IP/port entered once in the app's Settings screen (research.md §6).

## 1. Start the backend

```bash
cd backend
alembic upgrade head   # apply migrations, creates the SQLite DB file
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Confirm it's reachable from the phone: `curl http://<backend-host-ip>:8000/guiding-questions`
should return the seeded question library.

## 2. User Story 1 — capture entries fast

1. In the Android app, tap the new-entry FAB.
2. Write a short entry and save it. Expect: the entry appears immediately in today's list with a
   Claude-suggested feeling shown for confirmation (`POST /entries` → `PATCH /entries/{id}`).
3. Repeat immediately for a second entry the same day. Expect: both entries are listed separately
   under today, in order (validates FR-002).

## 3. User Story 2 — guided entry

1. Start a new entry; expect the mandatory general prompt plus any context-triggered prompts (e.g.,
   typing "I drank a coke" should surface the food/drink prompt per its `trigger_keywords`).
2. Answer the prompts and save. Expect the resulting entry's `raw_text`/guided answers to include a
   clear topic ("coke") and confirmed feeling.
3. Start another entry and choose to skip guided mode; expect a plain free-text composer instead
   (validates FR-005).

## 4. User Story 3 — pattern detection

1. Create at least 3 entries (guided or freeform, on different days if possible) that each mention
   the same topic (e.g., "coca cola") and are confirmed with the same feeling (e.g., "sleepy").
2. Open the Insights screen (`GET /insights`). Expect a pattern entry: topic "coca cola" ↔ feeling
   "sleepy", a plain-language narrative, and a `direction: "change"` suggestion (since sleepy is a
   negative-valence feeling) — validates FR-009/FR-010/FR-011/FR-012.
3. With fewer than 3 supporting entries for any topic, expect `insufficient_data: true` and no
   patterns listed — validates the "not enough data yet" edge case.

## 5. User Story 4 — reminders

1. Ensure notification permission is granted on first launch.
2. Wait for (or, in a debug build, fast-forward) one of the four scheduled times
   (9:00/12:00/18:00/21:00). Expect a notification within 1 minute of the scheduled time
   (validates SC-006).
3. Tap the notification. Expect the app to open directly into the new-entry composer (FR-014).

## 6. User Story 5 — monthly calendar

1. Seed a month's worth of entries with varied feelings (or use a test fixture / seed script).
2. Open the monthly calendar view (`GET /monthly-summary?month=YYYY-MM`). Expect each day cell to
   reflect the feeling(s) logged that day, and a totals panel showing per-feeling counts plus the
   average entries/day — validates FR-015/FR-016.

## 7. Edge cases to spot-check

- Delete one of the entries backing an active pattern; reload Insights and confirm the pattern's
  `occurrence_count` drops accordingly (or the pattern disappears if it falls below the threshold).
- Turn off Wi-Fi on the phone and attempt to save an entry; expect a clear "can't reach the diary
  server" error rather than a silent failure or crash (FR-020 / spec Edge Cases).
- Save an entry without confirming the suggested feeling; confirm it's stored as unclassified and
  is excluded from pattern/monthly aggregation until confirmed.
