# Tasks: Mood Pattern Diary Web App

**Input**: Design documents from `/specs/003-web-client/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/api.md](./contracts/api.md), [quickstart.md](./quickstart.md)

**Tests**: Per constitution Principle V, tests are **MANDATORY** for API contract behavior and for
correctness-gating logic — here that means the version/conflict rule, the two new endpoints, the two
changed endpoints, and the web client's conflict + unsaved-guard state machines. They MUST be
written first and MUST fail before implementation. Visual/interaction polish on either client is
exempt and is validated by hand via [quickstart.md](./quickstart.md).

**Organization**: Tasks are grouped by user story so each can be implemented and tested independently.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (US1–US5)
- Exact file paths are included in every task

## Path Conventions (multi-client + API, per plan.md)

- **Backend**: `backend/app/`, `backend/tests/`, `backend/alembic/versions/`
- **Web**: `web/src/`, `web/tests/`
- **Android**: `android/app/src/main/kotlin/com/moodpatterndiary/app/` (abbreviated `android/.../` below)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Stand up the new `web/` project so later phases have somewhere to land.

- [X] T001 Create the `web/` project skeleton (Vite 6 + React 18 + TypeScript) with `web/package.json`, `web/vite.config.ts`, `web/tsconfig.json`, `web/index.html`
- [X] T002 Configure `web/vite.config.ts` for the `/app` base path and a dev proxy forwarding API calls to `http://localhost:8000` (research.md §2)
- [X] T003 [P] Configure linting/formatting for the web client in `web/eslint.config.js` and `web/.prettierrc`, with an `npm run lint` script in `web/package.json`
- [X] T004 [P] Configure Vitest + React Testing Library in `web/vitest.config.ts` and `web/tests/setup.ts`, with an `npm test` script in `web/package.json`
- [X] T005 [P] Create the design-token stylesheet mirroring the Android Material 3 palette and type scale in `web/src/styles/tokens.css` (research.md §8)
- [X] T006 [P] Create the base stylesheet — reset, typography, and the visible focus-ring rule required by FR-027 — in `web/src/styles/base.css`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The entry-version contract, the feelings endpoint, static serving, and the web app shell. Every user story depends on these.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### Tests first (mandatory — constitution Principle V)

- [X] T007 [P] Unit tests for the version-conflict rule (match → apply and increment by 1; mismatch → reject, no state change, no increment) in `backend/tests/unit/test_version_conflict.py`
- [X] T008 [P] Contract test for `GET /feelings` — all 8 seeded feelings with `key`/`label`/`valence`, no emoji field — in `backend/tests/contract/test_feelings.py`
- [X] T009 [P] Contract test for `GET /entries/{id}` — 200 with `version`, 404 for unknown id — in `backend/tests/contract/test_entries_get.py`
- [X] T010 [P] Contract tests for the `409 stale_entry` shape on `PATCH` and `DELETE`, asserting the three guarantees in contracts/api.md (rejected write is a no-op, stored version not incremented, `current.version` immediately reusable) in `backend/tests/contract/test_entries_conflict.py`
- [X] T011 [P] Update existing contract tests for the new required `version` field and the `version` key in entry responses in `backend/tests/contract/test_entries_create.py`, `test_entries_list.py`, `test_entries_update.py`, `test_entries_delete.py`

### Backend implementation

- [X] T012 Add the `version` integer column (NOT NULL, default 1) to `DiaryEntry` in `backend/app/models/entry.py` (data-model.md Change 1)
- [X] T013 Generate the additive Alembic revision adding `diary_entries.version` with backfill to 1 in `backend/alembic/versions/` (depends on T012)
- [X] T014 [P] Add `FeelingOut`/`FeelingListOut` schemas in `backend/app/schemas/feeling.py`
- [X] T015 Add `version` to `EntryOut`, make `version` required on `EntryUpdate`, and add the stale-conflict response schema in `backend/app/schemas/entry.py` (depends on T012)
- [X] T016 Implement version checking in `EntryService.update_entry`/`delete_entry` — raise `StaleEntryError` carrying the current entry on mismatch, increment on success — in `backend/app/services/entry_service.py` (depends on T012, T015; makes T007 pass)
- [X] T017 [P] Implement the feelings router (`GET /feelings`) in `backend/app/api/feelings.py` (depends on T014; makes T008 pass)
- [X] T018 Add `GET /entries/{id}`, thread `version` through PATCH/DELETE, and map `StaleEntryError` to the `409` body defined in contracts/api.md in `backend/app/api/entries.py` (depends on T015, T016; makes T009/T010/T011 pass; FR-011). **Return the 409 as an explicit `JSONResponse`, not `raise HTTPException(409, ...)`** — the global handler in `backend/app/main.py:23-26` rebuilds every `HTTPException` as `{"error": {...}}` alone, which would silently drop the `current` entry the contract requires, and `_ERROR_CODES` has no 409 entry so `code` would come out as `"error"` instead of `"stale_entry"`
- [X] T019 Register the feelings router, mount the built web client at `/app` with SPA history fallback, and add `Cache-Control: no-store` to diary-bearing responses in `backend/app/main.py` (depends on T017, T018; FR-025, research.md §2/§5). **Skip the mount with a logged warning when the build directory is absent** rather than letting `StaticFiles` raise at startup — a backend-only run or a fresh clone must still serve the API, or the Android app breaks in violation of FR-018. Leave the existing exception handlers alone; T018 owns the 409 shape

