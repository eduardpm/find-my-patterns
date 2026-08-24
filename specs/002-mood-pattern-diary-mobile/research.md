# Phase 0 Research: Mood Pattern Diary Mobile App

Each topic below was an open technical question raised by the Technical Context (either a direct
NEEDS CLARIFICATION or a dependency/integration needing a best-practice decision). Two of the
biggest — backend language and feeling/pattern inference approach — were resolved directly with
the user; the rest are resolved here as design decisions to unblock Phase 1.

## 1. Guiding question framework (FR-004/005/006)

**Decision**: Ship a small, fixed, curated question library instead of dynamically generating
questions per entry. Every entry flow shows three core prompts covering recent context, mind/body,
and easily overlooked influences. A fourth response/outcome prompt appears when an answer describes
a notable positive or difficult experience. The app fetches and caches the whole library once
(`GET /guiding-questions`); the optional follow-up is selected **client-side** via simple keyword
matching against what the user has typed so far (zero-latency, no network round trip while typing).
The separate confirmed-feeling step supplies the standardized outcome for pattern detection.

**Rationale**: Keeps the flow short enough to hit SC-002 (second same-day entry in <15s), avoids
adding a network call (or LLM call) into the critical typing path which would hurt the "pleasure to
write" goal, and a small curated library is easy to extend later without redesigning the flow.
Separating context, internal signals, and small influences makes FR-006's core requirement (answers
must be reliable pattern-detection input) achievable while the local inference worker normalizes
the resulting topics.

The library also includes a situational response/outcome follow-up: "What did you do next, and what
changed afterward?" It is triggered by language indicating a notable positive or difficult
experience. This captures coping actions and their perceived consequences without adding a required
step to ordinary check-ins.

**Alternatives considered**: Fully dynamic, LLM-generated questions per entry — richer
personalization, but adds an LLM round trip before the user can even start typing, directly hurting
speed goals, and less predictable/testable. A single always-identical question — simplest, but
doesn't adapt to context and produces a weaker signal for the pattern engine.

## 2. Backend service shape (FastAPI + SQLite, decided with user)

**Decision**: FastAPI app served by uvicorn, bound to the host's LAN interface so the phone can
reach it directly; SQLite file storage via SQLAlchemy with Alembic migrations; no auth middleware
(per spec FR-019); CORS is not a meaningful concern since the client is a native app, not a browser.

**Rationale**: SQLite is zero-ops and more than sufficient for single-user, low-thousands-of-rows-
per-year data. FastAPI's native async support fits calling out to the Claude API without blocking
the event loop, and its automatic OpenAPI schema doubles as a live contract-test reference.

**Alternatives considered**: PostgreSQL — unnecessary operational overhead (a server process to
run/maintain) for a single-user local app. Flask — weaker native async support for the
LLM-call-in-the-request-path pattern this feature needs.

## 3. Fixed-time daily reminders on Android (FR-013, SC-006)

**Decision**: Use `AlarmManager` with exact, Doze-surviving alarms (`setExactAndAllowWhileIdle` /
the current equivalent exact-alarm API) for the four fixed daily times, with a boot-completed
receiver that re-arms the next alarm after each fire or device restart.

**Rationale**: The requirement is clock-exact reminders (9:00/12:00/18:00/21:00) within a 1-minute
tolerance (SC-006). `WorkManager`'s periodic scheduling is designed for flexible, deferrable work
and does not guarantee exact-time firing under Doze, so it can't reliably meet SC-006 on its own.

**Alternatives considered**: `WorkManager` periodic work — simpler API, but no exact-time guarantee.
A foreground service polling the clock — meets the timing need but burns battery continuously,
which exact alarms avoid entirely.

## 4. Claude API integration for feeling suggestion and pattern narration (decided with user)

**Decision**: The backend calls the Claude API from the service layer, using structured/tool-use
output so responses are typed JSON:
- Per-entry feeling suggestion: `{feeling: <one of the fixed feeling set>, confidence}`, called
  synchronously when an entry is created/edited, returned to the client for confirmation (FR-007).
- Pattern narration: recurrence detection (has a Topic+Feeling pair crossed the minimum-occurrence
  threshold, per FR-012) is computed **in application code**, not by the LLM. Only once a candidate
  pattern has been deterministically confirmed does the backend send the supporting entries to
  Claude to produce the plain-language description and suggestion text (FR-010/FR-011).

**Rationale**: Constraining feeling suggestions to the fixed enum (via tool schema) keeps them
directly usable in monthly aggregation (FR-016) without extra normalization. Keeping the
recurrence-threshold check deterministic and in code — rather than trusting the LLM to "notice"
recurrence itself — avoids hallucinated patterns, keeps the minimum-occurrence rule (FR-012)
enforceable and testable, and keeps LLM usage bounded (one small call per new entry, one call per
newly-qualifying pattern) rather than re-sending the whole entry history on every check.

**Alternatives considered**: Sending full entry history to the LLM on every insights view load —
unpredictable, slower and costlier as history grows, and harder to test deterministically. Using a
separate classical sentiment-analysis library for feeling suggestion alongside the LLM for pattern
narration only — adds a second NLP dependency for marginal gain, given an LLM call is already
required for narration.

## 5. Modern Android journaling UI (FR-003, SC-001/SC-002/SC-004)

**Decision**: Kotlin + Jetpack Compose with Material 3 (dynamic color, large touch targets, a
single-focus full-screen or bottom-sheet entry composer reachable via one prominent FAB from the
Today view, minimal chrome while writing, light motion between guided-question steps).

**Rationale**: Compose + Material 3 is the current standard toolkit for building modern, animated
native Android UI quickly, and directly supports the "modern, sleek, pleasant to write in" bar set
by the spec. A single FAB-to-composer path minimizes screens between "open app" and "start typing,"
supporting SC-001/SC-002.

**Alternatives considered**: Flutter — the cross-platform benefit isn't needed since the spec
scopes this to Android only (FR-017). Classic View/XML-based UI — slower to iterate on modern
motion/theming and a dated look relative to the spec's UI bar.

## 6. Phone → backend connectivity (FR-020)

**Decision**: The Android app stores a manually-entered backend address (host/IP + port) in local
settings; no automatic network discovery for v1.

**Rationale**: A home network has one relevant machine; typing its local IP once in Settings is
low-friction and avoids the real added complexity of network service discovery (advertising and
resolving an mDNS/NSD service) for a single-user, single-backend app.

**Alternatives considered**: Network Service Discovery (NSD/mDNS) auto-detection — nicer first-run
UX, but not justified by the added implementation/testing surface for a device pairing that only
ever needs to happen once per home network.
