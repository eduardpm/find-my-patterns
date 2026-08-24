# Tasks: Mood Pattern Diary Mobile App

**Input**: Design documents from `/specs/002-mood-pattern-diary-mobile/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/api.md, quickstart.md, constitution.md (v1.0.0)

**Tests**: Per constitution Principle V, tests are MANDATORY for backend pattern-detection logic,
feeling/topic aggregation, and API contract behavior — those test tasks are included below and
must be written to fail before their implementation task. Android UI is not test-gated; one
exception is made for reminder-scheduling logic (US4) since it's deterministic, non-UI logic cheap
to unit-test.

**Organization**: Tasks are grouped by user story (spec.md priorities P1–P5) so each can be
implemented, tested, and handed to a separate subagent independently.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: Maps the task to US1–US5 from spec.md
- Every task names its exact file path(s)

## Path Conventions (Mobile + API, per plan.md)

- Backend: `backend/app/...`, `backend/tests/...`
- Android: `android/app/src/main/kotlin/.../...`, `android/app/src/test/...`, `android/app/src/androidTest/...`

---

## Phase 1: Setup (Shared Infrastructure)

- [X] T001 Create the `backend/app/` and `backend/tests/{contract,integration,unit}/` directory skeleton, and `android/app/src/{main,test,androidTest}/` skeleton, per plan.md's Project Structure
- [X] T002 Initialize the backend Python project: `backend/pyproject.toml` (or `requirements.txt`) with FastAPI, uvicorn, SQLAlchemy, Alembic, the Anthropic Python SDK, pytest, httpx
- [X] T003 [P] Configure backend linting/formatting (ruff + black config) in `backend/pyproject.toml`
- [X] T004 Initialize the Android Gradle project in `android/` (Kotlin 2.x, min SDK 26, Jetpack Compose enabled) with `android/build.gradle.kts` and `android/app/build.gradle.kts`
- [X] T005 [P] Add Android dependencies (Compose + Material 3, Retrofit + OkHttp, Kotlin Coroutines/Flow, AndroidX WorkManager) in `android/app/build.gradle.kts`
- [X] T006 [P] Configure Android linting/formatting (ktlint) in `android/app/build.gradle.kts` *(configured; not run — no JDK/Gradle in this environment, see Notes)*

**Checkpoint**: Both projects build empty/skeleton successfully.

---

## Phase 2: Foundational (Blocking Prerequisites)

**⚠️ CRITICAL**: No user story work can begin until this phase is complete — every story needs the
DB, the app entrypoint, the Claude client, and the Android network/nav shell.

- [X] T007 Implement SQLite engine/session management in `backend/app/db/session.py`
- [X] T008 [P] Configure Alembic migrations (`backend/alembic/env.py`, `backend/alembic.ini`) wired to the models package
- [X] T009 [P] Create the `Feeling` model and seed data (happy, excited, neutral, sleepy, exhausted, stressed, sad, depressed, each with a `valence`) in `backend/app/models/feeling.py` and `backend/app/db/seed.py`
- [X] T010 Create the FastAPI app entrypoint with router registration and the shared error-response schema/middleware (per contracts/api.md's error shape) in `backend/app/main.py`
- [X] T011 [P] Implement the Claude API client wrapper with structured/tool-use output for feeling suggestion and pattern narration, per research.md §4, in `backend/app/services/llm_client.py`
- [X] T012 [P] Implement the shared error-response Pydantic schema in `backend/app/schemas/errors.py`
- [X] T013 Android: app shell — navigation graph and Material 3 theme (dynamic color) in `android/app/src/main/kotlin/.../ui/theme/Theme.kt` and `android/app/src/main/kotlin/.../ui/AppNavHost.kt`
- [X] T014 [P] Android: Retrofit/OkHttp network module in `android/app/src/main/kotlin/.../data/NetworkModule.kt`
- [X] T015 Android: Settings screen to configure the backend host/IP + port (research.md §6), stored locally, in `android/app/src/main/kotlin/.../ui/SettingsScreen.kt`

**Checkpoint**: Backend boots and responds with an empty router set; Android app builds, shows nav
shell + Settings, and can reach the backend once an IP is configured.

---

## Phase 3: User Story 1 - Capture a diary entry in seconds (Priority: P1) 🎯 MVP

**Goal**: Freeform entry creation, hybrid feeling suggestion/confirm, edit/delete, multiple
entries/day, per FR-001/002/003/007/008.

**Independent Test**: Open the app, write and save an entry, confirm the suggested feeling, save a
second entry the same day, confirm both are listed separately under today (spec.md US1).

### Tests for User Story 1 (mandatory — constitution Principle V)

- [X] T016 [P] [US1] Contract test for `POST /entries` in `backend/tests/contract/test_entries_create.py`
- [X] T017 [P] [US1] Contract test for `PATCH /entries/{id}` in `backend/tests/contract/test_entries_update.py`
- [X] T018 [P] [US1] Contract test for `DELETE /entries/{id}` in `backend/tests/contract/test_entries_delete.py`
- [X] T019 [P] [US1] Contract test for `GET /entries?date=` in `backend/tests/contract/test_entries_list.py`
- [X] T020 [P] [US1] Integration test: create → suggested feeling returned → confirm → entry appears in day list in `backend/tests/integration/test_entry_lifecycle.py`

### Implementation for User Story 1

- [X] T021 [P] [US1] Create the `DiaryEntry` model in `backend/app/models/entry.py`
- [X] T022 [P] [US1] Create Entry Pydantic schemas (create/update/response) in `backend/app/schemas/entry.py`
- [X] T023 [US1] Implement `EntryService` (create/update/delete/list; calls `llm_client` for feeling suggestion) in `backend/app/services/entry_service.py` (needs T021, T022, T011)
- [X] T024 [US1] Implement the entries router (POST/PATCH/DELETE/GET) in `backend/app/api/entries.py` (needs T023)
- [X] T025 [US1] Register the entries router in `backend/app/main.py` (needs T024, T010)
- [X] T026 [P] [US1] Android: Entry domain model + Retrofit API interface in `android/app/src/main/kotlin/.../domain/Entry.kt` and `android/app/src/main/kotlin/.../data/EntryApi.kt`
- [X] T027 [US1] Android: `EntryRepository` in `android/app/src/main/kotlin/.../data/EntryRepository.kt` (needs T026, T014)
- [X] T028 [US1] Android: `TodayScreen` (today's entry list + new-entry FAB) in `android/app/src/main/kotlin/.../ui/TodayScreen.kt` (needs T027)
- [X] T029 [US1] Android: `EntryComposer` screen (freeform text + suggested-feeling confirm/override) in `android/app/src/main/kotlin/.../ui/EntryComposer.kt` (needs T027)
- [X] T030 [US1] Android: entry detail/edit/delete screen in `android/app/src/main/kotlin/.../ui/EntryDetailScreen.kt` (needs T027)
- [X] T031 [US1] Wire `TodayScreen`, `EntryComposer`, `EntryDetailScreen` into `android/app/src/main/kotlin/.../ui/AppNavHost.kt` (needs T028, T029, T030, T013)

**Checkpoint**: User Story 1 fully functional and independently testable — this is the MVP.

---

## Phase 4: User Story 2 - Be guided by structured questions (Priority: P2)

**Goal**: Guided-prompt entry flow with a free-form bypass, per FR-004/005/006.

**Independent Test**: Start a new entry, see the guided-question sequence, answer it and save;
start another entry and bypass to freeform instead (spec.md US2).

### Tests for User Story 2 (mandatory — constitution Principle V)

- [X] T032 [P] [US2] Contract test for `GET /guiding-questions` in `backend/tests/contract/test_guiding_questions.py`
- [X] T033 [P] [US2] Integration test: create a guided entry with answers → stored with topics extracted in `backend/tests/integration/test_guided_entry.py`

### Implementation for User Story 2

- [X] T034 [P] [US2] Create the `GuidingQuestion` model + seed library (general/food_drink/activity/sleep/social/work_stress, per research.md §1) in `backend/app/models/guiding_question.py` and `backend/app/db/seed.py`
- [X] T035 [P] [US2] Create the `GuidingQuestionAnswer` model in `backend/app/models/guiding_question_answer.py`
- [X] T036 [US2] Implement the guiding-questions router (`GET /guiding-questions`) in `backend/app/api/guiding_questions.py` (needs T034)
- [X] T037 [US2] Extend `EntryService`/entry schemas to accept `mode` + `guided_answers`, persisting `GuidingQuestionAnswer` rows in `backend/app/services/entry_service.py` and `backend/app/schemas/entry.py` (needs T023, T035) — **shared file with T023/T050, see Dependencies note below**. *Resolution note: this was already satisfied by T023's original implementation (guided-mode handling was built in from the start), so no additional edit was needed here.*
- [X] T038 [US2] Register the guiding-questions router in `backend/app/main.py` (needs T036)
- [X] T039 [P] [US2] Android: `GuidingQuestion` domain model + Retrofit endpoint + local cache in `android/app/src/main/kotlin/.../domain/GuidingQuestion.kt` and `android/app/src/main/kotlin/.../data/GuidingQuestionApi.kt`
- [X] T040 [US2] Android: client-side keyword-trigger matching (no network call while typing) in `android/app/src/main/kotlin/.../domain/QuestionTrigger.kt` (needs T039)
- [X] T041 [US2] Android: `GuidedQuestionFlow` composer UI with a "write freely instead" bypass in `android/app/src/main/kotlin/.../ui/GuidedQuestionFlow.kt` (needs T040, T029)
- [X] T042 [US2] Wire the guided-vs-freeform entry point into `android/app/src/main/kotlin/.../ui/EntryComposer.kt` (needs T041, T031)

**Checkpoint**: US1 + US2 both functional.

---

## Phase 5: User Story 3 - Discover patterns, with suggestions (Priority: P3)

**Goal**: The app's core differentiator — deterministic recurrence detection (FR-012) narrated by
Claude (FR-010/FR-011), per constitution Principle III.

**Independent Test**: Seed ≥3 entries pairing the same topic with the same feeling, then confirm
`GET /insights` surfaces that pattern with a narrative and a suggestion; with <3, confirm
`insufficient_data: true` (spec.md US3).

### Tests for User Story 3 (mandatory — constitution Principle V)

- [X] T043 [P] [US3] Contract test for `GET /insights` in `backend/tests/contract/test_insights.py`
- [X] T044 [P] [US3] Unit test for the deterministic recurrence-threshold pattern logic (threshold = 3, per spec Assumptions) in `backend/tests/unit/test_pattern_detection.py`
- [X] T045 [P] [US3] Integration test: 3 same topic+feeling entries → pattern with narrative/suggestion; <3 → insufficient data in `backend/tests/integration/test_pattern_lifecycle.py`

### Implementation for User Story 3

- [X] T046 [P] [US3] Create `Topic`, `EntryTopic`, `Pattern`, `PatternEntry` models in `backend/app/models/topic.py` and `backend/app/models/pattern.py`
- [X] T047 [US3] Implement topic extraction in `backend/app/services/topic_service.py` (needs T046, T011)
- [X] T048 [US3] Implement deterministic recurrence-threshold pattern detection (pure code, no LLM — this is what T044 tests) in `backend/app/services/pattern_service.py` (needs T046)
- [X] T049 [US3] Extend `pattern_service.py` to call `llm_client` for `narrative_text`/`suggestion_text` only once a pattern crosses the threshold, with `direction` derived from `Feeling.valence` (needs T048, T011)
- [X] T050 [US3] Hook topic extraction + pattern recomputation into the entry create/update/delete flow in `backend/app/services/entry_service.py` (needs T047, T048, T023) — **shared file with T023/T037, see Dependencies note below**. *Resolution note: implemented as recompute-on-read instead of a write-time hook — `GET /insights` calls `recompute_patterns()`, which re-scans eligible entries itself, idempotently. This avoids touching `entry_service.py` at all (simpler, per constitution Principle II) while still satisfying FR-009/FR-012.*
- [X] T051 [US3] Implement the insights router (`GET /insights`) in `backend/app/api/insights.py` (needs T049)
- [X] T052 [US3] Register the insights router in `backend/app/main.py` (needs T051)
- [X] T053 [P] [US3] Android: `Pattern` domain model + Retrofit endpoint in `android/app/src/main/kotlin/.../domain/Pattern.kt` and `android/app/src/main/kotlin/.../data/InsightsApi.kt`
- [X] T054 [US3] Android: `InsightsScreen` (pattern cards + narrative + suggestion + "need more data" state) in `android/app/src/main/kotlin/.../ui/InsightsScreen.kt` (needs T053)
- [X] T055 [US3] Wire `InsightsScreen` into `android/app/src/main/kotlin/.../ui/AppNavHost.kt` (needs T054, T031)

**Checkpoint**: US1–US3 functional — the app's central "pattern identification" promise now works
end-to-end.

---

## Phase 6: User Story 4 - Get reminded to check in (Priority: P4)

**Goal**: Four fixed-time daily local notifications that deep-link into the entry composer, per
FR-013/FR-014, SC-006. Purely Android-side — no backend contract.

**Independent Test**: Enable notifications, confirm a notification fires within 1 minute of each
of 9:00/12:00/18:00/21:00, and tapping it opens the new-entry screen directly (spec.md US4).

- [X] T056 [P] [US4] Implement `ReminderScheduler` (exact-alarm scheduling + next-fire-time computation for 9/12/18/21, per research.md §3) in `android/app/src/main/kotlin/.../notifications/ReminderScheduler.kt`
- [X] T057 [P] [US4] Unit test for `ReminderScheduler` next-fire-time computation in `android/app/src/test/kotlin/.../notifications/ReminderSchedulerTest.kt` *(written, JUnit5, pure-logic — not run, no JDK in this environment; reviewed manually, logic verified correct)*
- [X] T058 [US4] Implement `ReminderReceiver` (alarm fire handling + boot-completed re-arm) in `android/app/src/main/kotlin/.../notifications/ReminderReceiver.kt` (needs T056)
- [X] T059 [US4] Implement notification posting with a tap-to-open-`EntryComposer` deep link in `android/app/src/main/kotlin/.../notifications/ReminderNotifier.kt` (needs T058, T031)
- [X] T060 [US4] Request notification permission and register the scheduler on first launch in `android/app/src/main/kotlin/.../MainActivity.kt` (needs T056)

**Checkpoint**: US1–US4 functional.

---

## Phase 7: User Story 5 - Review a month of feelings (Priority: P5)

**Goal**: Monthly calendar view with per-feeling totals and daily average, per FR-015/FR-016.

**Independent Test**: Seed a month of varied entries, confirm `GET /monthly-summary` and the
calendar screen reflect per-day feelings, per-feeling totals, and the daily average (spec.md US5).

### Tests for User Story 5 (mandatory — constitution Principle V)

- [X] T061 [P] [US5] Contract test for `GET /monthly-summary` in `backend/tests/contract/test_monthly_summary.py`
- [X] T062 [P] [US5] Unit test for the monthly aggregation logic (per-feeling counts, `average_entries_per_day` definition from contracts/api.md) in `backend/tests/unit/test_summary_service.py`

### Implementation for User Story 5

- [X] T063 [US5] Implement aggregation logic in `backend/app/services/summary_service.py` (needs T021 from US1)
- [X] T064 [US5] Implement the monthly-summary router (`GET /monthly-summary`) in `backend/app/api/monthly_summary.py` (needs T063)
- [X] T065 [US5] Register the monthly-summary router in `backend/app/main.py` (needs T064)
- [X] T066 [P] [US5] Android: `MonthlySummary` domain model + Retrofit endpoint in `android/app/src/main/kotlin/.../domain/MonthlySummary.kt` and `android/app/src/main/kotlin/.../data/MonthlySummaryApi.kt`
- [X] T067 [US5] Android: `MonthlyCalendarScreen` (calendar grid + totals panel) in `android/app/src/main/kotlin/.../ui/MonthlyCalendarScreen.kt` (needs T066)
- [X] T068 [US5] Wire `MonthlyCalendarScreen` into `android/app/src/main/kotlin/.../ui/AppNavHost.kt` (needs T067, T031)

**Checkpoint**: All five user stories independently functional.

---

## Phase 8: Polish & Cross-Cutting Concerns

- [X] T069 [P] Walk through `quickstart.md` end-to-end manually and fix any gaps found *(backend portion via curl against a live server — full pass; Android portion unverifiable in this environment, see Notes)*
- [X] T070 [P] Generate the initial Alembic migration and verify `alembic upgrade head` from a clean DB in `backend/alembic/versions/`
- [ ] T071 Add structured logging in `backend/app/main.py` *(not done — nice-to-have, deferred)*
- [X] T072 [P] Final Material 3 theming/motion pass for the "modern, sleek" bar (SC-004/SC-009) across `android/app/src/main/kotlin/.../ui/`
- [X] T073 [P] Write `backend/README.md` and `android/README.md` with run instructions
- [X] T074 Repo-wide cleanup pass: `ruff check` clean across `backend/`; `android/` reviewed manually (ktlint config present but not run — no JDK/Gradle in this environment, see Notes)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)** → no dependencies.
- **Foundational (Phase 2)** → depends on Setup; **blocks all user stories**.
- **User Stories (Phase 3–7)** → all depend on Foundational; independently testable per story, but see the **shared-file contention** note below before running them fully in parallel.
- **Polish (Phase 8)** → depends on whichever user stories are in scope for a given delivery.

### User Story Dependencies

- **US1 (P1)**: No dependency on other stories. This is the MVP.
- **US2 (P2)**: Independently testable, but its backend task T037 edits `entry_service.py`, a file US1's T023 also owns.
- **US3 (P3)**: Independently testable given seeded data, but its backend task T050 also edits `entry_service.py`, and depends on the `Feeling.valence` data from Foundational (T009).
- **US4 (P4)**: Fully independent — no shared backend files, touches only `android/.../notifications/`.
- **US5 (P5)**: Independently testable; reads the `DiaryEntry`/`Feeling` models from US1/Foundational but doesn't modify their files.

### ⚠️ Shared-file contention (important for parallel/multi-agent execution)

Since you're planning to run these with subagents in parallel, three files are touched by more
than one story and **must be serialized** (one agent at a time, in this order) even though the
stories around them can otherwise proceed independently:

1. `backend/app/services/entry_service.py` — created by **US1 (T023)**, extended by **US2 (T037)**, extended again by **US3 (T050)**. Run these three sequentially in story-priority order; don't hand US2's and US3's edits to two agents at once.
2. `backend/app/main.py` — router registered by Foundational (T010), then **US1 (T025)**, **US2 (T038)**, **US3 (T052)**, **US5 (T065)**. Each registration is a small, independent line addition — safe to serialize quickly, but not to edit concurrently.
3. `android/app/src/main/kotlin/.../ui/AppNavHost.kt` — wired by Foundational (T013), then **US1 (T031)**, **US3 (T055)**, **US5 (T068)** (US2 doesn't touch this one — T042 only edits `EntryComposer.kt`). Serialize these too.

Everything else within a story phase — models, schemas, Android screens under their own file, all
`[P]` tasks — has no cross-story file overlap and is safe for independent subagents to run
concurrently.

### Parallel Opportunities

- All Setup `[P]` tasks (T003, T005, T006) in parallel.
- All Foundational `[P]` tasks (T008, T009, T011, T012, T014) in parallel, once T007/T010/T013 land.
- Once Foundational is done: **US1 and US4 can start immediately in parallel** (US4 has zero file overlap with anything else). US2, US3, and US5 can also start in parallel with US1 *except* for the three shared files above.
- Within each story, all `[P]`-marked model/schema/domain-model tasks in parallel.

---

## Parallel Example: kicking off after Foundational

```text
# Four subagents can start at once:
Agent A: Phase 3 (US1) — entries CRUD, Today/Composer/Detail screens
Agent B: Phase 6 (US4) — reminder scheduling (zero file overlap, safest full-story parallel pick)
Agent C: Phase 5 (US3) models/tests only (T043-T046) — hold T050 until Agent A finishes T023
Agent D: Phase 7 (US5) — monthly aggregation (only reads Entry/Feeling, no shared-file writes)

