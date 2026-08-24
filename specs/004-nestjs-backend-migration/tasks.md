# Tasks: Re-platform the Backend onto NestJS

> **⚠️ Superseded in part (2026-07-29).** The Python backend was deleted, the differential test
> strategy was dropped, and the deliberately-ported topic-matching defect was fixed — because the
> **spec**, not the previous implementation, is the source of truth. The new backend now lives at
> `backend/`. Read the **Outcome** section at the top of [spec.md](./spec.md) before relying on
> anything here.

**Input**: Design documents from `/specs/004-nestjs-backend-migration/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/api.md](./contracts/api.md), [quickstart.md](./quickstart.md)

**Tests**: **MANDATORY throughout, and they are the deliverable.** This feature adds no behaviour, so
"it works" is meaningless — the only thing that can be demonstrated is *equivalence*. Constitution
Principle V requires tests for correctness-gating logic and contract behaviour, and FR-012/SC-006
extend that to every rule the current backend enforces. The 71 existing pytest cases in `backend/`
are the porting checklist.

**Organization**: Grouped by user story. Note that this feature's stories are *properties of the
whole system* rather than separable slices of functionality, so each phase is defined as **the slice
of the port that makes that story true**, and each is still independently testable.

---

## ⚠️ Blocker found while generating these tasks: SC-011 is not achievable as written

**`GET /insights` writes to the database on every call.** Verified against the running Python
backend: hashing the file, issuing one more `GET /insights` with no data change, and re-hashing gives
a different digest. `recompute_patterns()` runs on every read and unconditionally deletes and
re-inserts `pattern_entries` rows, then commits.

That puts two requirements in direct conflict:

- **FR-022 / SC-011** — "Starting the new backend against an existing diary and reading every screen
  leaves the stored data unchanged."
- **FR-011 / SC-002** — the new backend must produce identical pattern behaviour to the old one.

A faithful port *must* write on `/insights`. A backend that doesn't has changed the behaviour.

**Resolution assumed by these tasks** (spec correction recommended, see T072): FR-022's intent is that
*merely starting up* — connecting, seeding, schema handling — must not touch the diary. That intent is
preserved and tested (T009, T026). `/insights` writes by design in both backends, so the correct check
there is **differential** (both write the same thing), not "no writes". T026 covers the genuinely
read-only paths; T040 covers `/insights` by comparison.

This is worth fixing in the spec rather than quietly reinterpreting: as written, SC-011 would either
fail or push an implementer into "fixing" `/insights`, which would break SC-002.

---

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: US1–US5 from spec.md
- Exact file paths in every task

> **IDs are deliberately non-contiguous.** `T073`–`T076` were added after `/speckit-analyze` and are
> placed in their correct **execution position**, not appended at the end — so read the file in order,
> not by number. `T071` was deleted (it directed an edit to the constitution outside the amendment
> process, on a false premise: no principle changes in this feature). Existing IDs were left stable
> so the Dependencies section and any work already in flight keep referring to the same tasks.

## Path Conventions

- **New backend**: `backend/src/`, `backend/tests/`
- **Reference implementation (never modified)**: `backend/`
- **Clients (never modified)**: `web/`, `android/`

---

## Phase 1: Setup

**Purpose**: Stand up `backend/` alongside the untouched `backend/`.

- [X] T001 Create the NestJS + TypeScript skeleton in `backend/package.json`, `backend/tsconfig.json`, `backend/nest-cli.json`, with `@nestjs/common`, `@nestjs/core`, `@nestjs/platform-express`, `better-sqlite3`, `@anthropic-ai/sdk`, `zod` (research.md §2 — **no ORM, no migration tool**)
- [X] T002 Configure Vitest in `backend/vitest.config.ts` and `backend/tests/setup.ts`
- [X] T003 [P] Configure eslint + prettier in `backend/eslint.config.js` and `backend/.prettierrc`, matching the settings already used in `web/`
- [X] T004 [P] Add `start`, `build`, `test`, `lint`, `format` scripts to `backend/package.json`, mirroring `web/package.json` so both sides share one command vocabulary (US4)
- [X] T005 [P] Implement configuration reading `DATABASE_PATH`, `PORT`, `ANTHROPIC_API_KEY` and the web build location in `backend/src/config.ts`, defaulting to the same values the Python backend uses
- [X] T006 [P] Add `backend/.gitignore` for `node_modules/`, `dist/`, `*.log`, `.env*`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The codec layer, storage access, seeding, and the error envelope. Everything else
depends on these, and **the codecs are where this feature is most likely to fail silently**.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### Tests first (mandatory — Principle V, and these are the highest-value tests in the feature)

- [X] T007 [P] Codec tests in `backend/tests/codecs.test.ts` asserting against literals captured from the live database: datetimes round-trip as `2026-07-28 12:33:49.248359` (space separator, **six** fractional digits, no zone), dates as `2026-07-28`, JSON arrays as `["ate", "drank"]` (**space after comma**), booleans as `1`/`0`. Include an explicit assertion that a `Date`-based path producing `.248Z` or `.248000` fails (data-model.md)
- [X] T008 [P] Test in `backend/tests/no-ddl.test.ts` proving the storage layer issues no `CREATE`/`ALTER`/`DROP`/`PRAGMA user_version` write — instrument the driver and assert only DML is executed (FR-022)
- [X] T009 [P] Test in `backend/tests/seed-noop.test.ts` proving that seeding an already-populated diary changes nothing: hash the file before and after (FR-022, data-model.md "Seeding")
- [X] T010 [P] Create the golden fixture in `backend/tests/fixtures/golden.db` — a diary generated **by the Python backend** containing freeform and guided entries, all four feeling sources, multi-feeling days, and at least one qualifying pattern. Record how it was generated in `backend/tests/fixtures/README.md` so it can be regenerated

### Implementation

- [X] T011 Implement the value codecs in `backend/src/db/codecs.ts` — the single place any datetime, date, JSON column or boolean crosses into or out of storage or the wire (makes T007 pass; research.md §1)
- [X] T012 Implement the `better-sqlite3` handle in `backend/src/db/database.ts`: open the existing file, set `PRAGMA foreign_keys = ON` per connection, expose a transaction helper, and issue **no DDL ever** (makes T008 pass; data-model.md "Cascades")
- [X] T013 Implement idempotent seeding in `backend/src/db/seed.ts` — insert feelings and guiding questions only when those tables are empty (makes T009 pass)
- [X] T014 [P] Implement the error envelope filter in `backend/src/common/http-exception.filter.ts` producing `{"error":{"code","message"}}` with the mapping `400→bad_request`, `404→not_found`, `422→validation_error`, and **override Nest's default 400 for validation failures to 422** (contracts/api.md)
- [X] T015 [P] Implement the stale-entry conflict response in `backend/src/common/stale-entry.ts`, returned **directly rather than thrown**, so the `current` sibling key survives the filter (contracts/api.md — this is a documented trap)
- [X] T016 Implement the application bootstrap in `backend/src/main.ts` and `backend/src/app.module.ts`: LAN bind, filter registration, config wiring
- [X] T017 [P] Implement the feelings and guiding-questions repositories in `backend/src/feelings/feelings.repository.ts` and `backend/src/guiding-questions/guiding-questions.repository.ts`
- [X] T018 Implement the entry and guided-answer repositories in `backend/src/entries/entries.repository.ts`, decoding through the codecs
- [X] T019 [P] Implement the topic and pattern repositories in `backend/src/topics/topics.repository.ts` and `backend/src/insights/patterns.repository.ts`
- [X] T074 Implement a startup compatibility check in `backend/src/db/compatibility.ts` — verify every expected table and column is present with the expected type before serving, and **refuse to start with a clear message** if the diary cannot be fully interpreted, rather than starting up and presenting a partial diary (FR-018). Cover it with a test in `backend/tests/compatibility.test.ts` using a deliberately truncated fixture. **Note: this is the feature's only genuinely new behaviour** — the Python backend has no equivalent, so porting alone will never produce it
- [X] T076 [P] Implement request-body validation with `zod` in `backend/src/common/validation.pipe.ts`, rejecting malformed or missing fields and surfacing them through the 422 mapping from T014 — without this the contract tests asserting 422 for a missing `version` have nothing to exercise (plan.md lists `zod` as a dependency; T014 only maps the status)
- [X] T020 Implement the Claude client in `backend/src/llm/llm.client.ts` with the same two tool-shaped calls and the **word-for-word identical** no-API-key fallback (`neutral` at `0.0`; the templated narrative and suggestion strings), injected as a dependency rather than reading the environment at construction (research.md §5)

**Checkpoint**: storage reads and writes reproduce Python's byte formats exactly. Nothing else is safe until this holds.

---

## Phase 3: User Story 1 - My diary survives the change completely (Priority: P1) 🎯 MVP

**Goal**: Point the new backend at a real diary and read everything back identically, without writing to it.

**Independent Test**: Copy a real diary, hash it, serve it with the new backend, read every entry, the month and the feeling set, compare all of it against the Python backend on an identical copy, and confirm the hash is unchanged. (quickstart.md scenarios 1, 2)

### Tests for User Story 1 (mandatory)

- [X] T021 [P] [US1] Contract test for `GET /feelings` in `backend/tests/contract/feelings.test.ts` — 8 seeded feelings, seed order, `key`/`label`/`valence` only, no emoji
- [X] T022 [P] [US1] Contract test for `GET /guiding-questions` in `backend/tests/contract/guiding-questions.test.ts` — full library including `trigger_keywords` decoded from JSON
- [X] T023 [P] [US1] Contract tests for `GET /entries?date=` and `GET /entries/{id}` in `backend/tests/contract/entries-read.test.ts` — ordering by `created_at`, `version` present, 404 shape, and **`created_at` serialized with microseconds and no timezone suffix**
- [X] T024 [P] [US1] Contract test for `GET /monthly-summary` in `backend/tests/contract/monthly-summary.test.ts` — every day of the month present including empty ones, `feelings` a sorted distinct set, `totals_by_feeling` counting entries, and the average **unrounded** and divided by *days elapsed* (data-model.md)
- [X] T025 [US1] Read-fidelity test in `backend/tests/fidelity/read-golden.test.ts` — every entry, guided answer, feeling and pattern in `tests/fixtures/golden.db` reads back with identical values (SC-001)
- [X] T026 [US1] No-write test in `backend/tests/fidelity/no-write-on-read.test.ts` — hash the golden diary, start the app, exercise **every genuinely read-only endpoint** (`/feelings`, `/guiding-questions`, `/entries`, `/entries/{id}`, `/monthly-summary`), and assert the hash is unchanged. **`/insights` is deliberately excluded and must be commented as such** — it writes by design in both backends (see the blocker note above; covered instead by T040)

### Implementation for User Story 1

- [X] T027 [P] [US1] Implement `GET /feelings` in `backend/src/feelings/feelings.controller.ts` and `feelings.service.ts`
- [X] T028 [P] [US1] Implement `GET /guiding-questions` in `backend/src/guiding-questions/guiding-questions.controller.ts` and `guiding-questions.service.ts`
- [X] T029 [US1] Implement `GET /entries?date=` and `GET /entries/{id}` in `backend/src/entries/entries.controller.ts` and the read half of `entries.service.ts`
- [X] T030 [US1] Implement monthly aggregation in `backend/src/monthly-summary/monthly-summary.service.ts` — days-elapsed rule, distinct sorted per-day sets, entry-counting totals, no rounding
- [X] T031 [US1] Implement `GET /monthly-summary` in `backend/src/monthly-summary/monthly-summary.controller.ts`
- [X] T032 [US1] Run the new backend against a copy of a real diary and confirm scenarios 1 and 2 of `specs/004-nestjs-backend-migration/quickstart.md` by hand, recording the before/after hashes in `backend/tests/fidelity/README.md`

**Checkpoint**: the diary is provably readable and untouched — the MVP of a re-platform.

---

## Phase 4: User Story 2 - Provably equivalent, not assumed equivalent (Priority: P2)

**Goal**: The write path and the deterministic core, with every rule the Python suite pins down re-established and a differential harness proving the two backends agree.

**Independent Test**: Run the ported suite and the differential harness — replay an identical request sequence against both backends over copies of one diary and diff both the responses and the resulting database files. (quickstart.md scenarios 3, 4, 5)

### Tests for User Story 2 (mandatory — this phase is mostly tests, by design)

- [X] T033 [P] [US2] Port the version/conflict unit tests to `backend/tests/unit/version-conflict.test.ts` from `backend/tests/unit/test_version_conflict.py` — starts at 1, increments by exactly 1, mismatch rejected, **rejected write is a complete no-op and does not increment**
- [X] T034 [P] [US2] Port the pattern-detection unit tests to `backend/tests/unit/pattern-detection.test.ts` from `backend/tests/unit/test_pattern_detection.py` — the threshold-of-3 rule as a pure function
- [X] T035 [P] [US2] Port the summary unit tests to `backend/tests/unit/summary.test.ts` from `backend/tests/unit/test_summary_service.py`
- [X] T036 [P] [US2] Topic-extraction tests in `backend/tests/unit/topics.test.ts` — curated keyword matching, idempotence, **and an explicit test asserting `"I drank water"` yields the topic `exercise`**, labelled as a deliberate bug-for-bug port with a pointer to research.md §4
- [X] T037 [P] [US2] Port the write contract tests to `backend/tests/contract/entries-write.test.ts` from `backend/tests/contract/test_entries_{create,update,delete}.py` and `test_entries_conflict.py` — including the three 409 guarantees, 422 for a missing `version`, and 404 for an entry deleted elsewhere
- [X] T038 [P] [US2] Port the integration tests to `backend/tests/integration/` from `backend/tests/integration/` — entry lifecycle, guided entry, pattern lifecycle, cross-client consistency
- [X] T073 [P] [US2] Derived-value tests in `backend/tests/unit/guided-composition.test.ts` asserting the exact composed `raw_text` for a guided entry (single-space join of `"{prompt} {answer}"`, only when submitted `raw_text` is empty), the `question_text_snapshot` fallback to `question_key` for an unknown question, `order_index` ordering, and `extracted_by = "keyword"`. Assert against the literal string in data-model.md "Derived values" — this is a third fidelity boundary and, unlike the codecs, has no other guard
- [X] T039 [US2] Build the differential harness in `backend/tests/differential/harness.ts` — copy a fixture diary twice, start both backends, replay a scripted request sequence against each, diff responses **including datetime formatting and float precision**, then diff both database files row by row (research.md §8)
- [X] T040 [US2] Differential test in `backend/tests/differential/parity.test.ts` covering create → suggest → confirm → edit → conflict → delete → insights → monthly, **explicitly including repeated `/insights` calls** so the writes that endpoint makes are compared rather than assumed

### Implementation for User Story 2

- [X] T041 [US2] Implement the entry write path in `backend/src/entries/entries.service.ts` — create with `version: 1`, the feeling-source transition rules, and the version check plus update **inside one transaction** (makes T033 pass; data-model.md). **Reproduce the guided-entry derived values exactly** per data-model.md "Derived values": `raw_text` composed as `"{prompt_text} {answer_text}"` per answer joined by a single space and only when the submitted `raw_text` is empty; `question_text_snapshot` set to the question's prompt text, falling back to the `question_key` string when the question is unknown; `order_index` the zero-based submission position
- [X] T042 [US2] Implement `POST`, `PATCH` and `DELETE /entries` in `backend/src/entries/entries.controller.ts`, returning 201/200/204 and routing conflicts through the direct-response helper from T015
- [X] T043 [US2] Implement topic extraction in `backend/src/topics/topics.service.ts` — port the curated keyword map and substring matching **exactly, defect included**, with a comment explaining that the behaviour is deliberate (makes T036 pass). Write `entry_topics.extracted_by` as the literal `"keyword"`, not `NULL`, despite the column being nullable (data-model.md "Derived values")
- [X] T044 [US2] Implement pattern detection in `backend/src/insights/patterns.service.ts` — confirmed/overridden entries only, threshold of 3, `last_updated_at` stamped **only when the pattern actually changed**, and patterns dropped when they fall below threshold
- [X] T045 [US2] Implement `GET /insights` in `backend/src/insights/insights.controller.ts` — recompute before reading, `insufficient_data` flag, ordering by `last_updated_at` descending **with `id` as tiebreaker** (contracts/api.md — without it the two clients show different orders)
- [X] T046 [US2] Wire pattern narration through the LLM client in `backend/src/insights/patterns.service.ts`, calling it only when a pattern is new or its count changed
- [X] T047 [US2] Reconcile coverage: enumerate all 71 cases in `backend/tests/` against the ported suite and record the mapping in `backend/tests/PORTING.md`, with a justification for any case deliberately not ported (FR-012, SC-006)

**Checkpoint**: equivalence is demonstrated rather than asserted.

---

## Phase 5: User Story 3 - Both clients keep working untouched (Priority: P3)

**Goal**: Static hosting and header behaviour identical, verified by running the real, unmodified clients.

**Independent Test**: Point the installed Android app and the existing `web/dist` at the new backend and complete every journey on both, changing nothing on either. (quickstart.md scenarios 6, 7, 8)

### Tests for User Story 3 (mandatory)

- [X] T048 [P] [US3] Static-hosting tests in `backend/tests/contract/static-hosting.test.ts` — `/app/` serves the app, `/app/calendar` falls back to `index.html` rather than a JSON 404, `/insights` still returns JSON and is **not** shadowed, and a missing build directory logs a warning while the API keeps serving
- [X] T049 [P] [US3] Header tests in `backend/tests/contract/headers.test.ts` — `Cache-Control: no-store` on `/entries`, `/insights`, `/monthly-summary`, `/guiding-questions`, and **absent** on `/app/*` static assets

### Implementation for User Story 3

- [X] T050 [US3] Implement static hosting in `backend/src/main.ts` — mount the web build at `/app` **after** all API routes, with SPA history fallback and a guard that skips the mount and warns when the directory is absent (research.md §6)
- [X] T051 [US3] Implement the cache-control middleware in `backend/src/common/no-store.middleware.ts`, applied to diary-bearing paths only
- [X] T052 [US3] Serve the existing unmodified `web/dist` from the new backend and walk every screen — today, composer, guided flow, entry detail, insights, calendar
- [X] T053 [US3] Point the installed, unmodified Android app at the new backend and complete every journey including a forced conflict from a stale view — exercising `android/app/src/main/kotlin/com/moodpatterndiary/app/` without editing it
- [X] T054 [US3] Verify the conflict path from both clients against the new backend — refused save, user's text preserved, retry with the returned version succeeds, stale delete refused — covering `web/src/screens/ConflictScreen.tsx` and `android/.../ui/EntryDetailScreen.kt` as consumers
- [X] T055 [US3] Confirm and record that **no file under `web/` or `android/` was modified** for any of the above (SC-004, FR-006)

**Checkpoint**: both clients work against the new backend with zero changes.

---

## Phase 6: User Story 4 - The maintainer works in one language (Priority: P4)

**Goal**: The stated motivation, made real and checkable.

**Independent Test**: Make a change spanning the contract and the browser client and complete it in one language with one command vocabulary per side.

- [X] T056 [P] [US4] Align the command vocabulary between `backend/package.json` and `web/package.json` so `npm test`, `npm run lint`, `npm run build` mean the same thing on both sides
- [X] T057 [P] [US4] Write `backend/README.md` — setup, run, test, configuration, and an explicit statement that it reads the existing diary file with no migration step
- [X] T058 [US4] Walk through a contract-spanning change touching `backend/src/` and `web/src/` and confirm it can be made and verified without leaving TypeScript

---

## Phase 7: User Story 5 - The switch can be undone (Priority: P5)

**Goal**: A rehearsed, documented cutover with a rollback that has actually been performed.

**Independent Test**: Switch, write an entry, revert to the Python backend, and confirm the diary — including the post-switch entry — is intact on both clients.

- [X] T059 [P] [US5] Write the cutover and rollback runbook in `backend/CUTOVER.md` — stop, **back up the diary file**, start the other backend; no conversion in either direction
- [X] T060 [US5] Rehearse the cutover on a copy: Python → Nest, confirm both clients work, and time it against SC-009's 15 minutes, recording the timing in `backend/CUTOVER.md`
- [X] T061 [US5] Rehearse the rollback: Nest → Python on the same file, confirm the diary is intact and both clients work, recording the result in `backend/CUTOVER.md`
- [X] T062 [US5] Write an entry on the new backend, revert, and confirm it survives — then state the finding plainly in `backend/CUTOVER.md` (FR-017 requires the maintainer to *know*, not assume)
- [X] T063 [US5] Confirm `backend/` is still present, unmodified and passing its own suite after all of the above (FR-019)

---

## Phase 8: Polish & Cross-Cutting Concerns

- [X] T064 [P] Compare perceived latency of entry save, day load, month load and insights between the two backends on the same diary and record the result in `backend/README.md` (SC-007)
- [X] T065 [P] Repo-wide cleanup: `npm run lint` clean in `backend/`, `ruff check` still clean in `backend/`, `npm run lint` still clean in `web/`
- [X] T066 [P] Update `backend/README.md` and `web/README.md` to point at the new backend where relevant, without implying the Python one has been removed
- [X] T067 Walk through all 11 validation scenarios in `specs/004-nestjs-backend-migration/quickstart.md` end to end and fix any gaps found
- [X] T068 Record the two deliberately-ported defects as follow-up work in `backend/tests/PORTING.md` — the topic-extraction substring bug (research.md §4) and the `entry_date` UTC-vs-local clock mismatch (research.md §3), each with the test that currently locks the behaviour
- [X] T069 Verify no diary content reaches any new destination: with `ANTHROPIC_API_KEY` unset the app works fully on the deterministic fallback, and with it set the only outbound traffic is to the Claude API (SC-010, FR-013)
- [X] T070 Confirm the final state of `backend/` is byte-identical to its pre-feature state — this feature must not have edited the reference implementation at all
- [X] T075 Verify the LAN-only constraint for the new backend: confirm it is reachable from the home network and **not** from outside it, and carry the exposure warning from `backend/README.md` into `backend/README.md` — no authentication plus a browsable UI on one port means this must never be port-forwarded (FR-015, constitution Product Constraints "Clients are LAN-only")
- [X] T072 Raise the SC-011 conflict documented at the top of this file as a spec correction — narrow SC-011 to startup and read-only endpoints, and note that `/insights` writes by design in both backends. **Do not silently reinterpret it in code**

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies.
- **Foundational (Phase 2)**: depends on Setup. **Blocks every user story.** The codecs (T011) block everything that touches storage or the wire.
- **US1 (Phase 3)**: depends on Foundational. The MVP.
- **US2 (Phase 4)**: depends on Foundational; its differential harness (T039) needs US1's read endpoints to compare anything meaningful.
- **US3 (Phase 5)**: depends on US1 and US2 — both clients exercise read *and* write paths, so neither can be verified before those exist.
- **US4 (Phase 6)**: depends only on Setup in principle; verified meaningfully once there is real code to change.
- **US5 (Phase 7)**: depends on US1–US3 — there is nothing worth cutting over to until the clients work.
- **Polish (Phase 8)**: depends on everything.

### ⚠️ Shared-file contention

1. `backend/src/main.ts` — created in Foundational (T016), extended by **US3 (T050)** for static hosting. Serialize.
2. `backend/src/entries/entries.service.ts` — read half in **US1 (T029)**, write half in **US2 (T041)**. Serialize; one owner end to end is better.
3. `backend/src/entries/entries.controller.ts` — read routes in **US1 (T029)**, write routes in **US2 (T042)**. Serialize.
4. `backend/src/insights/patterns.service.ts` — detection in **T044**, narration wiring in **T046**. Same owner, sequential.
5. `backend/CUTOVER.md` — written by **T059**, appended by **T062**.
6. **`backend/` — read-only for the entire feature.** Any task that edits it is a bug (T070 checks this).

### Parallel Opportunities

- Phase 1 after T001: T003–T006 are independent.
- **Foundational tests T007–T010 are fully parallel and should all exist before T011.** T007 is the single highest-value test in the feature.
- T074 (startup compatibility check) and T076 (request validation) are independent of each other and of the codec work.
- T073 (derived-value tests) joins the T033–T038 parallel block — seven independent test files.
- T014, T015, T017, T019, T020 are independent of each other once T011/T012 land.
- US1's contract tests T021–T024 are fully parallel.
- US2's ported test files T033–T038 are fully parallel — six independent files, the largest parallel win here.
- US3's T048/T049 are parallel; T052 (web) and T053 (Android) are independent of each other.
- Polish T064, T065, T066 are parallel.

---

## Implementation Strategy

### MVP (Phases 1–3)

Stop after US1 and evaluate honestly. At that point the new backend can read a real diary correctly
and provably doesn't touch it — which is the point at which you will know whether the fidelity work
(codecs, formats, no-DDL storage) is as manageable as this plan assumes. **If it isn't, abandoning
here costs nothing**: `backend/` is untouched and still serving. That option is deliberately
preserved and is a legitimate outcome, not a failure.

### Incremental Delivery

1. **Setup + Foundational** → byte formats provably match.
2. **+ US1** → 🎯 reads a real diary identically, writes nothing.
3. **+ US2** → equivalence demonstrated by the ported suite and the differential harness.
4. **+ US3** → both real clients work untouched.
5. **+ US4** → one language, one command vocabulary.
6. **+ US5** → cutover and rollback rehearsed, not theorised.
7. **+ Polish** → parity confirmed, follow-ups recorded.

### Multi-Agent Parallel Strategy

Poorly suited to heavy parallelism: almost everything routes through the codec layer and the shared
entries service. After Foundational:

```text
Agent A: US1 end to end (T021–T032) — owns entries.service.ts / entries.controller.ts
Agent B: US2 ported unit tests only (T033–T036) — pure functions, no shared files
Agent C: the differential harness (T039) — self-contained, and the most valuable thing to have early
```

Then serialize US2's implementation behind Agent A's US1 work, since both own the entries module.

## Notes

- **The 71 tests in `backend/` are the specification.** Where this plan and those tests disagree, the tests win — they are what the system actually does.
- **Two defects are ported on purpose** (research.md §3, §4). Anything that looks like an improvement in the new backend's output is a defect *of this feature*, because it breaks SC-002/SC-005.
- `/insights` writes on read. That is current behaviour, it is preserved, and it is why SC-011 needs correcting rather than implementing.
- The most likely silent failure in the whole feature is a datetime serialized as `…248Z` instead of `…248359`. T007 exists to catch it on day one; if T007 is weak, nothing downstream will save you.
- **There are three fidelity boundaries, not two.** The plan identified storage format and wire format; `/speckit-analyze` found a third — *derived* values the backend computes before storing, chiefly the guided-entry `raw_text` composition. It has no codec guarding it and it feeds topic extraction, so a wrong separator changes stored text, what the user sees, and which patterns get detected. T073 is its only guard. If another derived value turns up during implementation, treat it the same way: pin it in data-model.md, then test it.
