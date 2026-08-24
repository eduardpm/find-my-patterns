# Phase 0 Research: Re-platform the Backend onto NestJS

> **⚠️ Superseded in part (2026-07-29).** The Python backend was deleted, the differential test
> strategy was dropped, and the deliberately-ported topic-matching defect was fixed — because the
> **spec**, not the previous implementation, is the source of truth. The new backend now lives at
> `backend/`. Read the **Outcome** section at the top of [spec.md](./spec.md) before relying on
> anything here.

Decisions behind [plan.md](./plan.md). Every one is measured against a single question: **does this
keep the diary and the contract byte-identical?** Where a conventional NestJS choice conflicts with
that, the conventional choice loses.

All formats below were captured from the running system, not assumed.

---

## 1. The two fidelity boundaries (the actual problem)

**Observed, not inferred.** A live entry created through the current backend produces:

| Boundary              | Value                          | Node's default would produce |
| --------------------- | ------------------------------ | ---------------------------- |
| Stored `created_at`   | `2026-07-28 12:33:49.248359`   | `2026-07-28T12:33:49.248Z`   |
| Stored `entry_date`   | `2026-07-28`                   | ISO datetime                 |
| Stored JSON column    | `["ate", "drank", "coffee"]`   | `["ate","drank","coffee"]`   |
| Stored `is_mandatory` | `1` / `0`                      | `true` / `false`             |
| Wire `created_at`     | `"2026-07-28T12:33:49.248359"` | `"2026-07-28T12:33:49.248Z"` |

**Decision**: All storage and serialization goes through one explicit codec module
(`src/db/codecs.ts`); no value reaches SQLite or the wire via a default `Date` or `JSON.stringify`
path. Datetimes are stored as `YYYY-MM-DD HH:MM:SS.ffffff` (space separator, six-digit fractional,
naive) and serialized as the same with a `T` separator and **no timezone suffix**. JSON columns are
written with Python's `json.dumps` default separator — `", "` — so a rewritten row is
indistinguishable from one the old backend wrote. Booleans are integers.

**Rationale**: These are the differences that would corrupt the diary or break the installed Android
app, and every one of them is a _silent_ difference — nothing throws. `toISOString()` truncates to
milliseconds, so `…248359` becomes `…248`: a real loss of stored precision on every write, and a
changed wire format that the Kotlin and TypeScript date parsers would either reject or reinterpret.
Node has no built-in microsecond clock, so timestamps must be composed deliberately.

**Alternatives considered**:

- _Store native ISO-8601 with `Z` and convert on read_ — rejected: it changes bytes on disk (FR-022)
  and creates a diary where old and new rows are formatted differently forever.
- _Normalise the whole file once at cutover_ — rejected outright by the Q1 decision: no
  transformation of existing data, and it would make revert lossy.
- _Let the Android client tolerate both formats_ — rejected: it is an installed app, and FR-006
  forbids touching either client.

---

## 2. Storage access: hand-written SQL, no ORM

**Decision**: `better-sqlite3` with hand-written statements and a thin per-table repository. No
TypeORM, no Prisma, no Drizzle, no migration framework. The database is opened against the existing
file and the process **never issues DDL**.

**Rationale**: FR-022 says merely starting the backend must not modify the diary. Every mainstream
Node ORM's default posture is to own the schema — TypeORM's `synchronize`, Prisma's `db push` and
migration state table, Drizzle's push. Each is opt-out, and the cost of getting the opt-out wrong is
not an error message, it is silent alteration of the one thing in this project that cannot be
reconstructed. Never introducing the capability is safer than configuring it off, and Principle II
says take the boring, direct option. The schema is 8 fixed tables that have changed once; an ORM's
value here is close to zero.

`better-sqlite3` is synchronous, which suits a single-user app: no connection pool, no async
transaction choreography, and the conflict check plus update can sit in one `db.transaction()` with
genuine atomicity.

**Alternatives considered**:

- _Prisma_ — the most ergonomic option and the one most people would reach for. Rejected on FR-022:
  it wants to own migration state and would add its own tracking table to the user's diary file.
