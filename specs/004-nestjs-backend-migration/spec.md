# Feature Specification: Re-platform the Backend onto NestJS

**Feature Branch**: `004-nestjs-backend-migration`

**Created**: 2026-07-28

**Status**: Implemented, then amended — see **Outcome** below

**Input**: User description: "I'd like to use nestjs on the backend, instead if python"

> ## ⚠️ Outcome (2026-07-29) — read this before anything below
>
> The feature was implemented, and then its **central premise was corrected by the user**. Parts of
> this spec, and more of the plan and research, no longer describe the system. They are kept as the
> record of what was decided and why it changed, not as instructions.
>
> **What changed:**
>
> 1. **The Python backend was deleted outright.** The original request said "instead of python", and
>    this spec softened that into coexistence — FR-019 required the previous backend to stay runnable.
>    That was never asked for. `backend/` is now the NestJS service; there is no second backend, no
>    cutover, and no rollback path. **FR-019 and User Story 5 are void.**
> 2. **The spec is the source of truth, not the previous implementation.** This spec treated the
>    Python code as the system of record and required byte-identical behaviour (FR-011, SC-002,
>    SC-005). That was the wrong authority. Those requirements are **void as written** — the correct
>    standard is conformance to specs 002 and 003.
> 3. **The differential test suite was removed.** It compared the two implementations, which only
>    made sense under the mistaken premise. Testing is now spec-derived; see `backend/tests/TESTING.md`.
> 4. **The deliberately-ported topic-matching defect was fixed.** Substring matching recorded the
>    topic *exercise* for "I drank water". Spec 002 FR-009 asks for topics *mentioned* in the entry,
>    so the old behaviour was a spec violation and preserving it was a mistake. Matching is now on
>    whole words. The diary was empty at the time, so no stored insight changed.
> 5. **The diary moved to `data/diary.db`**, out of the backend directory that was being replaced.
>
> **What survived intact:** the API contract (an installed Android client parses it), the storage
> schema, the version/409 concurrency protocol, `GET /feelings`, the compatibility check (FR-018),
> and the no-DDL / no-write-on-startup guarantees (FR-020/FR-022).
>
> The framing below — "continuity and provable equivalence" — is the framing that was corrected.
> Read it as history.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - My diary survives the change completely (Priority: P1)

The person using the diary opens their phone or browser after the switch and finds everything exactly
as they left it: every entry they have ever written, the feelings attached to them, the patterns the
app had detected, and their monthly history. They did not reinstall the Android app, did not
reconfigure its backend address, and did not export or re-import anything.

**Why this priority**: This is the entire risk of the feature. A re-platform that loses a month of
someone's diary has failed no matter how clean the new code is, and diary content is not
reconstructible — there is no upstream copy to restore from. Nothing else in this spec matters if
this does not hold.

**Independent Test**: Record the full contents of the diary before the switch — every entry, its
feeling, the detected patterns, and a month's totals. Perform the switch. Read them all back from
both clients and confirm they are identical, without having touched either client.

**Acceptance Scenarios**:

1. **Given** a diary with existing entries, **When** the new backend is in place, **Then** every entry appears with the same text, timestamp, day, feeling, and feeling source as before.
2. **Given** entries created through the guided flow, **When** they are viewed after the switch, **Then** their individual question answers are still attached and still readable.
3. **Given** patterns the app had already detected, **When** the user opens Insights, **Then** the same patterns appear with the same occurrence counts.
4. **Given** a month of history, **When** the user opens the monthly view, **Then** the per-feeling totals and the daily average are unchanged.
5. **Given** the installed Android app and the browser client, **When** the backend is replaced, **Then** both keep working with no reinstall, no rebuild, and no change to the address the user configured.

---

### User Story 2 - The new backend is provably equivalent, not assumed equivalent (Priority: P2)

Before the switch is considered done, the behaviour the old backend guaranteed is demonstrated on
the new one: the rules that decide when a pattern is real, how feelings are counted, how averages
are computed, and how a conflicting edit is refused.

**Why this priority**: The current backend's correctness is not obvious from reading it — it is
pinned down by tests covering the recurrence threshold, the version-conflict rule, and cross-client
consistency. Re-implementing the code without re-establishing those guarantees would leave the app's
central promise (trustworthy pattern-finding) resting on nothing. This ranks directly below data
survival because a subtly wrong backend corrupts the diary more slowly but just as surely.

