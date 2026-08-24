# Implementation Plan: Mood Pattern Diary Mobile App

**Branch**: `002-mood-pattern-diary-mobile` | **Date**: 2026-07-27 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/002-mood-pattern-diary-mobile/spec.md`

## Summary

A native Android diary app for fast, guided multi-entry-per-day journaling, paired with a
Python/FastAPI backend the user runs on their own machine. Each entry (freeform or guided by
structured prompts) gets a Claude-suggested feeling the user confirms; over time the backend
correlates recurring topics in entry text with feelings and surfaces plain-language patterns and
suggestions. The Android app also handles four fixed-time daily reminder notifications and a
monthly calendar view of feeling counts/averages. The app only needs to work while the phone is on
the same home network as the backend (or a VPN to it); no offline mode or in-app auth for v1.

## Technical Context

**Language/Version**: Backend: Python 3.11. Mobile: Kotlin 2.x (Android, min SDK 26 / Android 8+, target latest stable).

**Primary Dependencies**: Backend: FastAPI, uvicorn, SQLAlchemy + Alembic, Anthropic Python SDK (Claude API for feeling suggestion and pattern narration). Mobile: Jetpack Compose + Material 3, Retrofit + OkHttp (REST client), AndroidX WorkManager/AlarmManager (reminders), Kotlin Coroutines/Flow.

**Storage**: SQLite file on the backend host, accessed via SQLAlchemy. Chosen over a client-server DB because this is a single-user, single-machine deployment (see [research.md](./research.md)).

**Testing**: Backend: pytest (contract tests against the FastAPI OpenAPI schema, integration tests against a test SQLite DB, unit tests for pattern-detection logic). Mobile: JUnit5 + Compose UI testing / Espresso for instrumented flows.

**Target Platform**: Android phone (client) talking over the home LAN to a FastAPI service running on the user's existing Linux machine (this machine).

**Project Type**: Mobile + API (native Android client + local backend service).

**Performance Goals**: Entry save round-trips in well under 1s on the home network (excluding the async LLM feeling-suggestion call, which the UI shows as a brief "suggesting…" state per SC-001/SC-002). Reminder notifications fire within 1 minute of their scheduled time (SC-006). Insight/pattern recomputation completes within a few seconds when triggered by a new entry.

**Constraints**: Home-network-only connectivity — no offline entry creation/sync (FR-020). The backend itself needs outbound internet access to reach the Claude API even though phone↔backend traffic stays on the LAN. No in-app authentication (FR-019); relies on device lock + private network. Fixed daily reminder schedule (9:00/12:00/18:00/21:00) must survive Android Doze/battery optimization.

**Scale/Scope**: Single user, single backend instance, no multi-tenancy. Expected volume: a handful of entries/day, low thousands/year — no concurrency or horizontal-scale concerns. 5 prioritized user stories, 20 functional requirements.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Re-checked 2026-07-27 against constitution v1.0.0 (ratified after this plan's original draft).

| Principle | Status | Notes |
|---|---|---|
| I. Spec-First Workflow | ✅ Pass | This plan follows an approved, checklist-validated spec.md. |
| II. Simplicity & YAGNI | ✅ Pass | Single user, single backend instance, SQLite (no server DB to operate), no auth subsystem, no multi-tenancy — matches FR-017/018/019 and Product Constraints. |
| III. Deterministic Core, LLM at the Edges | ✅ Pass | research.md §4: minimum-occurrence pattern detection runs as deterministic application code; Claude is used only for feeling *suggestion* (user must confirm/override, FR-007) and pattern *narration* — never as sole authority for a count or threshold. |
| IV. Privacy by Architecture | ⚠ Exception, now documented | Claude API calls transmit entry text/topics off the user's machine for inference and narration. This was previously only implicit in plan.md/research.md; **spec.md's Assumptions now explicitly discloses and justifies it** (added during this re-check) per the principle's requirement. Persistent storage itself remains local-only (FR-018), satisfied. |
| V. Test-First for Logic, Not UI Polish | ✅ Pass | Testing section below already scopes pytest contract/integration/unit tests to the backend (pattern logic, API contracts); Android UI tests are not gated on TDD. |
| VI. UX Bar: Fast and Pleasant | ✅ Pass | research.md §1 and §5 explicitly optimize the guided-question and composer flow against SC-001/SC-002 speed targets. |

**Complexity Tracking**: the Principle IV exception above is the only flagged item, and it's
resolved by disclosure/justification in spec.md rather than by a design change — see the table
below.

*Post-Phase-1 re-check*: Still holds — Phase 1 design (data-model.md, contracts/api.md) introduces
no new off-device data flow beyond the two Claude calls already accounted for above, and no
additional projects/services beyond the one backend + one mobile client in Project Structure.

## Project Structure

### Documentation (this feature)

```text
specs/002-mood-pattern-diary-mobile/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md         # Phase 1 output (/speckit-plan command)
├── quickstart.md         # Phase 1 output (/speckit-plan command)
├── contracts/            # Phase 1 output (/speckit-plan command)
│   └── api.md
└── tasks.md              # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
backend/
├── app/
│   ├── main.py                 # FastAPI app entrypoint, uvicorn bound to LAN interface
│   ├── api/                    # routers: entries, guiding_questions, insights, monthly_summary
│   ├── models/                 # SQLAlchemy models: Entry, GuidingQuestionAnswer, Feeling, Topic, Pattern
│   ├── schemas/                # Pydantic request/response schemas
│   ├── services/
│   │   ├── llm_client.py       # Claude API wrapper (feeling suggestion + pattern narration)
│   │   ├── feeling_service.py
│   │   ├── pattern_service.py  # recurrence-threshold filtering + LLM narration
│   │   └── summary_service.py  # monthly aggregation
│   └── db/                     # session, Alembic migrations
└── tests/
    ├── contract/                # request/response shape tests against api.md
    ├── integration/             # entry -> feeling -> pattern end-to-end flows
    └── unit/                    # pattern recurrence logic, topic extraction

android/
└── app/src/
    ├── main/kotlin/.../
    │   ├── ui/                  # Compose screens: TodayScreen, EntryComposer, GuidedQuestionFlow,
    │   │                        # InsightsScreen, MonthlyCalendarScreen, SettingsScreen (backend host)
    │   ├── data/                # Retrofit API client, repositories
    │   ├── notifications/       # AlarmManager scheduling + BroadcastReceiver for the 4 daily reminders
    │   └── domain/               # Kotlin data classes mirroring backend schemas
    ├── test/                     # JUnit unit tests (viewmodels, reminder scheduling logic)
    └── androidTest/              # Compose UI tests for entry + insights + calendar flows
```

**Structure Decision**: Mobile + API layout (Option 3): a `backend/` FastAPI service and an
`android/` native app, matching the spec's split between a self-hosted backend and an Android
client. No shared/common package is introduced — the two communicate only over the REST contract
in [contracts/api.md](./contracts/api.md), keeping them independently buildable/testable per the
spec's per-user-story independent-test requirement.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| Diary entry text is sent to a third-party LLM API (Claude), an exception to Principle IV's default of keeping diary content fully on-machine | Real-time, natural-language feeling suggestion (FR-007) and plain-language pattern narration (FR-010/FR-011) are core, spec-mandated capabilities; both need language understanding well beyond simple keyword matching | A fully local rule/keyword-based or local-ML approach (considered in research.md §4) was rejected: keyword matching can't reliably infer feeling from open-ended text or produce natural pattern explanations, and a local ML model adds real setup/maintenance burden for a solo-maintained app while still falling short of LLM-quality narration — see research.md for the full comparison |