### Web foundation

- [X] T020 [P] Define TypeScript types mirroring the backend schemas — `Entry` (with `version`), `Feeling`, `GuidingQuestion`, `Pattern`, `MonthlySummary` — in `web/src/domain/types.ts` (contracts/api.md; carries no rules or thresholds, per Principle VII)
- [X] T021 Implement the fetch wrapper and `ApiResult` error mapping, including the `409 stale_entry` → `Conflict` mapping and network-failure mapping for FR-013, in `web/src/api/client.ts` (depends on T020). **Every request MUST carry an explicit abort timeout of ~8s** — `fetch` has no default timeout, so a hung connection (backend machine asleep, wrong IP) would otherwise hang indefinitely and SC-007's 10-second bound would have no mechanism behind it; a timed-out request maps to the same user-facing failure as a network error
- [X] T022 [P] Implement the feelings endpoint wrapper in `web/src/api/feelings.ts` (depends on T021)
- [X] T023 [P] Implement the entries endpoint wrappers — list, get, create, patch, delete, all passing `version` — in `web/src/api/entries.ts` (depends on T021)
- [X] T024 Create the app shell, bottom/side navigation, and the router with routes under `/app` in `web/src/App.tsx` and `web/src/main.tsx` (depends on T005, T006; FR-024 — routes carry only view identity and opaque UUIDs)
- [X] T025 [P] Implement the reusable error/offline banner used by every screen for FR-013 in `web/src/components/ErrorBanner.tsx`
- [X] T026 [P] Implement the `useRefreshable` hook backing FR-019's explicit per-view refresh in `web/src/hooks/useRefreshable.ts`

**Checkpoint**: Backend serves `/feelings`, enforces versions, and hosts the web shell at `/app`. User stories can now proceed.

---

## Phase 3: User Story 1 - Write and manage diary entries from a computer (Priority: P1) 🎯 MVP

**Goal**: A person can open the web app, write entries, confirm a feeling, and edit or delete them — entirely from a browser, entirely from the keyboard if they choose.

**Independent Test**: Open `/app`, write an entry, confirm a feeling, save; write a second entry the same day; confirm both are listed separately; edit one and delete the other. Repeat using only the keyboard. (quickstart.md Scenarios 1, 2, 8, 10)

### Tests for User Story 1 (mandatory — constitution Principle V)

- [X] T027 [P] [US1] Tests for the unsaved-change guard's arm/disarm transitions — armed only while text differs from last saved, disarmed on save (FR-026, SC-013) — in `web/tests/useUnsavedGuard.test.ts`
- [X] T028 [P] [US1] Tests for API error mapping surfacing a clear failure within the FR-013/SC-007 budget when the backend is unreachable, in `web/tests/apiClient.test.ts`

### Implementation for User Story 1