- _TypeORM with `synchronize: false`_ — one boolean between working and destructive, on a file with
  no upstream copy.
- _Drizzle_ — lighter and closer to SQL, genuinely tempting; still ships a push/migrate workflow
  whose whole purpose is to reshape the schema. Reconsider if the schema ever starts moving.

**Explicit rule for implementation**: the process must open the database and issue only `SELECT`,
`INSERT`, `UPDATE`, `DELETE`. Any `CREATE`, `ALTER`, `DROP` or `PRAGMA user_version` write is a bug,
and `alembic_version` is never read, written, or reasoned about.

---

## 3. The `entry_date` clock mismatch — port it, don't fix it

**Decision**: Reproduce the current behaviour exactly: `created_at`/`updated_at` from UTC now,
`entry_date` from the **server's local calendar date**. Do not unify them.

**Rationale**: The existing code sets `created_at=datetime.utcnow()` but `entry_date=date.today()`,
mixing two clocks. On a machine not running UTC, an entry written late at night can carry a
timestamp whose UTC date differs from its `entry_date`. Every entry already in the diary was written
under that rule, and day grouping, the monthly calendar and the daily average all key off
`entry_date`. "Fixing" it during a port would silently re-file existing entries onto different days
and change monthly totals — breaking SC-001 and SC-003 while looking like a cleanup.

