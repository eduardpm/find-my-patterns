# Topic identity resolution (A4 / #22)

Every proposed topic — whichever half of the app found it — resolves to a canonical name in
exactly one place: `canonicalTopicName` in `canonicalization.ts`. Every consumer of topic identity
calls it (directly, or transitively through `TopicsService`) rather than deciding equivalence on
its own:

| Consumer                                                                         | Resolves through                                                                              |
| -------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| Keyword extraction on write (`TopicsService.linkTopics`, `extractAndLinkTopics`) | `canonicalTopicName`                                                                          |
| Model-proposed topics on write (`inference/worker.ts`, `applyAnalysis`)          | `canonicalTopicName`                                                                          |
| Model-proposed topic↔feeling pairings (`entry_topic_feelings`, E-1a)             | `canonicalTopicName` (same call site as the topic write, just above it)                       |
| Pattern engine (`patterns.service.ts`)                                           | reads `entry_topics.topic_id`, already canonical by construction                              |
| Entry echo (`echo.service.ts`, `matchExistingTopics`)                            | matches text against each topic's stored name **and** aliases                                 |
| Topics listing (`GET /topics`)                                                   | reads the `topics` table directly — one row per canonical idea                                |
| Consolidation (`TopicsService.mergeFragmentedTopics`)                            | re-resolves every existing row against every other, folding a fragment into its canonical row |

`mergeFragmentedTopics` runs at the start of every `recomputePatterns()` call, which is what makes
a user-added alias (`POST /topics/:id/aliases`) take effect on the **next** `GET /insights` —
never immediately, and never by re-running the model.

## The rules, in the order they are tried

1. **The curated list** (`CURATED_TOPIC_KEYWORDS`) — the project's own vocabulary. The only place a
   claim like "a project review is work" is allowed to be made.
2. **An existing topic's name or alias**, matched exactly after normalisation. This is what makes a
   user-added alias take effect.
3. **The same words wearing different endings** — "project meetings" is "project meeting" (crude,
   deliberately: see `stemToken`).
4. **One phrase's words inside another's** — "review" and "project review" are the same subject at
   two lengths; the shorter is kept as canonical.

A proposal that matches none of the above is stored under its own normalised name — the mapping is
a preference, never a filter (a genuinely new topic is never dropped).

## Normalisation hygiene

`normalizeTopicName` is the one function every proposed or stored topic name passes through:
lowercased, trimmed, punctuation stripped, whitespace collapsed. "Walking", "walking " and
"Walking." are one string before any rule above ever sees them — case and incidental whitespace
never split identity. Singular/plural is deliberately out of scope beyond the crude stemming in
rule 3 above (see `stemToken`'s doc comment for why it stops there); real stemming is model-side
work, not this module's.

## What "merging" actually moves

`mergeFragmentedTopics` moves `entry_topics` links from the fragment row to the canonical row, and
keeps the fragment's name as a new alias on the canonical row — so the word the user actually wrote
still matches their entries. It never touches an entry, an `entry_feelings` row, or a confirmed
feeling. A pattern left pointing at a row that just disappeared is withdrawn on the next recompute
with reason `topic_merged`, rather than silently vanishing.

## A boundary worth knowing

`POST /topics/:id/aliases` rejects an alias string that already names another existing topic row —
two topics that already exist independently cannot be folded together through this endpoint, only
through the automatic rules above (which need a curated, alias, stem, or subset match to fire on
their own). A merge-suggestion UI for the general "these two unrelated-looking rows are the same
thing" case is out of scope (see the issue this file was added for, #22).

## What is not a topic

Context factors (`weekday:sunday`, `timeofday:evening`, `season:winter`, …) produced by
`PatternsService.contextPatterns()` are a different axis entirely — a passive fact about _when_ an
entry was written, never something extracted from its text. Nothing in this module or in
`contextPatterns()` ever runs a context factor key through `canonicalTopicName`; doing so would be
a category error, not a normalisation improvement.
