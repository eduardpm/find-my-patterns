<!--
Sync Impact Report
- Version change: 2.0.0 → 3.0.0 (MAJOR)
- Bump rationale: two principles are reversed in meaning, exactly as this constitution's own
  versioning policy defines MAJOR — "a principle is removed or reversed in meaning". Principle II
  forbade "diary data partitioned by owner, authorization roles, and any second person's account
  holding diary content" in as many words; v3.0.0 permits and, in the owner-operated managed
  shape, requires exactly that. Principle IV limited storage to "a datastore the user owns and
  administers"; v3.0.0 also permits a datastore the project owner operates on a paying customer's
  behalf. This ratifies the owner's 2026-08-29 hosting/monetization decision recorded in
  `specs/research/daylio-competitive-analysis.md` §11.2 and `specs/research/unified-backlog.md`,
  and unblocks the tickets built to implement it (#45, #46, #47, #48) and the privacy-copy rewrite
  that depends on the resulting guarantee (#49).
- Modified principles:
  - II. Simplicity & YAGNI — reversed. Previously: per-user data partitioning, authorization
    roles, and a second person's account holding diary content were forbidden outright. Now: the
    owner-operated managed shape MAY serve more than one paying customer, and doing so permits —
    and requires — per-customer data partitioning and authorization sufficient that one customer's
    session can reach only that customer's own diary content. The YAGNI spirit is kept by drawing
    the boundary tight: nothing beyond that single isolation guarantee is licensed — no roles, no
    permission levels, no delegated or shared access to another person's content. The self-hosted
    shape is unaffected; it remains single-user.
  - IV. Privacy by Architecture — reversed on storage, preserved and strengthened on processing.
    Storage boundary widened from "a datastore the user owns and administers" to also permit "a
    datastore the project owner operates on a customer's behalf" in the managed shape — the
    change #46/#47 need to exist at all. Encryption-at-rest brought in line with reality instead of
    stating a MUST the code does not meet: the backend stores diary content in a plain, unencrypted
    SQLite file (`backend/src/config.ts`, `backend/src/db/database.ts`, confirmed by inspection —
    no SQLCipher or equivalent is wired up); that is now recorded as a known gap and downgraded
    from MUST to SHOULD for the self-hosted shape, while encryption at rest becomes a hard MUST
    gating the owner-operated deployment before it may store a first paying customer's content.
    The second paragraph — no third-party processor ever sees diary content, full stop — is
    unchanged in substance and strengthened in two ways: it now says explicitly that no deployment
    shape is exempt (previously implicit), and "Inference over diary content MUST run locally" is
    reworded to "MUST run on infrastructure the project itself operates and controls", because
    "locally" stops describing the managed shape's inference server truthfully while the
    prohibition it protects must not visibly weaken. This is the load-bearing clause behind #49's
    "no third-party AI vendor ever sees your diary" claim and was not reinterpreted, only reworded
    to stay accurate.
- Added principles: none
- Removed sections: none
- Modified sections:
  - Product Constraints — "Single-user, owner-administered" bullet renamed and reworded: the
    self-hosted shape stays single-user (unchanged), the managed shape MAY now serve more than one
    customer under one owner-operated backend, each isolated to their own content per Principle II.
  - Product Constraints — "Single-user authentication" bullet renamed "Authentication" and split
    by shape: the self-hosted rules (local hash or identity provider, allowlisted single subject,
    locally verifiable fallback) are unchanged; a new managed-shape clause permits public sign-up
    gated by per-customer authorization, with the concrete mechanism left to the feature that
    implements it (#45), not fixed here.
- Templates requiring updates:
  - .specify/templates/plan-template.md — reviewed, no change required (Constitution Check reads
    gates dynamically from this file)
  - .specify/templates/spec-template.md — reviewed, no change required (no hardcoded principle
    text)
  - .specify/templates/tasks-template.md — reviewed, no change required (only principle reference
    is to Principle V, unchanged here)
  - .specify/templates/checklist-template.md — reviewed, no change required
  - .claude/skills/speckit-*/SKILL.md — reviewed, all load constitution.md dynamically; no
    hardcoded principle text
  - mobile/CLAUDE.md, mobile/CONSTITUTION.md — reviewed, no reference to the amended clauses
  - specs/002-mood-pattern-diary-mobile/{spec,plan}.md, specs/003-web-client/{plan,research}.md,
    specs/004-nestjs-backend-migration/{spec,plan}.md — reviewed. Each contains a historical
    Constitution Check record ("II. Simplicity & YAGNI | Pass | ... no multi-tenancy ...") written
    against the constitution version current at that feature's plan time. Per the Amendment
    reconciliation clause below, a past Constitution Check is not retroactively rewritten; these
    are left as the historical record they are, not updated to read as if v3.0.0 always applied.
  - README.md — pending, deliberately, as in the v2.0.0 report: still documents only the
    self-hosted scrypt/AUTH_PASSWORD_HASH flow, which remains the only implemented path today.
    Rewriting it is explicitly #49's scope, not this amendment's.
- Follow-up TODOs:
  - This amendment permits, but does not implement, per-customer data isolation and
    owner-operated hosting. Until #45/#46/#47 ship, the running system remains single-user,
    scrypt-authenticated, local SQLite, and is fully compliant with v3.0.0.
  - Principle IV's encryption-at-rest MUST for the owner-operated deployment has no owning ticket
    yet; whichever of #46/#47/#48 first causes a paying customer's diary content to be persisted
    MUST land encryption at rest as part of that work, not after.
  - specs/005-public-auth lists "registration, password reset ... social login" as out of scope
    for that (self-hosted, single-user) feature. That remains true for the self-hosted shape and is
    unaffected by this amendment, which only widens what the managed shape may do.
- Retained from v1.2.0's report:
  - specs/002-mood-pattern-diary-mobile/plan.md still does not evaluate Principle VII. Per
    Amendment reconciliation it is not retroactively blocked; reconcile at its next /speckit-plan
    or /speckit-tasks run if one occurs.
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

The system MUST be designed for exactly one backend instance. Horizontal scaling, general-purpose
role-based access control, and speculative extension points MUST NOT be introduced unless a spec
explicitly requires them. The self-hosted shape remains single-user: no second person's account
MAY hold diary content there. The owner-operated managed shape (Principle IV) MAY serve more than
one paying customer; doing so permits — and requires — per-user data partitioning and authorization
sufficient that one customer's session can read or write only that customer's own diary content.
This is not a license for general multi-tenancy: nothing beyond that single isolation boundary is
permitted — no roles, no permission levels, no delegated or shared access to another customer's
diary content. Authenticating a single user through an account system — including a managed
identity provider offering registration, password reset or multi-factor authentication — remains
permitted and is not itself multi-tenancy. When a design choice could be solved with a direct,
boring implementation or a more general/abstracted one, the direct implementation MUST be chosen
unless current requirements demand the general one.

**Rationale**: Solo-maintained personal software accumulates cost fastest through unused
generality. The owner-operated deployment now has a genuine, current requirement — one customer
must never see another's diary — and that requirement earns exactly one thing: isolation between
customers. It does not earn a roles system, a tenancy hierarchy, or any abstraction a concrete
requirement hasn't asked for.

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

Diary content MUST be stored only in infrastructure the project controls: a machine the user runs
themselves, a named managed database provider under the user's own account, or — in the
owner-operated managed shape (Principle II) — a datastore the project owner operates on a paying
customer's behalf. The permitted managed provider is Supabase Postgres; adding any other provider
requires an amendment to this principle, not a spec-level decision. Wherever content is stored,
connections MUST use TLS, and the user MUST retain a working path to export a complete copy of
their own content and to delete it permanently. Encryption at rest MUST be enabled for the
owner-operated deployment before it stores any paying customer's diary content — this gates that
deployment going live, it is not optional hardening added later. For the self-hosted shape,
encryption at rest SHOULD be enabled; stated honestly, it is not enabled today — the diary is
stored in a plain, unencrypted SQLite file at `data/diary.db` — and this principle records that gap
rather than asserting a MUST the running code does not meet.

Storage location is a separate question from processing, and moving storage — to a managed
provider, or to infrastructure the project owner operates — MUST NOT be read as permission to move
inference to a third party. Diary content MUST NOT be transmitted to any third-party processor —
including hosted LLM, speech-to-text, analytics, or error-reporting services — under any deployment
shape, self-hosted or owner-operated, by default. Inference over diary content MUST run on
infrastructure the project itself operates and controls — the user's own machine in the self-hosted
shape, the project owner's own servers in the managed shape — unless a specific spec names the
third-party service, states exactly what content reaches it, and justifies it in that spec's
Assumptions. No third-party AI vendor MAY see diary content merely because storage or inference
moved from the user's own machine to infrastructure the project owner operates.

**Rationale**: This is a personal diary containing sensitive reflections. The boundary was never
"stays on my machine" for its own sake — it was always "stays in infrastructure I own and
administer, and is never read by an outside processor to produce a result." The owner-operated
shape keeps that boundary true by relocating who "I" is from the user to the project, not by
weakening it: content still never leaves infrastructure the project controls, and the prohibition
on third-party inference is unchanged. Those two risks — where content is stored, and who is
allowed to read it to produce a result — remain different, and the weaker one (storage location)
must not silently license the stronger (a third party reading diary content). Every exception to
either still deserves a visible decision trail, and the encryption-at-rest gap is recorded here
for the same reason a false MUST would not be: a constitution that claims something the code
doesn't do is worse than one that names the gap.

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
layer over the single backend. The feeling set, the guiding-question library, the
minimum-occurrence threshold, topic extraction, pattern detection, and all counts and averages MUST
be defined and computed in the backend only and served to clients. A client MUST NOT hardcode,
duplicate, or independently recompute any of them. Clients MAY own purely presentational concerns
locally — icons, emoji, ordering, animation, layout, and the wording of their own UI chrome. A
client MUST NOT read or write diary data directly from the datastore, bypassing the backend, even
where the datastore offers a client SDK and row-level security that would make it technically
possible. Given identical backend data, all clients MUST present identical facts; where they
disagree, the backend is authoritative and the client is wrong.

**Rationale**: A second client doubles the number of places a rule can live, and duplicated rules
drift silently — a threshold changed in one place, a feeling added in another, and the app starts
telling the user two different stories about their own life. That directly attacks the product's
core promise of trustworthy pattern-finding (Principle III) and is far cheaper to prevent by rule
than to detect later by noticing two screens disagree.

## Product Constraints

- **Owner-administered; multi-tenant only in the managed shape**: the self-hosted shape remains
  single-user, with no multi-user accounts, for the lifetime of this constitution version. The
  managed shape MAY serve more than one paying customer under a single owner-operated backend,
  each isolated to their own diary content as Principle II requires. No third-party-owned backend
  is in scope in either shape (see Principles II and IV). The single backend MAY run on the user's
  own hardware, on hosting the user rents and administers, or on hosting the project owner rents
  and administers on a customer's behalf.
- **Client platforms**: an Android app and a web app, both thin clients of the one backend (see
  Principle VII). No iOS client and no desktop-native client is in scope unless a future amendment
  changes this.
- **Two permitted deployment shapes**: (a) *self-hosted* — clients MAY remain LAN/VPN-only without
  in-app authentication, and public web access is permitted only through an outbound reverse tunnel
  whose hostname is protected by the backend's authentication; direct router port-forwarding of a
  self-hosted origin remains forbidden. (b) *managed* — a publicly routable origin is permitted
  only when authentication is enabled for every route and cannot be turned off by configuration,
  TLS terminates at or before the origin, and no unauthenticated LAN bypass is configured. In both
  shapes an identity-aware proxy such as Cloudflare Access SHOULD provide an additional outer
  authorization layer.
- **Authentication**: authentication MUST protect both the web shell and every diary API route,
  throttle failed attempts, and fail closed when enabled with incomplete configuration. Browser
  sessions MUST use an HttpOnly, Secure, SameSite session cookie; native clients MAY use bearer
  tokens.
  - *Self-hosted shape*: credentials MAY be verified either locally with a slow password hash or
    by a managed identity provider; when a provider is used, the backend MUST verify its tokens
    against the provider's published signing keys, public sign-up MUST be disabled, and the
    accepted subject MUST be allowlisted so that an account created elsewhere on that provider
    cannot reach the diary. A locally verifiable credential path MUST remain available so the
    diary stays reachable when the identity provider is unavailable. The public hostname MAY be
    protected without forcing authentication on direct LAN clients only in this shape, and only
    while the origin is reachable from the public internet solely through the configured tunnel.
  - *Managed shape*: public sign-up MAY be enabled, but every authenticated session MUST resolve
    to exactly one customer account, and every diary API route MUST authorize the request against
    that account's own diary content only (Principle II). The concrete mechanism — identity
    provider, entitlement validation, session model — is a spec-level decision for the feature
    that implements it, not fixed by this constitution.

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

**Version**: 3.0.0 | **Ratified**: 2026-07-27 | **Last Amended**: 2026-08-29