**Independent Test**: Run the new backend's test suite and confirm it covers every rule the old
suite covered — minimum-occurrence threshold, conflict rejection semantics, monthly aggregation,
feeling-source transitions — and that each previously-passing behaviour still passes.

**Acceptance Scenarios**:

1. **Given** the deterministic rules the old backend enforced, **When** the new backend is tested, **Then** each rule has at least equivalent test coverage and passes.
2. **Given** the same set of entries, **When** pattern detection runs on old and new, **Then** both produce the same patterns with the same occurrence counts and directions.
3. **Given** a request that the old backend rejected, **When** the same request is made to the new one, **Then** it is rejected the same way with the same status and the same error shape.
4. **Given** identical stored data, **When** the monthly summary is requested, **Then** old and new return identical totals and the identical daily average.

---

### User Story 3 - Both clients keep working without being touched (Priority: P3)

The Android app and the web client continue to talk to the backend exactly as before. No client code
changes, no new app release, no rebuild of the web bundle.

**Why this priority**: The clients are the reason the backend exists, and one of them is an installed
Android app that cannot be silently updated. Any contract drift shows up as a broken phone. It ranks
below Story 2 only because a contract break is loud and immediate, whereas a wrong pattern rule is
quiet.

**Independent Test**: Point the existing, unmodified Android app and the existing, unmodified web
build at the new backend and walk through writing an entry, confirming a feeling, editing it,
deleting it, viewing insights, and viewing the month — on both clients.

**Acceptance Scenarios**:

1. **Given** the unmodified Android app, **When** it is pointed at the new backend, **Then** every screen works and no request fails.
2. **Given** the unmodified web client build, **When** it is served by the new backend, **Then** every screen works and the browser app is still reachable at the same address as before.
3. **Given** an entry edited from a stale view, **When** the new backend receives it, **Then** it is refused with the same conflict response the clients already know how to handle.
4. **Given** either client, **When** it requests the feeling set or the guiding questions, **Then** it receives the same set it received before.

---

### User Story 4 - The maintainer works in one language (Priority: P4)

The person maintaining the project stops switching between two languages and two toolchains when
making a change that touches both the backend and the browser client.

**Why this priority**: This is the actual motivation for the feature, but it is a benefit to exactly
one person and delivers nothing to the diary itself, so it must not be bought at the cost of Stories
1–3. It is listed to make the goal explicit rather than to imply it justifies risk.

**Independent Test**: Make a small change spanning the API contract and the browser client, and
confirm it can be done and verified in one language with one test command per side.

**Acceptance Scenarios**:

1. **Given** a change to the API contract, **When** the maintainer updates the backend and the web client, **Then** both are written in the same language.
2. **Given** the project after the switch, **When** the maintainer runs the backend's checks, **Then** the commands and tooling match the ones already used for the web client.

---

### User Story 5 - The switch can be undone (Priority: P5)

If the new backend misbehaves after the switch, the maintainer can return to the previous working
backend and to their diary as it was, without data loss.

**Why this priority**: A safety net rather than a capability. It matters most in the hours around the
cutover and stops mattering once the new backend has been trusted for a while.

**Independent Test**: Perform the switch, then deliberately revert to the previous backend and
confirm the diary is intact and both clients work.

**Acceptance Scenarios**:

1. **Given** the switch has happened, **When** the maintainer reverts to the previous backend, **Then** the diary is intact and both clients work.
2. **Given** entries written *after* the switch, **When** a revert happens, **Then** the maintainer is told plainly whether those entries survive the revert.

---

### Edge Cases

