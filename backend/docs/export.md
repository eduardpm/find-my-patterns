# Plain-text export (M-6)

The only export before this was a raw SQLite copy (`npm run backup`) — useful for a backup, useless
for a person who wants to read or move what they wrote. `GET /export` answers the whole diary in
two human- and machine-readable formats, and stays **free forever**: paywalling read-back is
Daylio's most common one-star complaint, and this product's monetization rules forbid it (see
`specs/research/daylio-competitive-analysis.md` §11).

This is also the contract the Daylio import (L-1b) is built against — a field renamed or dropped
here without bumping `schema_version` breaks that ticket silently.

## Endpoint

```
GET /export?format=markdown|json
```

`format` is required; anything else, including a missing value, answers `422`. The whole diary is
streamed back in one response — there is no pagination or date-range parameter, deliberately: this
endpoint exists so a person can walk away with everything, not a slice of it.

The response carries a `Content-Disposition: attachment` header naming the file
`find-my-patterns-export-YYYY-MM-DD.{md,json}`, where the date is _today_, not the diary's date
range — the same role a backup's filename plays in `npm run backup`. `Content-Type` is
`application/json; charset=utf-8` for JSON and `text/markdown; charset=utf-8` for Markdown.

Both formats are read-only and unencrypted. Import, a PDF/therapy report, and encrypting the export
file are explicitly out of scope for this ticket.

## Determinism

Two exports run back to back over an unchanged diary are byte-identical. That is enforced by
construction, not by luck:

- entries are ordered by `created_at` (`EntriesRepository.findAll`), and every child collection —
  guided answers, topics, topic↔feeling pairings — is itself ordered (`order_index`, topic name,
  topic name then feeling key);
- neither format ever serializes a JSON object whose key order depends on iteration order over a
  `Map` or a `Record` — feelings, topics and pairings are all built as ordered arrays instead;
- neither format includes a "generated at" timestamp or anything else derived from the wall clock.
  The `Content-Disposition` filename is the one exception, and it is stable within a day, which is
  what the determinism test relies on.

## JSON

```json
{
  "schema_version": 1,
  "entries": [
    {
      "id": "b6f1b6b0-...",
      "date": "2026-08-28",
      "created_at": "2026-08-28T23:11:00.248359",
      "mode": "guided",
      "raw_text": "What gave you energy today?\nA good run before work.\n\n...",
      "guided_answers": [
        {
          "question_key": "energy_today",
          "question_text": "What gave you energy today?",
          "answer_text": "A good run before work.",
          "order_index": 0
        }
      ],
      "feelings": [
        { "key": "stressed", "source": "confirmed", "intensity": 3 },
        { "key": "anxious", "source": "confirmed", "intensity": null }
      ],
      "topics": [{ "topic": "work", "surface_form": "work" }],
      "topic_feelings": [
        { "topic_id": "3c9e...", "topic": "work", "feeling_key": "stressed", "source": "confirmed" }
      ]
    }
  ]
}
```

`schema_version` is bumped whenever a field is added, renamed or removed — check it before parsing
anything else. `entries` is ordered by `created_at`; `id` is the entry's row id, `date` is
`entry_date` (`YYYY-MM-DD`), `created_at` is the naive datetime the entry was written at
(`YYYY-MM-DDTHH:MM:SS.ffffff`, no timezone — the diary has never stored one; see
`src/db/codecs.ts`).

`guided_answers` is empty for a freeform entry, one element per answer (in `order_index` order) for
a guided one. `question_text` is the **wording snapshot** recorded at answer time
(`guiding_question_answers.question_text_snapshot`), not the question's current prompt text — a
copy change made after the entry was written never rewrites history here.

### Feelings

Every entry serves the feelings it carries as an array, one element per feeling, in the order the
user (or the analyser) put them in — the same order `GET /entries` serves `feeling_keys` in.
`intensity` is `1`–`5` or `null` when that particular feeling was never rated.

**`source` is entry-level, not per-feeling.** The diary only ever stores one
`feeling_source` (`'unset' | 'suggested' | 'confirmed' | 'overridden'`) per entry — it describes how
the whole feeling _set_ was arrived at, not each feeling individually — so this field repeats that
one value on every feeling in the array. An entry with `Stressed` and `Anxious` both confirmed in
the same edit exports as `source: "confirmed"` on both; the schema has no way to say "I confirmed
one and the analyser only ever suggested the other" and does not claim to. A future schema version
that wants true per-feeling provenance needs a new stored column, not a new export field — there is
nothing this endpoint can read that the diary does not already have.

### Topics

`topics` lists the canonical topics linked to the entry (`entry_topics` joined to `topics.name`),
ordered by name. Each element carries the same string twice, as `topic` and `surface_form`.

That duplication is honest, not decorative. `entry_topics` records _which canonical topic row_ a
mention resolved to (`work`, say) but never _the words that were actually written_
(`"deadline"`, `"my boss"`) — extraction is keyword matching over the whole entry
(`src/topics/canonicalization.ts`), and nothing about which literal phrase matched survives past
that pass. `surface_form` exists in the field list because a plain-text export naming only the
canonical form reads oddly next to prose that never used that word, but until the schema grows a
place to store the matched phrase per mention, this field cannot do anything other than repeat
`topic`. **The Daylio import (L-1b) should not treat `surface_form` as evidence of the entry's
actual wording** — read `raw_text` for that.

`topic_feelings` is the E-1a topic↔feeling pairing set for the entry — not in the original issue's
field list, added because a mixed-valence entry's confirmed or overridden sub-entry attributions
are exactly the kind of user-confirmed data this ticket exists to make sure export never drops.
`source` here is `'suggested' | 'confirmed' | 'overridden'` (`PairingSource` — no `'unset'`: a pair
nobody proposed or chose simply has no row) and, unlike the entry-level feeling source above, it
already is per-pairing — an entry can confirm one topic↔feeling pair and override another in the
same edit, and this field says so correctly.

## Markdown

One `##` section per entry, ordered by `created_at`, oldest first:

```markdown
## 2026-08-28 — 11:11 PM

**What gave you energy today?**
A good run before work.

Feelings: Stressed (3/5, confirmed) · Anxious (confirmed)
Topics: work, deadline
```

- The heading is the entry's date (`entry_date`) and the time it was created, rendered as `h:mm
AM/PM` (no leading zero on the hour).
- **Guided entries** render one block per answer: the wording snapshot in bold, the answer text
  below it, in `order_index` order — the same paragraph-per-answer shape `raw_text` itself is
  composed in (see `EntriesService.createEntry`).
- **Freeform entries** render `raw_text` as-is.
- `Feelings:` lists every feeling on the entry, `·`-separated, as `Label (intensity/5, source)` when
  rated or `Label (source)` when not. The line is omitted entirely for an entry with no feelings.
- `Topics:` is the canonical topic names, comma-separated. Omitted for an entry with no topics.
  Topic↔feeling pairings (`topic_feelings`) are JSON-only — there is no Markdown rendering for them,
  since the format's whole point is prose a person reads back, and "topic X paired with feeling Y"
  is not prose.

Unfinalized guided drafts (an entry whose `raw_text` is still the internal draft sentinel) are
excluded from both formats, the same way `EntriesRepository` excludes them from every other read.

## Scope

Out of scope for this endpoint, per the issue: import, a PDF/therapy report, and encrypting the
export file. This is a read-only dump of what `GET /entries` already serves, reshaped for a person
to carry away or hand to another tool.
