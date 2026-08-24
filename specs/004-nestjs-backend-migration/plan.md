# Implementation Plan: Re-platform the Backend onto NestJS

> **⚠️ Superseded in part (2026-07-29).** The Python backend was deleted, the differential test
> strategy was dropped, and the deliberately-ported topic-matching defect was fixed — because the
> **spec**, not the previous implementation, is the source of truth. The new backend now lives at
> `backend/`. Read the **Outcome** section at the top of [spec.md](./spec.md) before relying on
> anything here.

**Branch**: `004-nestjs-backend-migration` | **Date**: 2026-07-28 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/004-nestjs-backend-migration/spec.md`
## Summary

Re-implement the existing FastAPI backend as a NestJS service that reads the **same untouched SQLite
file** and serves the **same frozen HTTP contract**, so neither client is modified and no data is
converted. The old backend stays in the repo, runnable, until the new one is trusted.

The engineering problem here is not "write a NestJS app". It is **byte-level fidelity at two
boundaries**: the shape of values already on disk, and the shape of values already on the wire. Both
were produced by Python defaults that Node does not share, and both are consumed by an installed
Android app that cannot be patched. The whole plan is organised around that.

## Technical Context

**Language/Version**: TypeScript 5.x on Node 20 LTS (matching the toolchain the web client already
uses). Replaces Python 3.11.

**Primary Dependencies**: NestJS 11 (`@nestjs/common`, `@nestjs/core`, `@nestjs/platform-express`),
`better-sqlite3` for storage access, `@anthropic-ai/sdk` for feeling suggestion and pattern
narration, `zod` for request validation. Deliberately **no ORM** — see research.md §2.

**Storage**: The existing SQLite file, unchanged. No schema management, no migrations, no
schema-sync. The `alembic_version` table is read-only ballast the new backend must not touch.

**Testing**: Vitest (same runner as the web client, one test command shape across the repo). The 71
existing pytest cases are the porting checklist and the definition of done for FR-012.

**Target Platform**: One Node process on the user's own Linux machine, bound to the LAN, also
serving the built web client at `/app` — identical deployment shape to today.

**Performance Goals**: No user-perceptible regression (SC-007). Entry save stays dominated by the
Claude call; day/month/insights reads stay well under a second on a diary of low thousands of
entries.

**Constraints**: The HTTP contract is frozen (FR-005) — same paths, shapes, status codes, error
codes, and datetime formatting. The stored file must not be modified by merely running the new
backend (FR-022). No new service, no second process (FR-016). LAN-only, no auth (FR-015).

**Scale/Scope**: Single user, single instance. 32 Python modules and 71 tests to replace; 8 tables;
6 endpoint groups; roughly 1,700 lines of application code.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Evaluated against constitution **v1.1.0**. No amendment is required — the constitution constrains the
system's shape, not its implementation language.

| Principle | Status | Notes |
|---|---|---|
| I. Spec-First Workflow | ✅ Pass | spec.md written and validated 16/16, one clarification resolved, no code before this plan. |
| II. Simplicity & YAGNI | ⚠ **Tension, accepted and recorded** | Replacing a working, fully tested backend is not something a current requirement demands — the spec's "Cost and constitutional tension" section states this plainly rather than arguing it away. The principle governs choices *within* a feature, and the maintainer is entitled to choose the stack they maintain. The plan then applies Principle II hard *inside* the feature: no ORM, no migration framework, no DI ceremony beyond Nest's defaults, no new service, no data conversion. See Complexity Tracking. |
| III. Deterministic Core, LLM at the Edges | ✅ Pass | Pattern detection, the occurrence threshold, topic extraction, aggregation and the conflict rule all stay ordinary unit-tested code. Claude keeps exactly its current two jobs. Porting must not "improve" any of it — FR-011/SC-002 require identical output. |
| IV. Privacy by Architecture | ✅ Pass | No new destination for diary content. Same single Claude exception, already disclosed in 002. Storage stays on the user's disk in the same file. |
| V. Test-First for Logic, Not for UI Polish | ✅ Pass | FR-012/SC-006 require equivalent coverage of every correctness-gating rule before the switch. The port is genuinely test-first: the behaviours are already pinned by 71 existing cases, so each is written against the new backend before its implementation. |
| VI. UX Bar: Fast and Pleasant | ✅ Pass | SC-007 forbids a perceptible slowdown; nothing in the entry flow gains a step. |
| VII. One Backend, Thin Clients | ✅ Pass, and load-bearing | A frozen contract is what lets both clients stay untouched. The feeling set and guiding questions continue to be served, not hardcoded. Replacement rather than parallel-run is explicitly chosen so there is never more than one backend over one diary. |

**Gate result: PASS**, with the Principle II tension recorded rather than dismissed.

*Post-Phase-1 re-check*: Still passes. Phase 1 adds no entity, no endpoint, no dependency beyond the
four listed, and no off-machine data flow. The contract in `contracts/api.md` is a *fidelity
specification* — it adds nothing, it pins down what already exists.

## Project Structure

### Documentation (this feature)

```text
specs/004-nestjs-backend-migration/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output — storage fidelity, not new modelling
├── quickstart.md        # Phase 1 output — differential validation against the old backend
├── contracts/
│   └── api.md           # Phase 1 output — byte-level fidelity spec for the frozen contract
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── tasks.md             # Phase 2 output (/speckit-tasks — NOT created here)
```

### Source Code (repository root)

```text
backend/                 # UNCHANGED. Stays runnable until the new backend is trusted (FR-019),
                         # and is the reference implementation for every differential test.

