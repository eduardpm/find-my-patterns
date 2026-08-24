<!--
Sync Impact Report
- Version change: 1.1.0 → 1.2.0 (MINOR)
- Bump rationale: public access through an authenticated outbound tunnel is now an explicit,
  narrowly bounded deployment option. This materially expands Product Constraints without
  removing or reversing a Core Principle.
- Bump rationale: a new principle (VII) is added and the Product Constraints section is materially
  expanded. Per this constitution's own versioning policy, MAJOR is reserved for "a principle is
  removed or reversed in meaning"; the client-platform change edits a Product Constraint via the
  amendment escape hatch that clause explicitly provided ("unless a future amendment changes
  this"), and no Core Principle is removed or reversed.
- Modified principles:
  - V. Test-First for Logic, Not for UI Polish — scope generalized from "the Android UI" to any
    client UI (Android or web). No change to what is gated; only which clients it covers.
- Added principles:
  - VII. One Backend, Thin Clients
- Modified sections:
  - Product Constraints — replaced the LAN-only/public-exposure prohibition with an authenticated
    reverse-tunnel exception and made in-app authentication mandatory on the public hostname.
  - Product Constraints — "Client platform: Android only for v1" replaced with "Client platforms:
    Android app and web app"; added an explicit LAN-only/no-public-exposure constraint for the web
    client; generalized the no-in-app-auth clause from "device lock" to any client device's lock.
- Removed sections: none
- Templates requiring updates:
  - .specify/templates/tasks-template.md — ✅ updated (Principle V note generalized from "Android
    UI layout/motion/theming" to client UI, Android or web)
  - .specify/templates/plan-template.md — ✅ reviewed, no change required (Constitution Check reads
    gates dynamically from this file; its Android/iOS mentions are generic layout examples)
  - .specify/templates/spec-template.md — ✅ reviewed, no change required
  - .specify/templates/checklist-template.md — ✅ reviewed, no change required
  - .claude/skills/speckit-*/SKILL.md — ✅ reviewed, all reference constitution.md dynamically; no
    hardcoded principle content to update
  - No README.md/CLAUDE.md exists at the repo root; backend/README.md and android/README.md carry
    run instructions only, no principle references — ✅ no change required
- Resolved from v1.0.0's report:
  - specs/002-mood-pattern-diary-mobile/plan.md's Constitution Check has since been re-checked
    against v1.0.0 — that follow-up TODO is closed.
  - PRINCIPLE_VII_RECONCILIATION is closed by 003-web-client T044/T045. The Android
    domain/Feeling.kt enum is gone; the feeling set's keys, labels and valences now come from
    `GET /feelings` via data/FeelingApi.kt, so both clients source them from the backend. Only
    emoji and accent colors remain client-side, and those are presentation the backend
    deliberately does not serve.
- Follow-up TODOs:
  - specs/002-mood-pattern-diary-mobile/plan.md was gated against v1.0.0 and does not evaluate
    Principle VII. Per Amendment reconciliation it is not retroactively blocked; reconcile at its
    next /speckit-plan or /speckit-tasks run if one occurs.
-->

# Mood Pattern Diary Constitution

## Core Principles

### I. Spec-First Workflow

Every feature MUST progress through the Spec Kit lifecycle — spec → plan → tasks → implement —
via the corresponding `/speckit-*` commands. No implementation code MUST be written before a
corresponding `spec.md` exists and has passed its quality checklist, and no task MUST begin
execution before it exists in an approved `tasks.md`.

**Rationale**: This is a solo project where the spec is the only durable record of intent and
rationale. Skipping stages silently erodes that record and leaves future work (including future
you) guessing at decisions instead of reading them.

### II. Simplicity & YAGNI

The system MUST be designed for exactly one user and one backend instance. Multi-tenancy, user
accounts/roles, horizontal scaling, and speculative extension points MUST NOT be introduced unless
a spec explicitly requires them. When a design choice could be solved with a direct, boring
implementation or a more general/abstracted one, the direct implementation MUST be chosen unless
current requirements demand the general one.

**Rationale**: Solo-maintained personal software accumulates cost fastest through unused
generality. Every abstraction must earn its place against a concrete, current requirement, not a
hypothetical future one.

### III. Deterministic Core, LLM at the Edges

Any logic that gates correctness or that the app presents as a factual claim to the user (e.g.,
"this pattern occurred 4 times," minimum-occurrence thresholds, feeling counts and averages) MUST
be implemented as deterministic, unit-testable code. LLM calls (via the Claude API) MAY be used
only for suggestion, narration, or inference — proposing a feeling, phrasing a pattern's
description, wording a suggestion — and MUST NOT be the sole authority for whether a rule was
satisfied or a count is correct.

**Rationale**: LLM output is not reproducible or independently verifiable. Using it to decide facts
the app asserts to the user would make the app's core promise — accurate, trustworthy
pattern-finding — untestable and unreliable.

### IV. Privacy by Architecture

All diary content MUST be stored only on a backend the user runs and controls themselves; no diary
content MUST be persisted in third-party or cloud storage. Any dependency or integration that would
transmit diary content off the user's own machine (including LLM API calls) MUST be explicitly
called out in the relevant spec's Assumptions and justified there — it is never an implicit
default.

**Rationale**: This is a personal diary containing sensitive reflections. Privacy is a product
requirement, not an afterthought, and every exception to "stays on my machine" deserves a visible
decision trail.

### V. Test-First for Logic, Not for UI Polish

Pattern-detection logic, feeling/topic aggregation, and API contract behavior MUST have tests
written before that code is merged, and those tests MUST fail prior to implementation. Visual and
interaction polish on any client UI — Android or web — (layout, motion, theming) is exempt from
this requirement and MAY be iterated on without tests blocking merges.

**Rationale**: Correctness of the pattern engine and API is the app's core value and must be
verifiable independent of how it looks. UI feel is inherently iterative and subjective, and
test-gating it would slow down the exact area the product needs to keep fast and pleasant. The
exemption is about the *kind* of work (visual polish), not the platform, so it applies equally to
every client.

### VI. UX Bar: Fast and Pleasant Over Feature-Complete

When a tradeoff arises between adding capability and keeping entry creation fast and frictionless,
speed and pleasantness of the writing experience MUST win. Any change that adds a required step,
field, or delay to the core entry-creation flow MUST be justified against the app's stated success
criteria (e.g., time-to-first-entry, time-to-second-entry) before being accepted. This bar applies
to every client independently — a client that is slower or clumsier to write in than another does
not meet it.

**Rationale**: Writing friction is the single biggest risk to the app's data supply — pattern
detection only works if entries keep getting written, so writing speed is a load-bearing constraint
on the app's central purpose, not a nice-to-have.

### VII. One Backend, Thin Clients

Every client — the Android app, the web app, and any client added later — MUST be a presentation
layer over the single self-hosted backend. The feeling set, the guiding-question library, the
minimum-occurrence threshold, topic extraction, pattern detection, and all counts and averages MUST
be defined and computed in the backend only and served to clients. A client MUST NOT hardcode,
duplicate, or independently recompute any of them. Clients MAY own purely presentational concerns
locally — icons, emoji, ordering, animation, layout, and the wording of their own UI chrome. Given
identical backend data, all clients MUST present identical facts; where they disagree, the backend
is authoritative and the client is wrong.

**Rationale**: A second client doubles the number of places a rule can live, and duplicated rules
drift silently — a threshold changed in one place, a feeling added in another, and the app starts
telling the user two different stories about their own life. That directly attacks the product's
core promise of trustworthy pattern-finding (Principle III) and is far cheaper to prevent by rule
than to detect later by noticing two screens disagree.

## Product Constraints

- **Single-user, self-hosted only**: no multi-user accounts and no cloud-hosted backend option are
  in scope for the lifetime of this constitution version (see Principles II and IV).
- **Client platforms**: an Android app and a web app, both thin clients of the one self-hosted
  backend (see Principle VII). No iOS client and no desktop-native client is in scope unless a
  future amendment changes this.
- **Private by default, authenticated tunnel as the only public option**: clients MAY remain
  LAN/VPN-only without in-app authentication. Public web access is permitted only through an
  outbound reverse tunnel whose public hostname is protected by the backend's authentication;
  direct router port-forwarding and a publicly routable origin remain forbidden. An identity-aware
  proxy such as Cloudflare Access SHOULD provide an additional outer authorization layer.
- **Single-user authentication**: authentication on a public hostname MUST protect both the web
  shell and every diary API route, use a slow password hash and an HttpOnly secure session cookie,
  throttle failed logins, and fail closed when enabled with incomplete configuration. The public
  hostname MAY be protected without forcing authentication on direct LAN clients, provided the
  origin is reachable from the public internet only through the configured tunnel.

## Development Workflow

- **Solo review in lieu of peer review**: each feature's implementation MUST be checked against
  its own `spec.md` and this constitution before being marked complete — a self-review checklist,
  not a formal PR gate.
- **Quality gates**: a feature MUST NOT be marked done if (a) any Principle III "deterministic
  core" logic lacks tests, or (b) that feature's `quickstart.md` validation has not been walked
  through manually at least once.
- **Cross-client parity check**: a feature that touches more than one client MUST NOT be marked
  done until the same data has been viewed on every affected client and confirmed to present the
  same facts (Principle VII).
- **Amendment reconciliation**: amendments to this constitution take effect immediately for new
  work; already-planned features are not retroactively blocked but SHOULD be reconciled with the
  new principles at their next `/speckit-plan` or `/speckit-tasks` run.

## Governance

This constitution supersedes any conflicting ad-hoc practice. Amendments are made via
`/speckit-constitution` and MUST include: the specific principle text changed, a version bump per
the semantic versioning policy below, and an updated Sync Impact Report. Since this is a solo
project, "approval" is the user's explicit confirmation of the amendment; no separate review board
exists.

**Versioning policy**: MAJOR — a principle is removed or reversed in meaning. MINOR — a new
principle or materially expanded section is added. PATCH — wording/clarification fixes with no
rule change.

**Compliance review**: every `/speckit-plan` run MUST re-evaluate the Constitution Check gate
against the current version of this file; any unjustified violation blocks progressing to Phase 0
research.

**Version**: 1.2.0 | **Ratified**: 2026-07-27 | **Last Amended**: 2026-08-14
