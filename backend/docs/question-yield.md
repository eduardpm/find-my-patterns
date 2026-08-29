# Guided-question topic yield (SC-008)

Guided questions exist to produce extractable topics for the pattern engine — that is their whole
job, stated as a product decision, not an implementation detail. `GET /insights/question-yield`
measures whether they do it, so a question's copy can be judged by results instead of by feel
before and after a wording change (UX-8a).

## Endpoint

```
GET /insights/question-yield?from=YYYY-MM-DD&to=YYYY-MM-DD
```

`from` and `to` are both optional and filter on `diary_entries.entry_date`, inclusive on both
ends. Omit either to leave that side of the window open; omit both to measure the whole diary.
Malformed dates, or a `from` after `to`, answer `422 validation_error`.

```json
{
  "from": "2026-08-01",
  "to": "2026-08-31",
  "overall": {
    "guided_entries": 40,
    "guided_entries_yielding": 37,
    "rate": 0.925
  },
  "questions": [
    {
      "question_key": "energy_today",
      "wording_snapshot_latest": "What gave you energy today?",
      "answered": 22,
      "yielded": 19,
      "rate": 0.8636363636363636
    }
  ]
}
```

## Reading it

- **`overall.rate` is the SC-008 number.** It is the share of guided (non-draft) entries in the
  window that carry at least one linked topic, measured at the entry level regardless of which
  question produced it. The target is **≥ 0.90**. `null` means there were no guided entries in the
  window — not zero yield, no denominator.
- **`questions[]` is the per-question breakdown**, which is where a copy problem actually gets
  found and fixed. `answered` counts guided entries that answered that question in the window;
  `yielded` counts those where that specific answer is attributed at least one topic (see
  Attribution rule below); `rate` is `yielded / answered`, or `null` if the question was not
  answered at all in the window.
- **`wording_snapshot_latest`** is the most recent `question_text_snapshot` recorded against that
  key in the window — the prompt text as the person actually saw it when they answered, not
  `guiding_questions.prompt_text` (which only ever holds the _current_ wording). If a copy change
  lands mid-window, this field reflects the newer wording as soon as anyone has answered under it,
  which is what lets a before/after comparison for UX-8a be built by running this endpoint once
  with `to` set just before the change and once with `from` set just after.

## Attribution rule

`entry_topics` links a topic to the **entry**, not to the individual guided answer that produced
it — extraction (`src/topics/topics.service.ts`) always runs over an entry's whole `raw_text`, and
the schema has no finer-grained record. To credit a topic back to the one answer responsible, an
answer is counted as having **yielded** a topic when that topic's canonical name or one of its
recorded aliases (`topics.aliases`) appears as a whole word or phrase inside the _answer's own
text_ — the same `mentions()` word-boundary match the keyword extractor itself uses
(`src/topics/canonicalization.ts`), applied here per-answer instead of per-entry.

This is a stated approximation:

- a topic mentioned in two different answers on the same entry credits both, because stored data
  cannot say which answer the extractor actually matched, and crediting neither would undercount
  as badly as crediting both overcounts;
- a topic linked to the entry via free text a client appended outside the guided answers (an edge
  case `raw_text` allows) can credit an answer that never mentioned it, for the same reason — the
  entry is the only place `entry_topics` looks;
- only topics _currently_ linked to the entry are considered. `entry_topics` is derived, recomputed
  data (`PatternsService.recomputePatterns`, run on every `GET /insights`), so editing an entry's
  text changes its yield the next time that recompute runs, not retroactively per historical
  answer.

The implementation lives in `src/insights/question-yield.service.ts`, with the same rule restated
there next to the code it governs.

## Scope

Unfinalized guided drafts (an entry whose `raw_text` is still the draft sentinel) are excluded
throughout, the same way `EntriesRepository` excludes them elsewhere — a draft is not yet an entry
the user kept, so it is not evidence about a question's yield.

Out of scope for this endpoint, deliberately: changing question copy (that is UX-8a's job, not
this measurement's), any client-facing UI, and automated A/B testing of question wording. This is
a read-only report over data that already exists.