backend/            # NEW
├── package.json, tsconfig.json, nest-cli.json, vitest.config.ts
└── src/
    ├── main.ts                     # bootstrap: LAN bind, /app static + SPA fallback, no-store
    ├── app.module.ts
    ├── db/
    │   ├── database.ts             # better-sqlite3 handle, opened read/write, NO schema management
    │   ├── codecs.ts               # ⚠ datetime/date/JSON encode+decode matching Python byte-for-byte
    │   └── seed.ts                 # idempotent: only inserts when the table is empty
    ├── entries/                    # controller + service + repository
    ├── feelings/
    ├── guiding-questions/
    ├── insights/                   # pattern detection (deterministic) + narration
    ├── monthly-summary/
    ├── topics/                     # keyword extraction — ported behaviour-identical, bug included
    ├── llm/                        # Anthropic client + the no-API-key deterministic fallback
    └── common/
        ├── http-exception.filter.ts  # the {"error":{code,message}} envelope
        └── stale-entry.ts            # the 409 body with its `current` sibling key

web/                     # UNCHANGED
android/                 # UNCHANGED
```

**Structure Decision**: The new backend lands in a **sibling `backend/` directory** rather than
replacing `backend/` in place. This is what makes FR-017 (reversible) and FR-019 (previous backend
stays runnable) true by construction rather than by discipline, and it is what enables the
differential testing the whole plan depends on: both backends can be pointed at copies of the same
diary and their responses compared directly. Renaming `backend/` → `backend/` is a separate,
deliberate step taken only after the switch is trusted — deliberately *not* part of this feature.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| A whole working backend is replaced with no user-visible gain, against Principle II's instinct to leave the boring, working thing alone | The maintainer will live with this codebase and wants one language across backend and browser client (spec US4). Principle II governs design choices within a feature; which stack the sole maintainer maintains is theirs to choose | **"Do nothing" is the genuinely simpler option and is recorded in the spec as consciously rejected, not overlooked.** The two-language cost falls on one person and is only paid when a change spans both sides — which has happened once in this project's life. If the cost of this feature turns out to exceed that, abandoning it part-way is a legitimate outcome; `backend/` is untouched throughout precisely so that stays possible |
| Two backends coexist in the repository for the duration | FR-017/FR-019 require the old one runnable for rollback, and every fidelity test is differential — it needs both sides running to compare | Deleting Python as the first step would make "is the new one identical?" unanswerable, and would turn any regression into an unrecoverable one. The coexistence is explicitly temporary and its removal is out of scope for this feature |
| Hand-written storage access instead of an ORM | FR-022 forbids modifying the stored file, and every mainstream Node ORM's default posture is to own the schema — synchronize, migrate, or "push" it. Opting all of that off is more fragile than never having it | See research.md §2. An ORM was seriously considered and rejected on exactly one criterion: the failure mode of a mis-set flag is silent, irreversible damage to the user's diary, which is the one thing this feature must not risk |