- What happens to entries written on the phone during the cutover window, while the backend is being swapped?
- What happens if the stored data contains something the new backend reads differently — a date interpreted in another timezone, a null feeling, an entry whose text is empty?
- What happens if the two backends disagree about which calendar day a near-midnight entry belongs to? The existing data was written under the old interpretation.
- Since the stored data is kept untouched, what happens if the new backend's idea of the stored structure differs subtly from what is actually on disk — a column it expects to be non-empty, a type it reads differently? (FR-018 requires it to refuse to run rather than present a partial diary.)
- What stops the new backend from "helpfully" adjusting the stored structure on startup, the way many data-layer tools do by default? FR-022 forbids it, but it is the most likely way this feature could quietly damage the diary.
- What happens to patterns that were detected under the old backend if the new one's detection produces a slightly different set on first run — does the user see their insights change for no reason they can perceive?
- How does the user find out the switch happened at all, if something does go visibly wrong?
- What happens to the phrasing of already-stored pattern narratives and suggestions, which were generated by a language model and stored as text?
- Does the browser client remain reachable at the same address during and after the switch?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST preserve every existing diary entry — text, timestamp, calendar day, feeling, and feeling source — across the change, with no user action required.
- **FR-002**: The system MUST preserve the individual answers attached to entries created through the guided flow.
- **FR-003**: The system MUST preserve the detected patterns, their supporting entries, their occurrence counts, and their stored narrative and suggestion text.
- **FR-004**: The system MUST continue to serve the same feeling set and the same guiding-question library, with the same identifiers, so stored entries still resolve to the right feeling.
- **FR-005**: The system MUST keep the existing interface between backend and clients unchanged — same addresses, same request shapes, same response shapes, same error shapes, same status codes — including the conflict response introduced for concurrent edits.
- **FR-006**: The Android app and the web client MUST continue to work without any code change, rebuild, reinstall, or reconfiguration by the user.
- **FR-007**: The browser client MUST continue to be served by the backend at the same address as before.
- **FR-008**: The system MUST continue to enforce the minimum-occurrence rule before presenting a pattern, with the same threshold.
- **FR-009**: The system MUST continue to refuse a change based on an out-of-date view, and MUST leave the stored entry untouched when it does.
- **FR-010**: The system MUST produce identical monthly per-feeling totals and identical daily averages for identical stored data.
- **FR-011**: The system MUST produce the same detected patterns, counts, and keep/change directions as the previous backend for the same stored data.
- **FR-012**: Every rule that gates correctness — the occurrence threshold, the conflict rule, feeling-source transitions, and the aggregation rules — MUST be covered by tests on the new backend before the switch is considered complete.
- **FR-013**: The system MUST continue to keep all diary content on the machine the user runs it on, with no new destination for diary content beyond the language-model calls already disclosed.
- **FR-014**: The system MUST continue to suggest a feeling for a new entry and to phrase detected patterns in plain language, as it does today.
- **FR-015**: The system MUST continue to be usable only on the user's own network and MUST NOT become reachable from the public internet as a result of this change.
- **FR-016**: The system MUST continue to run as a single process the user starts on their own machine, with no additional service to run or manage.
- **FR-017**: The switch MUST be reversible: the maintainer MUST be able to return to the previous backend with the diary intact, and MUST be told plainly what happens to any entries written after the switch.
- **FR-018**: The system MUST detect and refuse to run against data it cannot fully interpret, rather than starting up and silently presenting an incomplete diary.
- **FR-019**: The previous backend MUST remain available and runnable until the new one has been confirmed working, and MUST NOT be deleted as part of the switch itself.
- **FR-020**: The system MUST keep the existing on-disk storage exactly as it is. The storage engine MUST NOT change, existing data MUST NOT be transformed, converted, exported, or re-imported, and backing up the diary MUST remain a matter of copying a single file.
- **FR-021**: The system MUST adopt the existing stored structure as it stands, including the per-entry revision marker added for concurrent-edit protection, without re-creating or re-versioning it and without requiring the user to run any conversion step before or after the switch.
- **FR-022**: The system MUST leave the stored data byte-for-byte unchanged except for writes the user themselves causes. Merely starting the new backend against an existing diary MUST NOT modify it.

### Key Entities *(include if data involved)*

This feature introduces **no new entities and changes no existing one**. Diary Entry, Guiding
Question and its Answers, Feeling, Topic, Pattern, and the derived Monthly Summary all keep their
current meaning, their current relationships, and their current identifiers. That is the requirement,
not an incidental fact: the stored diary must be readable by the new backend without transformation
of its meaning.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of entries that existed before the switch are readable afterwards, with identical text, timestamp, day, and feeling.
- **SC-002**: 100% of previously detected patterns appear afterwards with the same occurrence counts.
- **SC-003**: For every month with existing data, the per-feeling totals and the daily average are identical before and after.
- **SC-004**: Both clients complete every one of their user journeys against the new backend with zero changes to either client.
- **SC-005**: For an identical set of requests, the new backend returns responses indistinguishable from the old one — same shapes, same status codes, same error codes.
- **SC-006**: Every correctness-gating rule covered by tests today is covered by tests on the new backend, and all of them pass.
- **SC-007**: Saving an entry and loading a day, a month, and the insights view are each no slower than before, as experienced by the user.
- **SC-008**: The user completes the switch without exporting, importing, reinstalling, or reconfiguring anything.
- **SC-009**: A revert to the previous backend restores a fully working diary within 15 minutes, with no data conversion required in either direction.
- **SC-010**: No diary content reaches any destination it does not reach today.
- **SC-011** *(corrected 2026-07-28 — see below)*: Starting the new backend against an existing diary and exercising every **read-only** endpoint leaves the stored data unchanged — a before-and-after comparison of the stored file shows no difference.

