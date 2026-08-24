# Phase 0 Research: Mood Pattern Diary Web App

Decisions resolving the open technical questions behind [plan.md](./plan.md). Every decision is
checked against constitution v1.1.0 — in particular Principle II (Simplicity & YAGNI) and
Principle VII (One Backend, Thin Clients), which together do most of the constraining here.

---

## 1. Web client stack

**Decision**: Vite 6 + React 18 + TypeScript, with React Router for view routing and plain CSS
(custom properties) for styling. No CSS framework, no state-management library, no data-fetching
library.

**Rationale**: The spec asks for genuinely interactive behavior that needs real client-side state —
guided questions that surface as the user types (FR-004), an unsaved-change guard (FR-026), a
side-by-side conflict view holding two versions of an entry at once (FR-023), and full keyboard
completion of the composer (FR-014). TypeScript pays for itself at the API boundary: the backend
contract is the only coupling between the two, and typing it catches drift that Principle VII cares
about. Everything beyond that was left out deliberately — with manual refresh (FR-019) there is no
cache-invalidation problem for a data library to solve, and a single-user app has no state
complexity a `useState` can't hold.

**Alternatives considered**:
- *Jinja2 templates + HTMX, served directly by FastAPI* — genuinely attractive: no Node, no build
  step, one language. Rejected because FR-026's beforeunload guard, FR-023's two-versions-on-screen
  conflict view, and FR-014's keyboard-only flow all need client state that HTMX can only fake with
  growing awkwardness, and SC-001/SC-002's speed targets sit badly with full page loads on every
  step.
- *SvelteKit* — less boilerplate and a smaller bundle, but its default posture is SSR plus a server
  runtime, which fights the "static assets served by the existing FastAPI process" decision in §2.
- *Vanilla TypeScript, no framework* — removes a dependency but not the complexity; re-implements
  list diffing and focus management by hand, with worse accessibility defaults.
- *Tailwind* — rejected to keep control of focus rings and contrast explicit for FR-027, and to
  avoid a second build-time dependency for something a token file already handles.

---

## 2. How the web app is served and routed

**Decision**: `vite build` emits static assets; FastAPI serves them with `StaticFiles(html=True)`
mounted at **`/app`**. All web routes live under that prefix (`/app/today`, `/app/insights`,
`/app/month/2026-07`, `/app/entry/{id}`). API paths are untouched. In development, the Vite dev
server proxies API calls to `http://localhost:8000`.

**Rationale**: This is the decision that keeps FR-018 intact. The SPA's natural routes collide
head-on with live API paths — `/insights` and `/entries` are both real endpoints today — so
mounting the SPA at `/` would either shadow the API or be shadowed by it depending on registration
order. The obvious fix, re-prefixing the API to `/api`, would break the already-shipped Android app,
which is exactly what FR-018 forbids. Serving under `/app` sidesteps both, and same-origin serving
means no CORS configuration, one process to run, one address to remember (matching the spec's
assumption that the user doesn't configure a second address), and no third-party CDN — which keeps
Principle IV clean.

**Alternatives considered**:
- *Re-prefix the API under `/api`, serve the SPA at `/`* — cleanest URLs, rejected on FR-018.
  Keeping compatibility aliases for the old paths was considered and rejected as two ways to do
  everything, forever.
- *Separate static server (nginx/`vite preview`) on another port* — a second process and a second
  address for the user to manage, for no gain on a single machine.
- *Hash routing (`/app#/today`)* — avoids server-side history fallback but produces uglier
  addresses; `html=True` gives SPA fallback without it.

---

## 3. Concurrent-modification detection (FR-011, FR-022, FR-023)

**Decision**: Add an integer `version` column to `diary_entries`, starting at 1 and incremented by
the backend on every mutation. It is returned on every entry read and **required** on `PATCH` and
`DELETE`. A mismatch returns **`409 Conflict`** with error code `stale_entry`, carrying the current
server-side entry in the response body so the client can render the comparison FR-023 requires
without a second round trip.

**Rationale**: Deterministic, trivially unit-testable, and immune to the failure modes a timestamp
has — no clock skew between the phone and the backend, no sub-millisecond collisions, and no
dependence on SQLAlchemy's `onupdate` firing (it only fires when a field actually changed, so a
no-op save would leave the timestamp untouched and silently defeat detection). Constitution
Principle III wants correctness-gating logic to be deterministic and testable; an integer
comparison is as deterministic as it gets. Returning the current entry inside the 409 body is what
makes FR-023's "your text next to the server's version" achievable without the client racing to
re-fetch.

