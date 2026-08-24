# Phase 1 Data Model: Mood Pattern Diary Mobile App

Derived from the spec's Key Entities section, refined with the decisions in
[research.md](./research.md). All entities are owned by the backend (SQLite via SQLAlchemy); the
Android app holds client-side copies via the [API contract](./contracts/api.md).

## DiaryEntry

The core unit the user creates — everything else derives from it.

| Field | Type | Notes |
|---|---|---|
| `id` | UUID (PK) | |
| `created_at` | datetime | Set on creation; entries are never merged (FR-002) |
| `updated_at` | datetime | Bumped on edit (FR-008) |
| `entry_date` | date | Derived from `created_at`, used for day grouping and the monthly view |
| `mode` | enum: `guided` \| `freeform` | Which flow produced this entry (FR-004/FR-005) |
| `raw_text` | text | Freeform text, or the rendered/concatenated guided answers |
| `feeling_key` | FK → Feeling, nullable | Null = "unclassified" (see spec Edge Cases) |
| `feeling_source` | enum: `suggested` \| `confirmed` \| `overridden` \| `unset` | Tracks the hybrid flow in FR-007 |

**Validation**:
- `raw_text` must be non-empty for `freeform` mode.
- `guided` mode requires at least the mandatory general question answered (see GuidingQuestionAnswer).
- Deleting a DiaryEntry (FR-008) cascades to its GuidingQuestionAnswer rows and its EntryTopic links;
  any Pattern whose supporting-entry count drops below the minimum-occurrence threshold as a result
  is recomputed/removed on the next pattern-detection run (spec Edge Cases).

**State transitions**: `unset` → `suggested` (backend returns a Claude-suggested feeling on create) →
`confirmed` or `overridden` (user acts on the suggestion, per FR-007's acceptance scenario).

## GuidingQuestion

Static/config-like library entry, not user data — seeded once, editable later without app changes.

| Field | Type | Notes |
|---|---|---|
| `key` | string (PK) | `general_feeling`, `mind_body`, `small_influences`, `response_outcome` |
| `category` | enum: `general` \| `mind_body` \| `small_influences` \| `response_outcome` | |
| `prompt_text` | string | Shown to the user (FR-004) |
| `trigger_keywords` | list[string] | Used by the client to decide when to surface a non-general prompt (research.md §1) |
| `is_mandatory` | bool | True for the three core prompts; false for the situational follow-up |

## GuidingQuestionAnswer

One row per prompt the user actually answered on a given entry.

| Field | Type | Notes |
|---|---|---|
| `id` | UUID (PK) | |
| `entry_id` | FK → DiaryEntry | |
| `question_key` | FK → GuidingQuestion | |
| `question_text_snapshot` | string | Copy of the prompt text at answer time, so later edits to the library don't rewrite history |
| `answer_text` | string | |
| `order_index` | int | Preserves the order questions were answered in |

## Feeling

The fixed, predefined mood set (spec Assumptions) — not user-editable in v1.

| Field | Type | Notes |
|---|---|---|
| `key` | string (PK) | e.g. `happy`, `excited`, `neutral`, `sleepy`, `exhausted`, `stressed`, `sad`, `depressed` |
| `label` | string | Display name |
| `valence` | enum: `positive` \| `neutral` \| `negative` | Drives suggestion direction in FR-011 |

## Topic

A recurring subject the pattern engine tracks across entries.

| Field | Type | Notes |
|---|---|---|
| `id` | UUID (PK) | |
| `name` | string | Canonical form, e.g. "coca cola", "takeout" |
| `aliases` | list[string] | Optional variant spellings/synonyms folded into the same topic |
| `first_seen_at` / `last_seen_at` | datetime | |

## EntryTopic

Join table — an entry can mention more than one topic.

| Field | Type | Notes |
|---|---|---|
| `entry_id` | FK → DiaryEntry | |
| `topic_id` | FK → Topic | |
| `extracted_by` | enum: `llm` \| `keyword` | How this topic was identified in the entry |

## Pattern (Insight)

A detected, threshold-confirmed correlation between a Topic and a Feeling.

| Field | Type | Notes |
|---|---|---|
| `id` | UUID (PK) | |
| `topic_id` | FK → Topic | |
| `feeling_key` | FK → Feeling | |
| `occurrence_count` | int | Must be ≥ the minimum-occurrence threshold (FR-012; default 3 per spec Assumptions) |
| `supporting_entry_ids` | list[UUID] (join table `PatternEntry`) | Entries backing this pattern |
| `narrative_text` | string | Claude-generated plain-language description (FR-010) |
| `suggestion_text` | string | Claude-generated actionable suggestion (FR-011) |
| `direction` | enum: `keep` \| `change` | Derived from `Feeling.valence` |
| `first_detected_at` / `last_updated_at` | datetime | |

**Validation**: A Pattern is only created/kept once `occurrence_count` meets the threshold (FR-012);
recomputed whenever a supporting entry is edited/deleted (spec Edge Cases).

## Monthly Summary (derived, not persisted)

Computed on request from DiaryEntry + Feeling, not stored as its own table:
- Per month, per `feeling_key`: count of entries and count of distinct days that feeling appeared on.
- Average entries per day for that month (`total entries / days with ≥1 entry`, or `/ days in month`
  — see [contracts/api.md](./contracts/api.md) for the exact definition returned to the client).
- Per-day breakdown: which feeling(s) were logged, for calendar cell rendering (FR-015).