> **Correction: SC-011 originally said "reading every screen".** That is not achievable while
> satisfying SC-002, and the conflict was found during `/speckit-tasks` by measuring rather than
> assuming: hashing the diary, issuing one further `GET /insights` with no data change, and
> re-hashing produces a different digest. `recompute_patterns()` runs on every read of that endpoint
> and rewrites `pattern_entries`.
>
> So `/insights` **writes on read in both backends**. A port that made it read-only would have
> changed behaviour and broken FR-011/SC-002. FR-022's real intent — that *merely starting up*
> (connecting, checking compatibility, seeding) must not touch the diary — is preserved and tested.
> `/insights` is verified **differentially** instead: both backends must write the same thing.
>
> Recorded rather than quietly reinterpreted, because as originally written this criterion would
> either fail or push an implementer into "fixing" `/insights` and silently changing the user's
> insights.

## Assumptions

- **No constitution amendment is required.** The constitution (v1.1.0) constrains the *shape* of the system — single user, self-hosted, LAN-only, deterministic core, thin clients — but names no language or framework for the backend. This differs from the web-client feature, which needed an explicit amendment. Every principle continues to apply unchanged to the new backend.
- **The interface to the clients is frozen for this feature.** No endpoint is added, removed, renamed, or reshaped. A re-platform that also changes the contract would make it impossible to tell a migration bug from a design change.
- **The stored diary is not migrated at all** (decided 2026-07-28). The existing storage is kept exactly as it is and the new backend is written to read it as it stands. This deliberately keeps the feature a code change rather than a data migration: nothing reads, transforms and rewrites the user's entries, so the highest-stakes requirement — that every entry survives — is satisfied by construction rather than by a conversion step that has to be got right. It also means a revert is simply running the previous backend again against the same untouched file.
- **The clients are not touched at all** — no rebuild of the web bundle, no new Android release. If the change cannot be made without touching a client, that is a finding to raise, not a step to take quietly.
- **The deterministic core stays deterministic.** Pattern detection, the occurrence threshold, topic extraction, and all counts and averages remain ordinary application code with tests; the language model keeps its existing, narrow role of suggesting a feeling and phrasing a pattern.
- **Stored language-model text is carried over as-is.** Narratives and suggestions already generated are data, not something to regenerate — regenerating them would silently reword the user's insights.
- **The switch is a replacement, not a parallel deployment.** Running two backends against one diary would create exactly the split-brain the project's "one backend" principle exists to prevent.
- **The previous backend is kept in the repository until the new one is trusted**, then removed in a separate, deliberate step.
- **This is scoped to the backend only.** The Android app, the web client, and the API contract are all out of scope.
- **The work is a re-implementation, not a translation.** Behaviour is defined by the existing tests and the API contract, not by the shape of the current Python code.

## Cost and constitutional tension

Recorded here because a spec is the durable record of why something was done, and this feature's
justification is weaker than any other in this project:

- **What is being discarded**: a backend completed and verified days ago — 32 modules, 71 passing
  tests, a working pattern engine, a language-model integration, database migrations, and a
  concurrency protocol that was verified live against both clients.
- **What the diary user gains**: nothing. By design, the best possible outcome is that nobody
  notices.
- **Constitution Principle II (Simplicity & YAGNI)** says the direct, boring implementation must be
  chosen unless current requirements demand otherwise. A working backend is the boring option;
  replacing it is not something a current requirement demands. This does not forbid the work — the
  principle governs design choices within a feature, and the maintainer is entitled to choose the
  stack they will live with — but the tension is real and is recorded rather than argued away.
- **Constitution Principle V** requires the deterministic core to be test-covered before it is
  considered done; FR-012 and SC-006 carry that obligation onto the new backend in full.
- **A cheaper alternative exists** and should be consciously rejected rather than skipped: leave the
  backend alone. The two-language cost falls on one person and is paid only when a change spans both
  sides, which is rare — the API contract has changed once in the project's life.
