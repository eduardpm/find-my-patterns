<!--
Sync Impact Report
- Version change: 1.2.0 → 2.0.0 (MAJOR)
- Bump rationale: Principle IV's storage boundary is reversed in meaning. v1.2.0 forbade
  persisting diary content in "third-party or cloud storage" outright; v2.0.0 permits it in a
  named managed provider held under the user's own account. This constitution's own versioning
  policy defines MAJOR as "a principle is removed or reversed in meaning", which this is. The
  Product Constraints clause forbidding "cloud-hosted backend option" is removed for the same
  reason.
- Modified principles:
  - II. Simplicity & YAGNI — clarified that authenticating the single user through an account
    system (registration, password reset, MFA) is not multi-tenancy. What stays forbidden is
    per-owner data partitioning, authorization roles, and a second person's account holding diary
    content. The rule is unchanged; its edge is now stated, because a managed identity provider
    would otherwise read as the "user accounts/roles" the old wording banned outright.
  - IV. Privacy by Architecture — storage boundary moved from "a backend the user runs and
    controls themselves" to "a datastore the user owns and administers", with Supabase Postgres
    named as the only permitted managed provider. Added TLS, encryption-at-rest, export and
    permanent-delete requirements. Split storage from processing: transmitting diary content to
    third-party LLM, speech-to-text, analytics or error-reporting services remains forbidden by
    default and still requires a named, justified spec Assumption. That split is the load-bearing
    half of this amendment — permission to host the database elsewhere is not permission to send
    diary text to an inference API.
  - VII. One Backend, Thin Clients — added an explicit prohibition on a client reading or writing
    the datastore directly, bypassing the backend, even where a client SDK and row-level security
    make it technically possible. Necessary because a managed Postgres ships exactly such an SDK.
    Also dropped "self-hosted" from "the single self-hosted backend", which the new deployment
    shapes make inaccurate.
- Added principles: none
- Removed sections: none
- Modified sections:
  - Product Constraints — "Single-user, self-hosted only" became "Single-user,
    owner-administered"; the one backend MAY now run on hosting the user rents and administers.
  - Product Constraints — the single tunnel-only public-access bullet became two named deployment
    shapes, self-hosted and managed. A managed backend is itself a publicly routable origin, which
    the previous text forbade outright, so the old bullet could not simply be widened.
  - Product Constraints — "Single-user authentication" generalized from a local scrypt hash to
    either a local slow hash or a managed identity provider whose tokens are verified against its
    published signing keys, with public sign-up disabled and the accepted subject allowlisted.
    Added a mandatory locally verifiable fallback so provider downtime cannot lock the user out of
    their own diary.
- Templates requiring updates:
  - .specify/templates/plan-template.md — ✅ reviewed, no change required (its Constitution Check
    reads gates dynamically from this file)
  - .specify/templates/spec-template.md — ✅ reviewed, no change required (its authentication
    mentions are generic placeholder examples, not principle content)
  - .specify/templates/tasks-template.md — ✅ reviewed, no change required (its only principle
    reference is to Principle V, unchanged here)
  - .specify/templates/checklist-template.md — ✅ reviewed, no change required
  - .claude/skills/speckit-*/SKILL.md — ✅ reviewed, all ten load constitution.md dynamically; no
    hardcoded principle text and no outdated agent-specific references
  - web/README.md — ✅ reviewed, no change required; its Principle VII reference concerns
    client-side computation, which this amendment expands rather than alters
  - README.md — ⚠ pending, deliberately: its "Public access through Cloudflare Tunnel" section
    documents the scrypt/AUTH_PASSWORD_HASH flow, which is still the only implemented path. The
    constitution now permits a managed provider, but no code implements one, and documenting an
    unbuilt flow would make the README false. Update it in the feature that implements
    provider-based authentication.
- Follow-up TODOs:
  - This amendment permits provider-based authentication and managed Postgres storage; it
    requires neither. Until a feature ships, the running system remains scrypt + local SQLite and
    is fully compliant with v2.0.0.
  - specs/005-public-auth lists "registration, password reset ... social login, persistent
    cross-restart sessions" as out of scope. That is a scope statement for that feature, not a
    rule, and is now superseded rather than contradicted; reconcile at the next /speckit-plan run
    that touches authentication.
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

The system MUST be designed for exactly one user and one backend instance. Multi-tenancy, per-user
data partitioning, authorization roles, horizontal scaling, and speculative extension points MUST
NOT be introduced unless a spec explicitly requires them. Authenticating that single user through
an account system — including a managed identity provider offering registration, password reset or
multi-factor authentication — is NOT multi-tenancy and is permitted; what remains forbidden is
diary data partitioned by owner, authorization roles, and any second person's account holding
diary content. When a design choice could be solved with a direct, boring implementation or a more
general/abstracted one, the direct implementation MUST be chosen unless current requirements demand
the general one.

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

Diary content MUST be stored only in a datastore the user owns and administers: either a machine
the user runs themselves, or a named managed database provider under the user's own account. The
permitted managed provider is Supabase Postgres; adding any other provider requires an amendment to
this principle, not a spec-level decision. Wherever content is stored, connections MUST use TLS,
encryption at rest MUST be enabled, and the user MUST retain a working path to export a complete
local copy and to delete all content permanently.

Storage location is a separate question from processing. Diary content MUST NOT be transmitted to
any third-party processor — including hosted LLM, speech-to-text, analytics, or error-reporting
services — by default. Inference over diary content MUST run locally unless a specific spec names
the service, states exactly what content reaches it, and justifies it in that spec's Assumptions.
Moving storage to a managed provider MUST NOT be read as permission to move inference too.

**Rationale**: This is a personal diary containing sensitive reflections. The original boundary was
"stays on my machine"; it is now "stays in infrastructure I own and administer", which admits
managed hosting without admitting the wider class of services that would read the content in order
to produce a result. Those are different risks, and the weaker one must not silently license the
stronger. Every exception still deserves a visible decision trail.

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

- **Single-user, owner-administered**: no multi-user accounts and no third-party-owned backend
  are in scope for the lifetime of this constitution version (see Principles II and IV). The single
  backend MAY run on the user's own hardware or on hosting the user rents and administers.
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
- **Single-user authentication**: authentication MUST protect both the web shell and every diary
  API route, throttle failed attempts, and fail closed when enabled with incomplete configuration.
  Credentials MAY be verified either locally with a slow password hash or by a managed identity
  provider; when a provider is used, the backend MUST verify its tokens against the provider's
  published signing keys, public sign-up MUST be disabled, and the accepted subject MUST be
  allowlisted so that an account created elsewhere on that provider cannot reach the diary. Browser
  sessions MUST use an HttpOnly, Secure, SameSite session cookie; native clients MAY use bearer
  tokens. A locally verifiable credential path MUST remain available so the diary stays reachable
  when the identity provider is unavailable. The public hostname MAY be protected without forcing
  authentication on direct LAN clients only in the self-hosted shape, and only while the origin is
  reachable from the public internet solely through the configured tunnel.

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

**Version**: 2.0.0 | **Ratified**: 2026-07-27 | **Last Amended**: 2026-08-27
