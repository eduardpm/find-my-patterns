# Phase 1 Data Model: Re-platform the Backend onto NestJS

> **⚠️ Superseded in part (2026-07-29).** The Python backend was deleted, the differential test
> strategy was dropped, and the deliberately-ported topic-matching defect was fixed — because the
> **spec**, not the previous implementation, is the source of truth. The new backend now lives at
> `backend/`. Read the **Outcome** section at the top of [spec.md](./spec.md) before relying on
> anything here.

**This feature models nothing new.** Every entity keeps the meaning defined in
[002's data-model.md](../002-mood-pattern-diary-mobile/data-model.md) and
[003's](../003-web-client/data-model.md). What follows is therefore not a design — it is a
**fidelity specification**: the exact on-disk shape the new backend must read and reproduce, captured
from the live database rather than inferred from the models.

Per FR-020/FR-021/FR-022 the schema is **frozen and adopted as-is**. The new backend issues no DDL.

## The schema, as it actually exists

```sql
CREATE TABLE feelings (
  "key" VARCHAR(32) NOT NULL, label VARCHAR(64) NOT NULL, valence VARCHAR(16) NOT NULL,
  PRIMARY KEY ("key"));

CREATE TABLE guiding_questions (
  "key" VARCHAR(64) NOT NULL, category VARCHAR(32) NOT NULL, prompt_text VARCHAR(256) NOT NULL,
  trigger_keywords JSON NOT NULL, is_mandatory BOOLEAN NOT NULL, PRIMARY KEY ("key"));

CREATE TABLE topics (
  id VARCHAR(36) NOT NULL, name VARCHAR(128) NOT NULL, aliases JSON NOT NULL,
  first_seen_at DATETIME NOT NULL, last_seen_at DATETIME NOT NULL,
  PRIMARY KEY (id), UNIQUE (name));

CREATE TABLE diary_entries (
  id VARCHAR(36) NOT NULL, created_at DATETIME NOT NULL, updated_at DATETIME NOT NULL,
  entry_date DATE NOT NULL, mode VARCHAR(16) NOT NULL, raw_text TEXT NOT NULL,
  feeling_key VARCHAR(32), feeling_source VARCHAR(16) NOT NULL,
  version INTEGER DEFAULT '1' NOT NULL,
  PRIMARY KEY (id), FOREIGN KEY(feeling_key) REFERENCES feelings ("key"));

CREATE TABLE guiding_question_answers (
  id VARCHAR(36) NOT NULL, entry_id VARCHAR(36) NOT NULL, question_key VARCHAR(64) NOT NULL,
  question_text_snapshot VARCHAR(256) NOT NULL, answer_text VARCHAR(1024) NOT NULL,
  order_index INTEGER NOT NULL, PRIMARY KEY (id),
  FOREIGN KEY(entry_id) REFERENCES diary_entries (id) ON DELETE CASCADE,
  FOREIGN KEY(question_key) REFERENCES guiding_questions ("key"));

CREATE TABLE entry_topics (
  entry_id VARCHAR(36) NOT NULL, topic_id VARCHAR(36) NOT NULL, extracted_by VARCHAR(16),
  PRIMARY KEY (entry_id, topic_id),
  FOREIGN KEY(entry_id) REFERENCES diary_entries (id) ON DELETE CASCADE,
  FOREIGN KEY(topic_id) REFERENCES topics (id) ON DELETE CASCADE);

CREATE TABLE patterns (
  id VARCHAR(36) NOT NULL, topic_id VARCHAR(36) NOT NULL, feeling_key VARCHAR(32) NOT NULL,
  occurrence_count INTEGER NOT NULL, narrative_text VARCHAR(512) NOT NULL,
  suggestion_text VARCHAR(512) NOT NULL, direction VARCHAR(16) NOT NULL,
  first_detected_at DATETIME NOT NULL, last_updated_at DATETIME NOT NULL,
  PRIMARY KEY (id), FOREIGN KEY(feeling_key) REFERENCES feelings ("key"),
  FOREIGN KEY(topic_id) REFERENCES topics (id));

CREATE TABLE pattern_entries (
  pattern_id VARCHAR(36) NOT NULL, entry_id VARCHAR(36) NOT NULL,
  PRIMARY KEY (pattern_id, entry_id),
  FOREIGN KEY(entry_id) REFERENCES diary_entries (id) ON DELETE CASCADE,
  FOREIGN KEY(pattern_id) REFERENCES patterns (id) ON DELETE CASCADE);

CREATE TABLE alembic_version (            -- NOT OURS. Never read, never written.
  version_num VARCHAR(32) NOT NULL, CONSTRAINT alembic_version_pkc PRIMARY KEY (version_num));
```

## Value encoding — the part that breaks silently

SQLite has no date, boolean or JSON types; these columns hold text and integers whose format was
chosen by the previous stack. **Reproducing that format exactly is a requirement, not a detail.**

| Column type | Stored as | Example (captured live) | What Node produces by default |
|---|---|---|---|
| `DATETIME` | `YYYY-MM-DD HH:MM:SS.ffffff`, space-separated, **naive**, microseconds | `2026-07-28 12:33:49.248359` | `2026-07-28T12:33:49.248Z` — wrong separator, lost precision, false zone |
| `DATE` | `YYYY-MM-DD` | `2026-07-28` | full ISO datetime |
| `JSON` | `json.dumps` default separators — **space after each comma** | `["ate", "drank", "coffee"]` | `["ate","drank","coffee"]` |
| `BOOLEAN` | integer | `1` / `0` | `true` / `false` |
| `id` | UUID v4, lowercase, hyphenated, stored as text | `5cd59243-637a-…` | — |

Every one of these differences is silent: nothing throws, the app appears to work, and the diary
quietly acquires two formats. A single codec module owns all of them (research.md §1).

**Microseconds have no built-in source in Node.** `Date` is millisecond-resolution, so the final
three digits must be composed deliberately rather than dropped or zero-padded by accident — a
timestamp ending `.248000` is a visible tell that the port is lossy.

## Derived values — the third fidelity boundary

The plan identified two boundaries where Python's defaults must be reproduced: the byte format on
disk and the byte format on the wire. There is a **third**, found during `/speckit-analyze`: values
the backend *computes* from user input before storing them. These are not visible in the schema, are
not covered by the codecs, and diverge silently — a different separator produces a different stored
entry, which the user can see, and which topic extraction then reads differently, which changes
detected patterns. That chain ends at SC-002/SC-005.

All values below were captured from the running system.

### `diary_entries.raw_text` for a guided entry

Composed from the submitted answers as **`"{prompt_text} {answer_text}"` per answer, joined by a
single space**, in submission order. No punctuation is inserted, no newlines, no trailing separator.

Given answers `[(general_feeling, "Sluggish after lunch"), (food_drink, "Had a coca cola")]`, the
stored `raw_text` is exactly:

```
What's going on, and how are you feeling? Sluggish after lunch What did you eat or drink? Had a coca cola
```

The composition happens **only when `mode` is `guided`, answers are present, and the submitted
`raw_text` is empty**. A guided submission that also carries `raw_text` keeps the submitted text
untouched.

### `guiding_question_answers.question_text_snapshot`

The **prompt text of the referenced question at answer time** — which is why the column exists: later
edits to the question library must not rewrite history. If the `question_key` matches no known
question, it falls back to **the `question_key` string itself**, and that same fallback value is what
gets used in the `raw_text` composition above.

### `guiding_question_answers.order_index`

The zero-based position of the answer in the submitted array. Not re-sorted.

### `entry_topics.extracted_by`

Always written as **`"keyword"`** by the current extractor, despite the column being nullable. A port
that writes `NULL` — the natural reading of "nullable" — diverges on every topic link it creates.

## Enumerated values

Stored as plain strings; the new backend must accept and emit exactly these, and must not normalise
case or ordering.

- `diary_entries.mode` — `guided` | `freeform`
- `diary_entries.feeling_source` — `unset` | `suggested` | `confirmed` | `overridden`
- `feelings.valence` — `positive` | `neutral` | `negative`
- `patterns.direction` — `keep` | `change`
- `entry_topics.extracted_by` — `llm` | `keyword`, nullable

## Behavioural rules the storage layer must preserve

These are the rules the 71 existing tests pin down. They are data-model concerns because getting any
of them wrong changes what ends up in the file.

**Entry versioning (FR-009).** `version` starts at 1 and increments by exactly 1 on each successful
mutation. A mutation whose supplied version does not match is rejected **before anything is written**
and does **not** increment. The check and the write belong in one transaction.

**Feeling-source transitions.** `unset → suggested` on creation when text is present; then
`confirmed` if the user's chosen feeling equals the one already suggested, `overridden` otherwise.
The comparison is against the *previously suggested* value and only applies when the current source
is `suggested` — a subtlety that is easy to lose in a rewrite.

**The two clocks.** `created_at`/`updated_at` come from UTC; `entry_date` comes from the server's
**local** calendar date. This is a latent defect (research.md §3) and is reproduced deliberately,
because existing rows were written under it.

**Cascades.** Deleting an entry removes its guided answers, its topic links and its pattern links.
SQLite does not enforce `ON DELETE CASCADE` unless `PRAGMA foreign_keys = ON` is set per connection —
the previous stack managed these cascades in the application layer, so the port must either set the
pragma or delete children explicitly. Doing neither leaves orphans that inflate later pattern counts.

**Topic identity.** `topics.name` is unique. Extraction is find-or-create by canonical name and is
idempotent: re-running it over the same entry must not duplicate a link or create a second topic row.

**Pattern recomputation.** Patterns are recomputed on read. Only entries whose feeling is `confirmed`
or `overridden` count as evidence. A pair qualifies at **3** occurrences. `last_updated_at` is stamped
**only when the pattern actually changed** — an unconditional stamp made the field meaningless and
made two clients disagree (fixed during feature 003; the port must not reintroduce it).

**Monthly aggregation.** `totals_by_feeling` counts **entries**; `days[].feelings` is the **distinct
set** per day, sorted. The daily average divides total entries by *days elapsed* — the day-of-month
for the current month, the full month length otherwise. These differ deliberately and a client-side
re-tally disagrees with the server, which is the trap feature 003's calendar test relies on.

## Seeding

`feelings` and `guiding_questions` are seeded only when empty. Against an existing diary the seed
must therefore be a **no-op** — if it inserts or updates anything on a populated database, FR-022 is
violated and the byte-comparison test in quickstart.md will catch it.