Requiring the field on `DELETE` matters as much as on `PATCH`: FR-021 exists precisely because a
stale-view *delete* is the most destructive thing the manual-refresh model allows.

**Transport shape**: `version` is a normal field in the `PATCH` JSON body, and a required query
parameter on `DELETE` (`DELETE /entries/{id}?version=3`), since DELETE bodies are poorly supported
across HTTP clients.

**Alternatives considered**:
- *ETag / `If-Match` headers* — the HTTP-idiomatic answer, and rejected reluctantly. The existing
  API is plain JSON with no header-level semantics anywhere; introducing conditional-request
  handling for one operation adds a concept both clients and every contract test would have to
  learn, for no behavioral gain on a single-user LAN app. Principle II says take the boring option.
- *`updated_at` timestamp comparison* — no schema change needed, but fragile for the reasons above.
- *Last-write-wins with an audit trail* — rejected outright: it satisfies neither FR-011 nor SC-008.

---

## 4. Serving the feeling set, and reconciling Android (Principle VII)

**Decision**: Add `GET /feelings`, returning key, label, and valence for the eight seeded feelings.
The web client consumes it from day one. The Android app is migrated from its hardcoded
`Feeling` enum onto the same endpoint, keeping only the emoji mapping locally as presentation.

**Rationale**: Principle VII forbids a client hardcoding the feeling set, and this is the app's one
outstanding violation — `android/.../domain/Feeling.kt` duplicates `backend/app/db/seed.py`
key-for-key *and* duplicates each feeling's valence, which is a rule (it drives the keep/change
direction of every insight), not a presentation detail. Building the web client against a hardcoded
copy would make it three copies. Doing the Android migration in this feature is close to free
because FR-022 already opens that client's data layer for the version change, and the constitution's
Sync Impact Report already tracks it as `TODO(PRINCIPLE_VII_RECONCILIATION)`.

Emoji stay client-side deliberately: Principle VII explicitly reserves icons and presentation to
clients, and the web client will want its own treatment anyway.

**Alternatives considered**:
- *Leave Android alone, have only the web client fetch* — rejected: it leaves the constitutional
  debt open and means the two clients disagree about where truth lives, which is precisely the drift
  Principle VII names.
- *Add feelings to the existing `GET /guiding-questions` response* — fewer endpoints but conflates
  two unrelated resources; the entry composer needs both independently.

---

## 5. Keeping diary content out of the browser (FR-024, FR-025)

**Decision**: Addresses carry only view identity and opaque entry UUIDs — never entry text, guided
answers, or feelings. No `localStorage`, no `sessionStorage`, no IndexedDB, no service worker, and
no cookies. Diary content lives only in React state for the lifetime of the tab. API responses are
sent with `Cache-Control: no-store` so diary JSON is not written to the browser's HTTP cache.

**Rationale**: The no-authentication decision rests entirely on "only I can reach this machine," and
browser history is where that assumption leaks — history syncs across devices on every major
browser, so a URL containing entry text would carry diary content off the LAN through a channel the
threat model never accounted for. `no-store` closes the equivalent leak through the disk cache.
Ruling out a service worker is a real consequence worth stating plainly: it forecloses offline
support and installability for as long as FR-025 stands, which is consistent with FR-016's LAN-only
posture but would need revisiting if offline mode is ever specified.

