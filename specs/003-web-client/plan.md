# Implementation Plan: Mood Pattern Diary Web App

**Branch**: `003-web-client` | **Date**: 2026-07-28 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/003-web-client/spec.md`

## Summary

Add a browser client with full diary parity — capture, guided questions, feeling confirmation,
edit/delete, insights, monthly calendar — served as static assets by the existing FastAPI backend
under an `/app` prefix, so the phone and the computer talk to one address and one dataset.

Two things make this more than "another client". First, **FR-011/FR-022 require optimistic
concurrency across both clients**, which means a new `version` column on entries, a `409` conflict
response, and a small Android change — this feature touches backend, web, and Android. Second,
**constitution Principle VII (One Backend, Thin Clients)** forces the backend to start serving the
feeling set (`GET /feelings`), which closes the pre-existing deviation where the Android app
hardcodes it as a Kotlin enum.

## Technical Context

**Language/Version**: Backend: Python 3.11 (existing). Web: TypeScript 5.x on Node 20 LTS. Mobile:
Kotlin 2.1 (existing).

**Primary Dependencies**: Backend: FastAPI, SQLAlchemy 2.0, Alembic (all existing) — no new runtime
dependency. Web: Vite 6, React 18, React Router, plain CSS with custom properties (no UI/CSS
framework, no state-management library). Mobile: existing Retrofit/OkHttp stack, no new dependency.

**Storage**: Unchanged — SQLite on the backend host. One additive migration (`diary_entries.version`).
No browser-side persistence of any kind (FR-025).

**Testing**: Backend: pytest — contract tests for the new/changed endpoints, unit tests for the
version-conflict rule. Web: Vitest + React Testing Library for logic and component behavior
(conflict state machine, unsaved-change tracking, guided-question triggering). Mobile: existing
JUnit5 setup, extended for the 409 path. No browser E2E automation in v1 (see research.md §7).

**Target Platform**: Modern evergreen browsers (Chromium, Firefox, Safari) on desktop and mobile,
talking over the home LAN to the FastAPI service on the user's Linux machine. Android client
unchanged in platform terms.

**Project Type**: Multi-client + API — one backend, two clients (`android/`, new `web/`).

**Performance Goals**: First entry saved in under 30s and a second in under 15s (SC-001/SC-002),
which on a LAN is dominated by the Claude feeling-suggestion round trip, shown as a transient
"suggesting…" state exactly as the Android app does. Initial page load of the web app under 2s on
the LAN. Conflict detection adds no measurable latency (a single integer comparison).

**Constraints**: LAN-only, never exposed to the public internet (FR-016, constitution Product
Constraints). No diary content in addresses or persistent browser storage (FR-024/FR-025) — this
rules out a service worker, offline caching, and local drafts. No in-app authentication. Existing
Android API paths MUST keep working unchanged (FR-018), which constrains how the web app is routed.

**Scale/Scope**: Single user, single backend instance. 5 user stories, 27 functional requirements,
14 success criteria. Roughly 6 web screens plus a conflict-resolution view; one Alembic migration;
two new backend endpoints and a changed contract on two existing ones; one focused Android change.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Evaluated against constitution **v1.1.0** (amended 2026-07-28 to permit a web client and to add
Principle VII).

| Principle | Status | Notes |
|---|---|---|
| I. Spec-First Workflow | ✅ Pass | spec.md written, quality checklist 16/16, `/speckit-clarify` completed with 5 clarifications integrated. No code before this plan. |
| II. Simplicity & YAGNI | ✅ Pass | Still one user, one backend, no auth subsystem, no multi-tenancy. Web stack kept deliberately thin: no CSS framework, no state library, no E2E harness, no offline layer. Live-update push was explicitly rejected in the spec for exactly this reason. The one genuinely new thing — a Node build toolchain — is tracked below. |
| III. Deterministic Core, LLM at the Edges | ✅ Pass | No new LLM usage. Conflict detection is an integer comparison in backend code with unit tests; all counts/averages continue to come from the existing deterministic services. The web client computes no facts. |
| IV. Privacy by Architecture | ✅ Pass, strengthened | No new off-machine data flow — the web client triggers the same backend behavior, and the same previously-disclosed Claude exception applies unchanged. FR-024/FR-025 actively *tighten* privacy by keeping diary content out of browser history and local storage. Static assets are served from the user's own machine, not a CDN. |
| V. Test-First for Logic, Not for UI Polish | ✅ Pass | Mandatory-before-merge: version-conflict rule (unit), the two new endpoints and two changed contracts (contract tests). Exempt: web visual/interaction polish, per the principle's v1.1.0 wording that now covers any client UI. |
| VI. UX Bar: Fast and Pleasant | ✅ Pass | The conflict flow adds zero steps to the happy path — it only appears on rejection. FR-026's unsaved-change prompt is suppressed when there is nothing unsaved. SC-001/SC-002 carry the Android speed targets over unchanged. |
| VII. One Backend, Thin Clients | ✅ Pass, and closes a debt | The web client fetches feelings and guiding questions from the backend and computes no thresholds or aggregates. This feature also adds `GET /feelings` and migrates the Android app onto it, resolving `TODO(PRINCIPLE_VII_RECONCILIATION)` from the constitution's Sync Impact Report. |

**Gate result: PASS.** One item tracked in Complexity Tracking; no unjustified violations.

*Post-Phase-1 re-check*: Still passes. The Phase 1 design introduces no new persistent entity
(only an additive `version` column), no new external dependency for the backend, and no new
off-device data flow. `contracts/api.md` keeps every existing Android request shape valid, and the
`/app` mount prefix was chosen specifically so no existing API path changes meaning — both
Principle VII and FR-018 hold as designed.

## Project Structure

### Documentation (this feature)

```text
specs/003-web-client/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
│   └── api.md           # Delta against 002's contract: new + changed endpoints
├── checklists/
│   └── requirements.md  # Spec quality checklist (from /speckit-specify)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created here)
```

### Source Code (repository root)

```text
backend/
├── app/
│   ├── main.py                     # CHANGED: mount built web assets at /app
│   ├── api/
│   │   ├── entries.py              # CHANGED: expose version; require it on PATCH/DELETE; add GET /entries/{id}
│   │   └── feelings.py             # NEW: GET /feelings (Principle VII)
│   ├── models/entry.py             # CHANGED: version column
│   ├── schemas/
│   │   ├── entry.py                # CHANGED: version in/out
│   │   └── feeling.py              # NEW
│   ├── services/entry_service.py   # CHANGED: version check + bump, StaleEntryError
│   └── db/
├── alembic/versions/               # NEW: add_entry_version migration
└── tests/
    ├── contract/                   # NEW: test_feelings.py, test_entries_get.py; CHANGED: update/delete
    └── unit/                       # NEW: test_version_conflict.py

