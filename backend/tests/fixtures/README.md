# Golden fixture

`golden.db` is a small diary used as test input. Tests copy it to a temp directory and work on the
copy, so it is never modified.

It deliberately contains one of everything that behaves differently:

| Case | Exercises |
|---|---|
| 3 × "coca cola … sleepy", confirmed | Enough to cross the 3-occurrence pattern threshold |
| An entry whose feeling was overridden | `feeling_source = overridden` |
| An entry left at `suggested` | The never-confirmed state |
| An entry with empty text | `feeling_source = unset`, `feeling_key = NULL` |
| A guided entry with two answers | `raw_text` composition, `question_text_snapshot`, `order_index` |
| A guided entry citing an **unknown** question key | The snapshot's fallback to the raw key |
| Materialised patterns | Real `patterns` and `pattern_entries` rows |

Contents: 8 entries, 3 guided answers, 6 topic links, 2 patterns, 2 topics.

It also carries an inert `alembic_version` table left by an earlier migration tool — kept on purpose,
because real diaries have one and the backend must ignore it.

## Regenerating

Start the backend against an empty diary, replay the cases above through the API, then call
`GET /insights` once to materialise patterns.

Regenerating changes every timestamp, so no test asserts a literal stamp *from this file* — the
codec tests use their own hardcoded values, which are independent of it.

## `insight-scenarios.json`

A corpus of 22 diary situations, each written to probe one way the Insights view could mislead
someone. Driven by `../e2e/insight-scenarios.test.ts`.

Every scenario carries the entries to write, the feelings the user settled on, and an `expect`
block describing **what the app should do** — never what it currently does. A `verdict` records
which of those two it is:

- `holds` (5) — the app already meets the expectation, and the test guards it.
- `defect` (17) — it does not. The test runs as a *failing* expectation, so the suite stays green
  while the problem exists and turns **red the moment it is fixed**, which forces this file to be
  updated in the same change rather than leaving a stale known-issues list behind.

A second block of tests re-runs every defect and checks it fails by *failing its expectation*
rather than by throwing — otherwise a misspelled topic in this file would masquerade as a known
defect and nobody would notice.

Scenarios are grouped by what they probe: statistical validity (base rate, confounding, reverse
causation, multiple comparisons, recency), text handling (negation, intention, attribution to
another person, word boundaries, non-English), safety and tone (medication, menstrual cycle,
illness, a partner, a reader in crisis, a neutral feeling), and presentation (ranking,
contradiction). Each names its `source`: the repo's own research under `specs/research`, the
n-of-1 self-tracking literature, or reasoning about a specific function.

Adding a scenario needs no code — add an object to `scenarios` and run the suite.
