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
and a qualifying pattern. Regenerate it by replaying those cases through the API — see
`fixtures/README.md`.

## Known behaviour worth revisiting

**`entry_date` uses the server's local calendar date while `created_at` uses UTC.** On a machine not
running UTC these disagree near midnight, so an entry can carry a timestamp whose UTC date differs
from the day it is filed under. Every existing entry was filed this way, and day grouping, the
monthly calendar and the daily average all key off `entry_date`.

No spec mandates either clock, so this is not a violation — but it is a latent inconsistency, and
changing it would re-file existing entries onto different days. It deserves its own spec rather than
a quiet fix. `codecs.ts` exposes the two clocks as `nowUtc()` and `todayLocal()` so the choice is at
least explicit.