- [X] T029 [P] [US1] Implement the `useUnsavedGuard` hook — `beforeunload` plus in-app navigation blocking, registered only while dirty — in `web/src/hooks/useUnsavedGuard.ts` (makes T027 pass; research.md §6)
- [X] T030 [P] [US1] Implement the feeling chip selector as a keyboard-navigable labelled radio group, fed by `GET /feelings`, in `web/src/components/FeelingChips.tsx` (depends on T022; FR-014, FR-027)
- [X] T031 [P] [US1] Implement the entry card used in day listings in `web/src/components/EntryCard.tsx`
- [X] T032 [US1] Implement the freeform composer with the suggest-then-confirm feeling flow and a "suggesting…" state, in `web/src/screens/EntryComposer.tsx` (depends on T023, T029, T030; FR-002/FR-003/FR-005)
- [X] T033 [US1] Implement today's entry list with the explicit refresh control in `web/src/screens/TodayScreen.tsx` (depends on T023, T026, T031; FR-019)
- [X] T034 [US1] Implement entry detail with edit and delete, sending `version` on both, in `web/src/screens/EntryDetailScreen.tsx` (depends on T023, T029; FR-006)
- [X] T035 [US1] Wire the Today, Composer, and Entry Detail routes into `web/src/App.tsx` (depends on T032, T033, T034 — **shared file, see contention note**)
- [X] T036 [US1] Add loading and empty states across the US1 screens in `web/src/screens/TodayScreen.tsx` and `web/src/screens/EntryComposer.tsx`
- [X] T037 [US1] Verify keyboard-only completion of the full write→confirm→save flow and fix any focus-order or focus-visibility gaps across `web/src/screens/` and `web/src/components/` (FR-014, FR-027, SC-003, SC-014)

**Checkpoint**: US1 is a shippable MVP — the web app is usable for writing on its own.

---

## Phase 4: User Story 2 - One diary, whichever device I'm on (Priority: P2)

**Goal**: One diary across phone and browser, with concurrent edits from either side rejected rather than silently clobbering — and the feeling set sourced from the backend on both clients.

**Independent Test**: Create an entry on the phone and see it on the web (and vice versa); edit the same entry from both with a stale view in each direction and confirm the later save is rejected with the user's text preserved; confirm insights/monthly totals match on both clients. (quickstart.md Scenarios 4, 5, 6, 7)

### Tests for User Story 2 (mandatory — constitution Principle V)

- [X] T038 [P] [US2] Tests for the web conflict state machine — 409 → preserve draft → retry with current version / discard / carry text across; and the deleted-elsewhere 404 branch — in `web/tests/conflict.test.tsx` (FR-023, contracts/api.md)
- [X] T039 [P] [US2] Integration test proving an entry edited via one client's request path is reflected in the other's read path and counted once in insights and monthly summary, in `backend/tests/integration/test_cross_client_consistency.py` (FR-009, FR-010, SC-005)
- [X] T040 [P] [US2] Unit test for the Android 409 mapping producing a stale-entry result rather than a generic error, in `android/app/src/test/kotlin/com/moodpatterndiary/app/data/ConflictMappingTest.kt`

### Implementation for User Story 2

- [X] T041 [US2] Implement the conflict resolution screen showing the user's text beside the current stored version with retry/discard/carry-across actions in `web/src/screens/ConflictScreen.tsx` (depends on T021, T034; makes T038 pass; FR-023)
- [X] T042 [US2] Route `PATCH`/`DELETE` rejections from entry detail and the composer into the conflict screen, and handle the deleted-elsewhere 404 branch, in `web/src/screens/EntryDetailScreen.tsx` (depends on T041; FR-021)
- [X] T043 [US2] Wire the conflict route into `web/src/App.tsx` (depends on T041 — **shared file, see contention note**)
- [X] T044 [P] [US2] Add the feelings Retrofit endpoint in `android/.../data/FeelingApi.kt` and register it in `android/.../data/NetworkModule.kt`
- [X] T045 [US2] Migrate `android/.../domain/Feeling.kt` off the hardcoded enum to the backend-served set, keeping only the emoji mapping client-side (depends on T044; constitution Principle VII — closes `TODO(PRINCIPLE_VII_RECONCILIATION)`)
- [X] T046 [US2] Update `android/.../ui/components/FeelingChipRow.kt` to render the fetched feeling list (depends on T045)
- [X] T047 [US2] Send `version` on PATCH/DELETE and map `409` to a stale-entry result in `android/.../data/EntryApi.kt` and `android/.../data/EntryRepository.kt` (depends on T018; makes T040 pass; FR-022)
- [X] T048 [US2] Surface the FR-023 outcome on Android — user's text preserved alongside the current stored version, with retry/discard/carry-across — in `android/.../ui/EntryDetailScreen.kt` (depends on T047)
- [X] T049 [US2] Add the `version` field to the Android entry model in `android/.../domain/Entry.kt` (depends on T018)

**Checkpoint**: Both clients participate in conflict protection and source feelings from the backend. SC-005 and SC-008 are now verifiable.

---

## Phase 5: User Story 3 - Be guided by structured questions in the browser (Priority: P3)

