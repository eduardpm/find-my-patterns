# Quickstart & Validation: Re-platform the Backend onto NestJS

> **⚠️ Superseded in part (2026-07-29).** The Python backend was deleted, the differential test
> strategy was dropped, and the deliberately-ported topic-matching defect was fixed — because the
> **spec**, not the previous implementation, is the source of truth. The new backend now lives at
> `backend/`. Read the **Outcome** section at the top of [spec.md](./spec.md) before relying on
> anything here.
> How to run the new backend and prove it is indistinguishable from the old one. Walking this through
> is a constitution quality gate (Development Workflow), and for this feature it carries more weight
> than usual: there is no new behaviour to demo, so **validation is the deliverable**.

The organising idea is **differential testing**. Not "does the new backend work?" but "does it do
exactly what the old one does, given the same diary?" The old backend is still here precisely so it
can answer that.

## Prerequisites

- The existing Python backend, set up per [`backend/README.md`](../../backend/README.md) — it is the
  reference implementation, not legacy.
- **Node 20 LTS**.
- The Android app installed, and the web client built, both **unmodified**.

## Setup

```sh
cd backend
npm install
npm run build
```

No migration step. No conversion step. That absence is the Q1 decision working as intended.

## Automated checks

```sh
cd backend && npm test && npm run lint
cd ../backend   && .venv/bin/pytest -q          # reference suite must still pass, untouched
```

Both must be clean. The Python suite passing is not a formality — if it stops passing, the reference
has drifted and every differential result is suspect.

---

## Validation scenarios

### 1. The new backend does not touch the diary — FR-022 / SC-011

The single most important check, and the one to run first.

```sh
cp ~/diary.db /tmp/before.db
sha256sum /tmp/before.db
DATABASE_PATH=/tmp/before.db npm start          # then read every screen in the browser
# stop the server
sha256sum /tmp/before.db
```

**Expected**: the hash is identical. Starting up, seeding, listing entries, opening insights and
opening the calendar must write nothing.

If this fails, stop. The likely causes are a seed that inserts into a populated table, a schema-sync
that "helpfully" adjusts a column, or a pattern recompute stamping `last_updated_at` unconditionally.
Each of those is a silent data change and must be fixed before anything else is judged.

### 2. Every entry survived — US1 / SC-001

Point the new backend at a copy of a real diary and read it all back. Every entry appears with the
same text, timestamp, day, feeling and feeling source. Guided entries still carry their individual
answers. **Nothing was exported, imported, converted or re-entered to make this true.**

### 3. Both backends answer identically — SC-005

The core differential run:

```sh
cp ~/diary.db /tmp/a.db && cp ~/diary.db /tmp/b.db
# start the Python backend on :8000 against /tmp/a.db
# start the Nest backend  on :8001 against /tmp/b.db
# replay an identical request sequence against both and diff the responses
```

**Expected**: byte-identical JSON, apart from values that are genuinely time- or id-dependent.

Look specifically at: the **microseconds** in `created_at` (`.248359`, not `.248` and not `Z`); the
**unrounded** `average_entries_per_day`; error `code` values; the 409 body's `current` sibling; and
`insufficient_data` when there are no patterns.

Then diff the two databases row by row. They must agree everywhere — including the JSON columns'
`", "` separator on any row that was rewritten.

### 4. Patterns are identical — US2 / SC-002 / FR-011

Against the same seeded diary, `GET /insights` on both backends must return the same patterns, the
same occurrence counts, the same directions and the same order.

**Including the wrong ones.** A diary containing "I drank water" produces the topic **exercise**,
because the current extractor matches `"ran"` inside `"drank"`. The new backend must reproduce that
(research.md §4). If the new insights look _better_ than the old ones, the port has failed its own
success criteria — that fix belongs to its own feature.

### 5. The conflict protocol still holds — FR-009 / SC-005

1. Read an entry, note its `version`.
2. Update it once so the stored version moves on.
3. Save again using the original version.

**Expected**: `409`, body code `stale_entry`, `current` present with the current entry, the stored
entry unchanged, and the stored version **not** incremented by the rejected attempt. Then repeat with
`DELETE ?version=` — refused, entry still there.

### 6. The unmodified Android app works — US3 / SC-004

Point the installed app at the new backend without reinstalling or changing its configured address.
Write an entry, confirm a feeling, edit it, delete it, open Insights, open the calendar, and force a
conflict from a stale view.

This is the scenario with the least margin for error: the app parses these responses with a
statically-typed serializer, so a missing key or a reformatted timestamp shows up as a failure, not a
warning. If a client needs _any_ change to work, that is a finding — the contract has drifted.

### 7. The unmodified web client works — US3 / SC-004

Serve the existing `web/dist` from the new backend at the same address. Every screen works.

Check the two traps from feature 003 specifically: a deep link like `/app/calendar` returns the app
and not a JSON 404, and `/insights` still returns JSON rather than the app.

### 8. Missing web build doesn't take down the API — FR-016 / FR-018

Temporarily rename `web/dist` and start the backend. **Expected**: a logged warning, the API serving
normally, and the Android app unaffected. A backend that refuses to start over a missing web build
breaks the phone for a reason that has nothing to do with the phone.

### 9. Nothing new leaves the machine — FR-013 / SC-010

> **Current behavior (2026-08-14):** this migration-era Claude check is superseded. Entry analysis
> now runs through the separate local Ollama worker and no diary text leaves the machine.

With `ANTHROPIC_API_KEY` unset, the whole app works: the feeling suggestion falls back to `neutral`
at confidence `0.0` and pattern narratives use the templated wording, **word for word identical** to
the Python fallback. With the key set, the only outbound traffic is to the Claude API, as before.

### 10. It is no slower — SC-007

Save an entry, open a day, a month, and insights. None should feel slower than before. Compare
against the Python backend on the same diary rather than against a stopwatch target.

### 11. Rollback works — US5 / FR-017 / SC-009

Stop the new backend, restart the old one against the same file, confirm the diary is intact and both
clients work. Target: under 15 minutes, no conversion in either direction.

**Then write an entry on the new backend, revert, and check it is still there.** It should be — the
schema is unchanged, so post-switch entries are readable by the old backend. FR-017 requires the
maintainer to know this for certain rather than assume it.

---

## Definition of done

- [ ] Scenario 1 passes — the hash is unchanged. Nothing else counts until this does.
- [ ] All 71 behaviours covered by the Python suite are covered and passing on the new backend (FR-012).
- [ ] Differential run over a realistic diary shows no unexplained response difference.
- [ ] Both clients work with zero changes (SC-004).
- [ ] The Python backend is still present and runnable (FR-019) — **removing it is not part of this feature.**
- [ ] The `entry_date` clock mismatch and the topic-extraction bug are still present, still tested, and each has a follow-up recorded.