This is a genuine latent defect (it was raised as finding F4 during feature 003's analysis). It
deserves its own spec, where the migration of existing rows can be reasoned about deliberately. It
must not ride along inside a re-platform.

---

## 4. The topic-extraction bug: port it verbatim, and pin it with a test

**Decision**: Port `topic_service`'s substring matching exactly as it is — including the defect where
`"drank"` and `"grandma"` both match the keyword `"ran"` and register the topic **exercise**. Add a
test asserting the buggy behaviour, labelled as a deliberate bug-for-bug port with a pointer to the
follow-up.

**Rationale**: This is the conflict the spec flagged, and it resolves against fixing. FR-011 and
SC-002 require the new backend to produce _the same patterns with the same occurrence counts_ as the
old one. The bug is not cosmetic — it has already written rows: topics, `entry_topics` links and
`patterns` in the user's diary were created under it. A "fixed" backend would compute a different
topic set on its first pattern run, delete patterns that no longer qualify, and change the user's
Insights for reasons they cannot perceive. That is exactly the silent divergence this feature exists
to avoid.

Porting a known bug on purpose is uncomfortable, and the discomfort is the point: a re-platform's job
is to change _how_, never _what_. The test locks the behaviour so the fix, when it comes, is a
visible decision in its own feature rather than an accident inside this one.

**Alternatives considered**:

- _Fix during the port_ — rejected: directly contradicts SC-002, and mixes two changes so any
  resulting difference in insights is unattributable.
- _Fix behind a flag_ — rejected: two behaviours to test, and the flag would outlive its purpose.

---

## 5. The Claude integration, including its no-key fallback

> **Superseded on 2026-08-14:** the hosted Claude edge described below was replaced after the
> migration by a durable SQLite job queue and a separate local Ollama worker using `qwen3:4b`.
> Entry text no longer leaves the machine. Pattern narration is now deterministic.

**Decision**: `@anthropic-ai/sdk` with the same model, the same two tool-shaped calls, and — this is
the part that matters for testing — the **same deterministic fallback when `ANTHROPIC_API_KEY` is
absent**: `suggest_feeling` returns `neutral` with confidence `0.0`, and `narrate_pattern` returns
the same templated sentences, word for word.

**Rationale**: The entire existing test suite depends on that fallback; it is why 71 tests run with
no network and no key. Reproducing the templated strings exactly is what allows the differential
tests in quickstart.md to compare narrative text between backends. The fallback strings are
therefore contract, not filler.

**Note for implementation**: the current Python client reads `ANTHROPIC_API_KEY` at construction, so
tests inject a stub rather than relying on the environment (a fragility found and fixed during 003).
The Node port should take the client as an injected dependency from the start — Nest's DI makes this
the natural shape anyway.

---

## 6. Serving the web client at `/app`

**Decision**: `express.static` mounted at `/app` **after** all API routes, with an explicit SPA
fallback to `index.html` for unmatched paths under `/app`, and the same guard: if `web/dist` is
missing, log a warning and serve the API only.

**Rationale**: All three properties are load-bearing and each was learned the hard way in feature 003.
The prefix exists because SPA routes would otherwise collide with `/entries` and `/insights`. The
fallback exists because a deep link like `/app/calendar` is not a file — in the Python version this
was initially broken because `StaticFiles` _raises_ rather than returns a 404, and the equivalent
Express trap is `express.static` calling `next()` and falling through to a JSON 404 handler. The
missing-directory guard exists because an unconditional mount takes the API down on a fresh clone,
which would break the Android app.

`Cache-Control: no-store` is applied to the diary-bearing API paths only (`/entries`, `/insights`,
`/monthly-summary`, `/guiding-questions`) and **not** to static assets — matching current behaviour
exactly.

---

## 7. Error envelope and the 409 conflict body

**Decision**: A global exception filter produces `{"error": {"code", "message"}}` with the same code
mapping (`400 → bad_request`, `404 → not_found`, `422 → validation_error`). The stale-entry conflict
is returned **directly**, not thrown, because its body carries an extra top-level `current` key
alongside `error`.

**Rationale**: This is the same trap the Python version hit and documented: routing the 409 through
the generic error handler strips `current` and mislabels the code, and both failures are silent — the
response still looks well-formed. The web client's conflict screen and the Android app's
`ApiResult.StaleEntry` both parse `current` and would degrade to a generic error without it.

Validation failures must surface as **422**, not Nest's default 400, to match FastAPI. Nest's
`ValidationPipe` defaults to 400, so the status is set explicitly — a small detail that would
otherwise break the contract tests asserting 422 for a missing `version`.

---

## 8. Test strategy: differential, not just parallel

**Decision**: Vitest, with three layers:

1. **Ported unit/contract tests** — a Vitest equivalent of each of the 71 pytest cases. This is the
   FR-012 checklist.
2. **Differential tests** — the distinguishing layer. A fixture diary is copied twice; both backends
   are started against their own copy; an identical sequence of requests is replayed against each;
   responses are compared _including datetime formatting_, and afterwards both database files are
   compared row by row.
3. **A byte-level no-write test** — start the new backend against a diary, exercise every read path,
   shut down, and assert the file's hash is unchanged (SC-011/FR-022).

**Rationale**: Ported tests prove the new backend satisfies the specification as understood by
whoever ports them — which is exactly the risk, since a misunderstanding gets copied into the test.
Differential testing compares against the system of record instead, and catches the failure modes
that matter here: a datetime formatted with milliseconds, a JSON separator, a float rendered
differently, an ordering difference. The hash test is the only thing that actually proves FR-022
rather than assuming it.

**Alternatives considered**:

- _Ported tests only_ — cheaper, and blind to precisely the formatting differences this port is most
  likely to produce.
- _Golden-file snapshots captured once from the Python backend_ — a reasonable middle ground and
  worth using for fixed payloads, but it cannot cover generated timestamps, so it supplements rather
  than replaces differential runs.

---

## 9. Cutover and rollback

**Decision**: Cutover is: stop the old process, **copy the diary file to a timestamped backup**, start
the new process against the original path. Rollback is the reverse, with no conversion in either
direction. The backup is taken by the operator, not by the application.

**Rationale**: Because nothing transforms the data (Q1 decision), rollback is just running the other
binary — which is what makes SC-009's 15-minute target easily achievable. The backup is belt-and-braces
against the scenario the whole plan is guarding: a first-run write that alters the file in a way the
old backend then misreads. Entries written _after_ the switch live in the same file and survive a
revert, since the schema is unchanged — FR-017 requires the maintainer be told this plainly, and
[quickstart.md](./quickstart.md) states it.

**Not doing**: parallel-run with both backends live against one diary. Two writers over one SQLite
file is exactly the split-brain Principle VII exists to prevent, and it would make the conflict
protocol meaningless.