# Then, serialized (one agent, in order) once US1's T023 lands:
T037 (US2) → T050 (US3) → router registrations T025/T038/T052/T065 in main.py → nav wiring T031/T055/T068 in AppNavHost.kt
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1 (Setup) → Phase 2 (Foundational) → Phase 3 (US1).
2. **STOP and VALIDATE**: run the US1 section of `quickstart.md` on a real device against a real backend.
3. This alone delivers a working, fast, pleasant diary — no pattern detection yet, but usable.

### Incremental Delivery

1. Foundational → US1 (MVP, freeform + feeling confirm).
2. Add US2 (guided prompts) → re-validate US1 still works.
3. Add US3 (pattern insights — the app's actual differentiator) → validate with seeded recurring entries.
4. Add US4 (reminders) → validate on-device notification timing.
5. Add US5 (monthly calendar) → validate against a seeded month.

### Multi-Agent Parallel Strategy

Given the shared-file contention noted above, the safest split across subagents is:

- One agent owns `entry_service.py` end-to-end (T023 → T037 → T050) sequentially, since every
  story that touches it depends on the previous story's version of that file.
- Separate agents can take US1's Android UI, US3's pattern-detection core (T044/T046/T048/T049,
  everything except T050), US4 entirely, and US5 entirely, all concurrently.
- Save `main.py` router registrations and `AppNavHost.kt` wiring as small, quick, serialized
  "integration" tasks at the end of each story rather than parallelizing them — they're one-line
  additions per story and not worth the coordination cost of splitting further.

---

## Notes

- `[P]` tasks touch different files with no dependency on an incomplete task.
- `[Story]` labels map every user-story-phase task to US1–US5 for traceability back to spec.md.
- Contract and integration tests (T016-T020, T032-T033, T043-T045, T061-T062) are constitution-mandated (Principle V) — write them first and confirm they fail before implementing.
- Commit after each task or logical group; stop at any checkpoint to validate a story independently before moving on.
- **2026-07-27 implementation status**: All backend tasks (Setup/Foundational/US1/US2/US3/US5 + Polish) are complete and verified — 35/35 pytest passing, a live-server smoke test walked through every endpoint end-to-end, `alembic upgrade head` verified from a clean DB, and `ruff check` is clean. All Android tasks (Setup/Foundational/US1/US2/US3/US4/US5 + Polish) are complete and now **build-verified**: a JDK 17 + Gradle 8.9 + Android SDK 35 toolchain was installed locally (no root needed, see `android/README.md`), `./gradlew clean assembleDebug testDebugUnitTest ktlintCheck` passes end-to-end (debug APK produced, 6/6 unit tests, lint clean). Six real Compose/Kotlin API bugs were found and fixed in the process (wrong import packages for `rememberSaveable`/`getValue`/`dp`, a Java-interop property-vs-method mistake, a ktlint/Compose naming false-positive) — see `android/README.md`'s "how this was built and verified" section for the full list. **Still not verified**: no emulator/device was available, so nothing has actually run on Android yet — UI behavior, live network calls, and notification delivery are unverified beyond compilation and the one pure-logic test suite. US4 (reminders) has no backend component at all — it's Android-only per the spec.
