# Test strategy

**The spec is the source of truth.** Every test here asserts something a spec asks for — not
something a previous implementation happened to do. Where the two ever disagreed, the spec won.

| Suite                                         | Asserts                                                                                            |
| --------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `codecs.test.ts` (26)                         | The stored byte formats. Not a style choice — see below.                                           |
| `unit/pure-logic.test.ts` (20)                | The minimum-occurrence rule, keep/change direction, topic matching (002 FR-009/FR-011/FR-012)      |
| `contract/read-endpoints.test.ts` (14)        | `GET /feelings`, `/guiding-questions`, `/entries`, `/monthly-summary` against contracts/api.md     |
| `contract/entries-write.test.ts` (21)         | The version rule, the three 409 guarantees, guided-entry derived values (003 FR-011/FR-021/FR-023) |
| `contract/static-hosting.test.ts` (10)        | `/app` serving, SPA fallback, API not shadowed, `no-store` headers (003 FR-016/FR-024/FR-025)      |
| `compatibility.test.ts` (6)                   | Refuse to serve a diary that can't be fully interpreted (004 FR-018)                               |
| `no-ddl.test.ts` (8), `seed-noop.test.ts` (3) | The backend never alters the diary's schema or reference rows (004 FR-020/FR-022)                  |
| `fidelity/no-write-on-read.test.ts` (4)       | Startup and read-only endpoints leave the file byte-identical (004 SC-011)                         |
| `init-db.test.ts` (7)                         | Creating a new diary: correct schema, seeded, empty, and refuses to touch an existing file         |
| `pattern-lifecycle.test.ts` (1)               | Editing a topic out of an entry removes its derived pattern support                                |
| `backup.test.ts` (2)                          | Online backups are valid, private, and never overwrite an existing snapshot                        |
| `migrate-db.test.ts` (6)                      | Growing an existing diary to the grouped vocabulary adds reference data and touches no entry       |
| `unit/feeling-vocabulary.test.ts` (11)        | The vocabulary's invariants, and how the analyser's proposal is reconciled                         |
| `unit/suggestion-guard.test.ts` (13)          | The guard between the model's advice and the user (FR-010)                                         |
| `e2e/insights-pipeline.test.ts` (12)          | Written entries to discovered insights, end to end, with **no model involved**                     |
| `e2e/insight-scenarios.test.ts` (40)          | 22 ways the Insights view could mislead. Six guarded, sixteen open defects — see below             |
| `e2e/llm-analysis.eval.test.ts` (19)          | What the local model makes of an entry, and of an insight. **Opt-in** — see below                  |

## The two halves of "does this work end to end"

`e2e/insights-pipeline.test.ts` is a normal test and runs with everything else. It starts from an
**empty** diary, writes a corpus a human can grade by hand, and asserts the insights _exactly_ —
including that a `(topic, feeling)` pair seen only twice produces nothing. Every claim it checks is
one the app makes to the user as a fact, so under Principle III none of it may depend on a model,
and none of it does: feelings are set explicitly and topics come from the keyword extractor.

`e2e/llm-analysis.eval.test.ts` is the other half, and it is an **evaluation**, not a unit test.
Model output is not reproducible, so it grades the _band_ the model has to land in rather than the
exact word — whether a sleepless, dragging day reads as **Low** rather than **Uplifted**, not
whether it reads as `exhausted` rather than `sleepy`. The grouped vocabulary is what makes that band
expressible at all. It also runs the real worker over four naturally-worded entries about one habit
and checks that a relevant insight actually surfaces, which is the product's whole promise in one
assertion.

It is skipped by default, because it needs a local Ollama and takes ~20s rather than ~1s:

```
RUN_LLM_EVAL=1 npm test -- tests/e2e/llm-analysis.eval.test.ts
```

It uses whatever `OLLAMA_MODEL` names (default `qwen3:4b`) and prints the Insights view as the user
would read it, so it doubles as the way to check a candidate model before switching to it. Measured
over three consecutive runs on `qwen3:4b`, every case passed and the wording stayed close.

## The scenario corpus, and what it says about the Insights view

`fixtures/insight-scenarios.json` holds 22 diary situations chosen to attack the Insights view
rather than exercise it. Seventeen of them currently find something wrong, which is the point: the
corpus is a standing inventory of what the pattern engine cannot yet do, expressed as tests rather
than as a document that goes stale.

The mechanism matters. A `defect` scenario asserts the **correct** behaviour and runs under
`it.fails`, so it passes while the defect exists and fails once the defect is fixed. Nobody has to
remember to come back and delete a `skip`. `fixtures/README.md` covers the format; adding a
scenario needs no code.

The defects cluster into four kinds, and the first is much the most serious:

1. **The engine counts co-occurrence, so it cannot tell influence from background.** A diary where
   one feeling dominates reports every topic as a cause of it. Two things that always happen
   together are reported as two independent causes. A coping strategy is reported as if it were the
   trigger. `specs/research/diff-1-base-rate-patterns.md` and `diff-2-temporal-precedence.md`
   already design the fixes; these scenarios are what will tell you when they land.
2. **Topic extraction reads mentions, not events.** "No coffee today" and "I should cut down on
   wine" both register as the habit happening.
3. **`direction` is derived from valence alone**, so any non-positive feeling produces advice to
   change the topic — including medication, an illness, a menstrual cycle, and a person.
4. **The view has no ranking and no time window.** Entries from over a year ago are described as
   "recent", and nothing orders insights by strength.

The ranking gap is deliberately **not** in the corpus. Ordering is by `last_updated_at` with the
pattern id as tiebreaker, and patterns written in one recompute land microseconds apart, so the
result is arbitrary rather than reliably wrong: measured over 8 fresh diaries, 7 put a
3-occurrence insight above a 20-occurrence one and 1 did not. A test asserting "strongest first"
would therefore flake around one run in eight, which is worse than a documented gap. What _is_
tested is the half that holds — the same diary reads the same way twice.

## The two halves of an insight

An insight is one observation and one suggestion, and they are held to different standards because
they make different kinds of claim:

|                                                                                 | Written by                                 | Tested by                                            |
| ------------------------------------------------------------------------------- | ------------------------------------------ | ---------------------------------------------------- |
| `narrative_text` — "You felt energised in 3 recent entries mentioning walking." | `observationFor`, deterministic            | asserted **exactly**                                 |
| `suggestion_text` — "Try a short walk on the days you start out flat…"          | the local model, behind `acceptSuggestion` | the guard is asserted exactly; the wording is graded |

Every number the app shows the user is in the observation, where it was measured. The model is
never told the count and never allowed to state one — see `acceptSuggestion` for what that means in
practice, including the ban that turned out to be too blunt and why it was narrowed.

Narration runs in the worker, never on the request path: `GET /insights` writes a plain template
and returns, so the view is never blank and never waits on a cold model. The better wording lands
on a later read. That is also why a fresh insight can show the placeholder for a moment — it is
correct, just dull.

## Why the byte formats are pinned — and how much that is actually worth

`codecs.test.ts` asserts that timestamps are stored as `2026-07-28 12:33:49.248359` and JSON arrays
as `["ate", "drank"]`. **Be honest about where that requirement comes from.**

It is _not_ forced by existing data. As of the NestJS switch the diary held zero entries, zero
patterns and zero topics — no stored datetime anywhere. The formats were inherited from the previous
implementation, and describing them as a data-compatibility requirement would be justifying a choice
after the fact.

What genuinely constrains the **wire** format is the installed Android app: it parses `created_at`
with a statically-typed serializer, and changing the shape means rebuilding and reinstalling it. That
is a real cost, but a small and entirely reversible one.

So the formats are kept for two modest reasons — a client already parses them, and churning a format
buys nothing — not because data forces it. If a diary from the previous backend is ever restored, it
still reads; that is a bonus, not the rationale.

The one part that is unambiguously worth its keep is that a _single_ module owns all encoding.
Node's defaults differ from the stored shape in ways that fail silently (`toISOString()` truncates to
milliseconds and appends `Z`; `JSON.stringify` emits non-ASCII literally), so wherever the format
lands, it should land in exactly one place.

**Open question worth deciding deliberately:** move to plain ISO-8601 (`…T12:33:49.248Z`) and standard
`JSON.stringify`, dropping the microsecond synthesis entirely. It costs one Android rebuild and would
delete real complexity from `codecs.ts`.

## `tests/fixtures/golden.db`

A small diary used as test input. It exercises freeform and guided entries, all four feeling
sources, an entry with no text, a guided entry citing an unknown question key, multi-feeling days,
and a qualifying pattern. Not committed (#83) — built from `tests/fixtures/golden-seed.json` and
the current schema on every `npm test` run. See `fixtures/README.md` and
`../docs/golden-fixture.md`.

## Known behaviour worth revisiting

**`entry_date` uses the server's local calendar date while `created_at` uses UTC.** On a machine not
running UTC these disagree near midnight, so an entry can carry a timestamp whose UTC date differs
from the day it is filed under. Every existing entry was filed this way, and day grouping, the
monthly calendar and the daily average all key off `entry_date`.

No spec mandates either clock, so this is not a violation — but it is a latent inconsistency, and
changing it would re-file existing entries onto different days. It deserves its own spec rather than
a quiet fix. `codecs.ts` exposes the two clocks as `nowUtc()` and `todayLocal()` so the choice is at
least explicit.