**Alternatives considered**:
- *Encrypt local drafts* — key management with no authentication is theatre; there is nowhere to put
  a key the browser can use but an attacker at the same machine cannot.
- *Session-only `sessionStorage` for drafts* — survives reloads but also survives the tab restore
  flow, and writes diary text to disk on some platforms. Ruled out by the plain reading of FR-025.

---

## 6. Unsaved-change guard (FR-026)

**Decision**: A `useUnsavedGuard` hook registers a `beforeunload` handler only while the composer
holds text that differs from what was last saved, and blocks in-app route changes through the
router's navigation-blocking API. It is unregistered the moment the entry is clean.

**Rationale**: FR-026 requires a prompt when there is unsaved text and explicitly forbids one when
there isn't — an always-on handler would nag on every close and would itself violate Principle VI's
bar on friction. Browsers deliberately ignore custom text in the native dialog and only honor the
handler after a user gesture; both are acceptable here since the requirement is that the user is
*asked*, not that we control the wording.

**Known limitation, accepted**: `beforeunload` does not fire on a browser or OS crash, so crash-time
writing is genuinely lost — FR-025 forecloses the draft-recovery answer. This is recorded as a
residual risk in the spec's Edge Cases rather than silently designed around.

---

## 7. Testing strategy for the web client

**Decision**: Vitest + React Testing Library covering the pieces with real logic — the conflict
state machine (409 → preserve text → retry/discard/carry across), the unsaved-change guard's
arm/disarm transitions, guided-question trigger matching, and API error mapping. No Playwright or
other browser-driving E2E harness in v1. FR-014's keyboard flow and FR-027's accessibility baseline
are verified by the manual walkthrough in [quickstart.md](./quickstart.md).

**Rationale**: Principle V requires tests before merge for correctness-gating logic and explicitly
exempts client UI polish, which now covers web as well as Android. The backend contract tests
remain the real guard on the API. A full browser E2E stack is a large standing dependency for a
solo-maintained personal app, and Principle II says not to buy it until a concrete requirement
demands it — and here the two most valuable checks it would give (keyboard operability, visible
focus) are things FR-027 already defines as verifiable by inspection.

**Alternatives considered**:
- *Playwright E2E from the start* — genuinely the strongest coverage of SC-003 and SC-014, and worth
  revisiting if the web client grows past v1. Deferred, not dismissed.
- *`axe-core` automated accessibility assertions* — cheap and tempting, but catches only a subset of
  FR-027's bar (contrast and labels, not focus visibility), so it would give false confidence
  without replacing the manual pass.

---

## 8. Visual system, keyboard, and accessibility (FR-015, FR-014, FR-027)

**Decision**: A CSS custom-property token file mirrors the Android app's Material 3 palette and type
scale so the two clients feel related without sharing code. Every interactive element carries a
visible focus ring meeting a 3:1 contrast ratio against its background; body text meets 4.5:1. The
composer is reachable and completable by keyboard alone, with feeling selection as a labelled radio
group (arrow-key navigable) and an explicit save shortcut. Semantic HTML first; ARIA only where no
native element fits — the calendar grid and the conflict comparison.

**Rationale**: FR-027 pins the bar to something checkable by inspection rather than a formal
conformance level, and these three — visible focus, real contrast, labelled controls — are what make
FR-014's keyboard requirement usable rather than merely technically satisfied. Mirroring the Android
tokens is the cheapest route to FR-015's "same bar" without coupling the builds, and stays inside
Principle VII's carve-out for presentation.

**Alternatives considered**:
- *A component library (MUI, Radix)* — strong a11y primitives out of the box, rejected as a heavy
  dependency for roughly six screens, and it would fight the Android-matching visual system.
- *Committing to WCAG 2.1 AA* — already weighed and declined during `/speckit-clarify` as ceremony
  for a single-user personal app.