**Goal**: The browser composer offers the same guiding prompts as the phone, and lets the user skip them.

**Independent Test**: Start an entry in the browser and confirm guiding questions appear and their answers become the entry; start another, skip them, and confirm a freeform entry saves. (quickstart.md Scenario 3)

### Tests for User Story 3 (mandatory — constitution Principle V)

- [X] T050 [P] [US3] Tests for guiding-question trigger matching — the mandatory general prompt always shows, keyword-triggered prompts surface only on match — in `web/tests/guidedQuestions.test.ts` (research.md §1)

### Implementation for User Story 3

- [X] T051 [P] [US3] Implement the guiding-questions endpoint wrapper in `web/src/api/guidingQuestions.ts` (depends on T021)
- [X] T052 [US3] Implement the guided question flow with keyword-triggered prompts and a bypass-to-freeform action in `web/src/screens/GuidedQuestionFlow.tsx` (depends on T051; makes T050 pass; FR-004, FR-005)
- [X] T053 [US3] Submit guided answers via `POST /entries` with `mode: "guided"` from `web/src/screens/EntryComposer.tsx` (depends on T052)
- [X] T054 [US3] Wire the guided flow route into `web/src/App.tsx` (depends on T052 — **shared file, see contention note**)

**Checkpoint**: Blank-page hesitation is handled on the web, and guided entries feed pattern detection identically to phone entries.

---

## Phase 6: User Story 4 - Review patterns and suggestions on a big screen (Priority: P4)

**Goal**: The Insights view in the browser, matching the phone.

**Independent Test**: Seed entries that cross the pattern threshold, open Insights in the browser, and confirm the patterns and suggestions match the phone's; with too few entries, confirm the "more entries needed" state. (quickstart.md Scenario 11)

- [X] T055 [P] [US4] Implement the insights endpoint wrapper in `web/src/api/insights.ts` (depends on T021)
- [X] T056 [P] [US4] Implement the pattern card — narrative, suggestion, and keep/change direction rendered from the response, never recomputed — in `web/src/components/PatternCard.tsx` (Principle VII)
- [X] T057 [US4] Implement the Insights screen including the `insufficient_data` state and refresh control in `web/src/screens/InsightsScreen.tsx` (depends on T026, T055, T056; FR-007)
- [X] T058 [US4] Wire the Insights route into `web/src/App.tsx` (depends on T057 — **shared file, see contention note**)

**Checkpoint**: The app's central payoff is readable on a large screen.

---

## Phase 7: User Story 5 - See a month of feelings in a calendar on the web (Priority: P5)

**Goal**: The monthly calendar with per-feeling totals and the daily average, on one screen.

**Independent Test**: Seed a month of varied entries, open the monthly view, and confirm each day cell reflects that day's feelings, empty days are distinguishable, and month totals plus the daily average match the phone. (quickstart.md Scenario 11)

### Tests for User Story 5 (mandatory — constitution Principle V)

- [X] T059 [P] [US5] Test that the calendar renders month totals and the daily average exactly as returned, with no client-side re-tallying, in `web/tests/monthlyCalendar.test.tsx` (Principle VII, SC-005)

### Implementation for User Story 5

- [X] T060 [P] [US5] Implement the monthly-summary endpoint wrapper in `web/src/api/monthlySummary.ts` (depends on T021)
- [X] T061 [US5] Implement the calendar grid with multi-feeling day cells and visually distinct empty days in `web/src/components/CalendarGrid.tsx` (FR-008, US5 AC3/AC4)
- [X] T062 [US5] Implement the monthly screen with per-feeling totals, daily average, and month navigation in `web/src/screens/MonthlyCalendarScreen.tsx` (depends on T060, T061; makes T059 pass; SC-006)
- [X] T063 [US5] Wire the Calendar route into `web/src/App.tsx` (depends on T062 — **shared file, see contention note**)

**Checkpoint**: Feature parity with the Android app is complete.

---

## Phase 8: Polish & Cross-Cutting Concerns

