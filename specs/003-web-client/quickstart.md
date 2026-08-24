# Quickstart & Validation: Mood Pattern Diary Web App

> **⚠️ Backend commands below are historical.** The backend was re-platformed from Python/FastAPI to
> NestJS in feature 004, so `uvicorn`, `alembic` and `pytest` no longer exist here. Everything about
> the *product* below still holds — only the commands changed. Current instructions:
> [`backend/README.md`](../../backend/README.md).

How to run the web client and prove this feature works end to end. Walking this through manually at
least once is a constitution quality gate (Development Workflow), and it is the verification route
for FR-014, FR-027, SC-003 and SC-014, which have no automated coverage by design
([research.md §7](./research.md)).

## Prerequisites

- The existing backend set up per [`backend/README.md`](../../backend/README.md).
- **Node 20 LTS** for the web client.
- The Android app installed, for the cross-client scenarios (Scenarios 4–6). Everything else can be
  validated with the browser alone.

## Setup

```bash
# 1. Backend: apply the new version column
cd backend
.venv/bin/alembic upgrade head

# 2. Web client: install and build
cd ../web
npm install
npm run build          # emits static assets the backend serves at /app

# 3. Run the backend (serves both the API and the built web client)
cd ../backend
.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Open **`http://<machine-lan-ip>:8000/app`**. For iterating on the UI, `npm run dev` in `web/` gives
hot reload and proxies API calls to port 8000.

## Automated checks

```bash
cd backend && .venv/bin/pytest -q && .venv/bin/ruff check app tests
cd ../web && npm test && npm run lint
cd ../android && ./gradlew testDebugUnitTest ktlintCheck
```

All three must be clean. The backend suite must include the new `stale_entry` contract tests and the
version-conflict unit tests before the corresponding implementation lands (constitution Principle V).

---

## Validation scenarios

### 1. Write an entry — US1, SC-001

Open `/app`, write a sentence, save. A suggested feeling appears; confirm or override it. The entry
shows up in today's list with a timestamp. **Time it**: under 30 seconds from opening the app.
Write a second entry the same day — under 15 seconds (SC-002) — and confirm both are listed
separately.

### 2. Keyboard only — FR-014, SC-003, SC-014

Repeat Scenario 1 without touching the mouse or trackpad at all. Reach the composer, type, select a
feeling with the arrow keys, and save. At every step you must be able to see which element is
focused. If you lose track of focus even once, SC-014 fails.

### 3. Guided questions — US3

Start a new entry and confirm the guiding prompts appear rather than a bare text box. Answer them and
save; the entry content reflects the answers. Start another and skip the prompts to write freely —
that must also save cleanly.

### 4. One diary across clients — US2, FR-009

Write an entry on the phone, then refresh the web app: same text, timestamp, and feeling. Edit it on
the web, return to the phone, refresh: the edit is there. Check Insights and the monthly view on
both — the totals must match exactly (SC-005), with the entry counted once.

### 5. Conflict, from the web — FR-011, FR-023, SC-008

1. Open the same entry on both the phone and the web app.
2. Edit and save it **on the phone**.
3. Without refreshing, edit it on the **web** and save.

Expected: the save is rejected with a clear "changed somewhere else" message. **Your typed text is
still on screen**, shown next to the current stored version, and you can retry, discard, or carry
your text across. Nothing is silently overwritten and nothing you typed is lost.

### 6. Conflict, from the phone — FR-022

The same as Scenario 5 with the roles reversed: edit on the web first, then save from the phone
against a stale view. The phone must surface the same outcome. This is the scenario that fails if
only the web client was taught about versions.

### 7. Stale delete — FR-021

Open an entry on both clients. Edit it on the phone. Without refreshing, delete it from the web.
The delete must be **rejected**, not silently applied to an entry you can no longer see correctly.

### 8. Unsaved-change guard — FR-026, SC-013

Start typing an entry and try to close the tab: the browser asks you to confirm. Save the entry,
then close the tab again: **no prompt** — a prompt with nothing unsaved is itself a defect.

### 9. Nothing left behind — FR-024, FR-025, SC-012

After a session of writing and browsing:
- Check the address bar and browser history — no entry text, no feelings, only view identifiers and
  opaque UUIDs.
- In devtools → Application, confirm Local Storage, Session Storage, IndexedDB and Cookies hold **no
  diary content**.
- Close the tab, reopen `/app` — nothing you wrote is restored from the browser (it comes back from
  the backend, which is the point).

### 10. Backend unreachable — FR-013, SC-007

Stop the backend, then try to save an entry. Within 10 seconds you must see a clear failure message.
No entry may be reported as saved. Restart the backend and confirm the app recovers on refresh.

### 11. Insights and calendar — US4, US5

With enough entries to cross the pattern threshold, open Insights: patterns in plain language, each
with a suggestion. With too few, the "more entries needed" state instead. Open the monthly view:
per-day feelings, per-feeling totals, daily average — all on one screen (SC-006), matching the phone.

### 12. Responsive and reminders — SC-010, SC-011

Resize from a narrow phone width to a wide monitor: everything stays readable and reachable.
Separately, confirm across a day that reminders arrive **only** from the phone — the web app must
never ask for notification permission (FR-020).

---

## Definition of done

- [ ] All three automated suites clean.
- [ ] Scenarios 1–12 pass by hand.
- [ ] Feelings come from `GET /feelings` on **both** clients — grep the Android source to confirm the
      hardcoded `Feeling` enum no longer carries `key`/`valence` as the source of truth
      (constitution `TODO(PRINCIPLE_VII_RECONCILIATION)` closed).
- [ ] Android regression pass: entry creation, guided flow, insights, calendar and the four daily
      reminders all still work (FR-018).
