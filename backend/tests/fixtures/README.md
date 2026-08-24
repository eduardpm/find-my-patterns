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