- [X] T064 [P] Responsive pass from narrow phone width to wide desktop across `web/src/screens/` and `web/src/styles/` (FR-015, SC-010)
- [X] T065 [P] Motion and visual refinement pass for the "modern, sleek" bar across `web/src/screens/` and `web/src/styles/` (FR-015, SC-009)
- [X] T066 Privacy audit against FR-024/FR-025/SC-012: confirm no diary content in any route, in `localStorage`/`sessionStorage`/IndexedDB/cookies, or in the HTTP cache; verify `Cache-Control: no-store` is actually applied — across `web/src/` and `backend/app/main.py`
- [X] T067 Verify the web client never registers a service worker and never requests notification permission (FR-020, SC-011) across `web/src/`
- [X] T068 [P] Accessibility inspection pass — focus visibility on every interactive element, text contrast, control labelling — across `web/src/` (FR-027, SC-014)
- [X] T069 [P] Write `web/README.md` with setup, dev, build, and pairing instructions
- [X] T070 [P] Update `backend/README.md` for the new `/app` mount and the `alembic upgrade head` step, and `android/README.md` for the backend-served feeling set
- [X] T071 Android regression pass on a device/emulator — entry creation, guided flow, insights, calendar, and the four daily reminders all still work — covering `android/app/src/main/kotlin/com/moodpatterndiary/app/` (FR-018) *(Run on a headless API-35 emulator (Pixel 6, x86_64) driven over adb/uiautomator, against a live backend reached via `adb reverse`. Verified: app launches with no crash; notification permission prompt on first run; Settings pairing; **Today shows entries created in the browser** (FR-009); feeling chips render from `GET /feelings` with labels from the backend and emoji client-side (T045/T046); guided flow opens with the mandatory prompt and a "Write freely instead" bypass (FR-004/FR-005); a guided entry created on device reached the backend as `mode=guided`, then the feeling confirm step took it to **v2/overridden** — the versioned PATCH working on a real device (T047); Insights render "You felt sleepy in 4 recent entries mentioning coca cola" with counts identical to the backend (SC-005); monthly calendar renders July 2026 with per-feeling legend and daily average; **exactly four `REMINDER_FIRED` alarms scheduled**, `ReminderReceiver` registered for `BOOT_COMPLETED`, and a reminder actually fired and posted "Time to check in / How are you doing right now? Log a quick entry." (FR-013). One cross-client discrepancy found and fixed — see T072.)*
- [X] T072 Walk through all 12 validation scenarios in `specs/003-web-client/quickstart.md` end to end and fix any gaps found *(All 12 done. Scenarios 3, 5, 7, 9, 10, 11 verified live against a running backend on a freshly migrated database; 1, 2, 8, 9, 12 verified in real headless Chromium against the built app — SC-001 first entry 0.9s, SC-002 second entry 0.3s, SC-003 the whole flow completed keyboard-only with the feeling picked by arrow keys, SC-014 focus visible across 25 tab stops, SC-013 prompt on close-while-dirty and silence when clean, SC-012 localStorage/sessionStorage/IndexedDB/cookies all empty after a full session, FR-024 no diary text in any address, SC-010 no horizontal overflow at 320/390/768/1440px; the conflict path (5/7) driven through the browser — stale save refused, the user's text preserved beside the stored version, retry against the current version succeeded, stale delete refused; 4 and 6 verified in both directions across the real emulator and the browser. Three defects found and fixed during the walkthrough: focus not moving to the composer after skipping the guided questions, and the daily-average formatting mismatch between clients. The Playwright harness was deliberately not kept — research.md §7 excludes it as a project dependency, so it was installed with `--no-save` and removed afterwards.)*
- [X] T073 Repo-wide cleanup: `ruff check` clean in `backend/`, `npm run lint` clean in `web/`, `ktlintCheck` clean in `android/`
- [X] T074 Verify the LAN-only constraint now that the backend also serves a UI: confirm the service is reachable from the home network and **not** from outside it, and document the exposure risk (no auth + a browsable UI on one port ⇒ never port-forward this) in `backend/README.md` (FR-016, constitution Product Constraints "Clients are LAN-only")

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies.
- **Foundational (Phase 2)**: depends on Setup. **Blocks every user story.**
- **US1 (Phase 3)**: depends on Foundational. No dependency on any other story.
- **US2 (Phase 4)**: depends on Foundational; its web half also depends on US1's entry-detail screen (T034).
- **US3 (Phase 5)**: depends on Foundational; extends US1's composer (T032).
- **US4 (Phase 6)**: depends on Foundational only.
- **US5 (Phase 7)**: depends on Foundational only.
- **Polish (Phase 8)**: depends on all stories being complete.

### User Story Dependencies

- **US1 (P1)**: fully independent once Foundational lands — this is the MVP.
- **US2 (P2)**: needs US1's entry detail to hang conflict resolution off. Its Android half (T044–T049) is independent of the web half and can run concurrently.
- **US3 (P3)**: needs US1's composer.
- **US4 (P4)**: independent — could be built before US2 or US3 if insights matter more than cross-client safety.
- **US5 (P5)**: independent.

### ⚠️ Shared-file contention (important for parallel/multi-agent execution)

1. `web/src/App.tsx` — created by Foundational (T024), then edited by **US1 (T035)**, **US2 (T043)**, **US3 (T054)**, **US4 (T058)**, **US5 (T063)**. Each is a small route addition; serialize them, never hand two to concurrent agents.
2. `backend/app/api/entries.py` — all changes are in Foundational (T018) by design, so no story touches it. Keep it that way.
3. `backend/app/services/entry_service.py` — likewise Foundational-only (T016).
4. `backend/app/main.py` — Foundational-only (T019), then read-only until T066.
5. `web/src/screens/EntryComposer.tsx` — created by **US1 (T032)**, extended by **US3 (T053)**. Serialize.
6. `web/src/screens/EntryDetailScreen.tsx` — created by **US1 (T034)**, extended by **US2 (T042)**. Serialize.
7. `android/.../data/EntryRepository.kt` — touched only by **US2 (T047)**.
8. `backend/README.md` — written by Polish **T070**, appended by Polish **T074**. Both are Phase 8; serialize them (T070 first).

### Parallel Opportunities

- All of Phase 1 except T001→T002 (T003–T006 are independent).
- Foundational tests T007–T011 are fully parallel and should all be written before T012.
- T014/T017 (feelings) are independent of T012/T015/T016/T018 (versioning) and can run alongside.
- Web foundation T020–T026 is independent of the backend work once contracts/api.md is fixed.
- **US2's Android half (T044–T049) and web half (T041–T043) are independent** — the largest genuine parallel win in this feature.
- US4 and US5 are independent of each other and of US2/US3; three agents could take them concurrently after US1.
- Polish T064, T065, T068, T069, T070 are all parallel. T074 must follow T070 (both write `backend/README.md`).

---

## Implementation Strategy

### MVP First (User Story 1 only)

Phases 1 → 2 → 3. That delivers a browser you can write your diary in, with edit and delete, keyboard-operable, failing loudly when the backend is unreachable. Stop and use it for a few days before continuing — it is the phase most likely to change your mind about the composer.

### Incremental Delivery

1. **Setup + Foundational** → backend contract settled, web shell served at `/app`.
2. **+ US1** → 🎯 MVP: usable web diary.
3. **+ US2** → safe to use both clients in the same day; the Principle VII debt is closed.
4. **+ US3** → guided prompts on the web.
5. **+ US4** → insights on a big screen.
6. **+ US5** → full parity.
7. **+ Polish** → responsive, private, accessible, documented.

### Multi-Agent Parallel Strategy

After Foundational completes:

```text
Agent A: US1 end to end (T027–T037) — owns EntryComposer.tsx and EntryDetailScreen.tsx
Agent B: US2 Android half (T040, T044–T049) — owns android/, starts immediately, no US1 dependency
Agent C: US4 (T055–T058) — owns InsightsScreen.tsx and PatternCard.tsx
Agent D: US5 (T059–T063) — owns MonthlyCalendarScreen.tsx and CalendarGrid.tsx
```

Then serialize: US2's web half (T041–T043) after Agent A finishes T034, US3 (T050–T054) after Agent A finishes T032, and every `web/src/App.tsx` route wiring (T035 → T043 → T054 → T058 → T063) one at a time.

## Notes

- The `version` contract change (T012–T019) must land before **any** client work, because both clients' edit and delete paths depend on it. This is the single most important ordering constraint in the feature.
- **Two traps in Foundational, both found by `/speckit-analyze` and both already written into the tasks** — read T018 and T019 in full before touching `backend/`. Raising `HTTPException(409, ...)` will silently produce the wrong response body, and mounting `StaticFiles` unconditionally will stop the backend from starting when `web/` hasn't been built. Both fail in ways that look like something else.
- T045 (Android feelings migration) closes `TODO(PRINCIPLE_VII_RECONCILIATION)` from the constitution's Sync Impact Report. When it lands, that follow-up can be struck from `.specify/memory/constitution.md`.
- No task introduces client-side computation of any count, average, or threshold. If a task seems to require it, the design has drifted from Principle VII — stop and reconcile rather than working around it.
- T071's Android regression pass is not optional: FR-018 is the requirement most likely to be quietly broken by T045 and T047.