web/                                # NEW — the browser client
├── index.html
├── package.json, vite.config.ts, tsconfig.json
└── src/
    ├── main.tsx, App.tsx           # app shell + routes under /app
    ├── api/                        # fetch wrappers mirroring contracts/api.md; ApiResult + 409 mapping
    ├── domain/                     # TS types mirroring backend schemas (no rules, no thresholds)
    ├── screens/                    # Today, Composer, GuidedFlow, EntryDetail, Conflict, Insights, Calendar
    ├── components/                 # FeelingChips, EntryCard, PatternCard, CalendarGrid, RefreshButton
    ├── hooks/                      # useUnsavedGuard (FR-026), useRefreshable (FR-019)
    └── styles/                     # design tokens mirroring the Android Material 3 palette
web/tests/                          # Vitest + React Testing Library

android/
└── app/src/main/kotlin/com/moodpatterndiary/app/
    ├── data/                       # CHANGED: send version on PATCH/DELETE; map 409; FeelingApi
    ├── domain/Feeling.kt           # CHANGED: fetched from backend; emoji stays client-side
    └── ui/EntryDetailScreen.kt     # CHANGED: conflict outcome (FR-022/FR-023)
```

**Structure Decision**: A third top-level `web/` directory alongside the existing `backend/` and
`android/`, mirroring how those two are already laid out — self-contained, independently buildable,
communicating with the backend only over the REST contract in
[contracts/api.md](./contracts/api.md). No shared/common package is introduced between clients;
duplicating a handful of TypeScript type declarations is cheaper than coupling a Kotlin and a
TypeScript build together, and Principle VII already prevents the duplication that actually matters
(rules and computed facts, which live only in the backend).

The web client's built assets are served by the existing FastAPI process under `/app`, so there is
one process, one address, and no CORS. The prefix is load-bearing: the SPA's own routes would
otherwise collide with live API paths such as `/insights` and `/entries`, and re-prefixing the API
to `/api` would break the shipped Android app in violation of FR-018. See research.md §2.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| A third build toolchain (Node 20 + Vite) enters a repo that currently builds with only Python and Gradle — added maintenance surface, against Principle II's instinct to keep the stack boring | FR-001 requires a browser client with full parity, and FR-015/FR-014/FR-027 require a modern, responsive, keyboard-operable, accessible UI. A composer with live guided-question triggering, a conflict-resolution view, and a calendar is genuinely interactive; there is no way to deliver it without *some* web build step | Server-rendered Jinja2 templates + HTMX (research.md §1) would avoid Node entirely and was seriously considered — rejected because the unsaved-change guard (FR-026), the side-by-side conflict view (FR-023), and keyboard-only completion of the composer (FR-014) all need real client-side state, which HTMX only approximates with escalating awkwardness. A no-build vanilla-JS SPA was also rejected: it removes the toolchain but re-adds the same complexity by hand, with worse a11y defaults and no type checking across the API boundary |
