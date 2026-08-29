# Detailed Roadmap Specification — A1–A6, I1–I8

**Date:** 2026-08-26
**Status:** Draft
**Scope:** expands every item of `master-implementation-roadmap.md` into verifiable
requirements. Item IDs and the phase ordering are identical to the roadmap; this document is the
requirement-level detail under each.
**Convention:** `XX-n (MUST|SHOULD|NOT)` — MUST is mandatory and testable; SHOULD is expected
unless there is a documented reason otherwise; NOT is a prohibition. `XX-SCn` are the success
criteria that prove the item. All requirements below are written to be verified by unit test,
contract test, or inspection — never by taste.

---

## 0. Cross-cutting requirements — apply to every item

These hold for all fourteen items and are not repeated per item.

- **C-01 (MUST):** the backend is the only place that computes any number, threshold, rate,
  merge, or label introduced by these items. Clients render what they are given and compute
  nothing (constitution Principle VII).
- **C-02 (MUST):** web and Android clients show identical values for the same data, 100% of the
  time (extension of SC-005 in `specs/003-web-client/spec.md`).
- **C-03 (MUST):** no LLM output ever becomes a counted number or a stored fact. Where the model
  participates, it proposes; deterministic backend code decides (constitution Principle III).
- **C-04 (MUST):** only entries whose feeling source is `confirmed` or `overridden`
  (`CONFIRMED_FEELING_SOURCES`) may appear as evidence in any pattern, count, rate, echo, or
  aggregation introduced below. `suggested` and `unset` entries are never evidence.
- **C-05 (MUST):** every new surface must state its own numbers on the card — a user must never
  have to trust a label without the count that produced it.
- **C-06 (MUST):** recomputation stays lazy: all new engine features recompute on `GET /insights`
  (or the equivalent read), never on the write path, and never on the request path of a client
  that is merely saving an entry.
- **C-07 (NOT):** no feature below may add a cloud dependency, a network call to a third party,
  or a new persistent store of diary content outside the existing SQLite database.
- **C-08 (NOT):** no feature below may change the meaning or validity of existing `FR-*`
  requirements in `specs/002` and `specs/003` unless explicitly stated in the item.

---

## 1. Phase 1 — Make the evidence visible

### A1 — Evidence trail: tap a pattern → its supporting entries

**Business idea:** every pattern card opens to the exact entries that produced it. The audit
found `pattern_entries` is already written and pruned correctly but no client renders it. This
item makes "patterns you can audit" a visible property.

**Functional requirements**

- **A1-01 (MUST):** the backend serves, with each pattern, the list of supporting entries:
  entry id, entry date, raw text, confirmed feelings, and feeling source.
- **A1-02 (MUST):** the number of supporting entries returned equals the pattern's displayed
  occurrence count, 100% of the time. (Verifiable: contract test asserts
  `len(evidence) === occurrence_count` for every pattern in every fixture.)
- **A1-03 (MUST):** a supporting entry is returned only if its feeling source is in
  `CONFIRMED_FEELING_SOURCES` (C-04).
- **A1-04 (MUST):** the list is ordered by entry date, oldest first, deterministically
  (ties broken by entry id).
- **A1-05 (MUST):** each client renders the evidence trail on user action from the pattern card
  (tap/expand) — never requires navigating to Insights to see it.
- **A1-06 (MUST):** each entry in the trail is itself viewable/editable in the normal entry flow
  from the trail.
- **A1-07 (MUST):** after an entry in the trail is edited so it no longer supports the pattern,
  the next recompute removes it from the trail and updates the count; after a supporting entry is
  deleted, the same holds.
- **A1-08 (MUST):** the trail is recomputed from `pattern_entries`, not reconstructed by the
  client.
- **A1-09 (SHOULD):** each trail entry shows its feeling badge and date so the evidence is
  scannable without opening each entry.
- **A1-10 (NOT):** the client must not re-derive or filter the trail locally; it displays exactly
  the backend's list.

**Success criteria**

- **A1-SC1:** with three confirmed entries pairing topic X with feeling Y, the pattern shows
  count 3 and the trail returns exactly those three entries, identical on web and Android.
- **A1-SC2:** after editing one supporting entry to remove topic X and recomputing, the trail
  shows 2 entries and the count shows 2.
- **A1-SC3:** a `suggested`-source entry mentioning X and Y never appears in the trail, even
  though it would raise the count if it were counted.

---

### A2 — Visible withdrawals: "this pattern was dropped, and why"

**Business idea:** when recomputation removes a pattern (evidence fell below threshold), the user
is told — with the previous count, the new count, and the reason. Withdrawal becomes a
first-class, explainable event instead of a silent disappearance.

**Functional requirements**

- **A2-01 (MUST):** the backend records a withdrawal event whenever recompute drops a pattern
  that previously existed: pattern id, topic, feeling, previous occurrence count, new count,
  reason, timestamp.
- **A2-02 (MUST):** the reason is one of a fixed, deterministic set derived from data:
  `below_threshold` (count dropped below the minimum), `no_longer_confirmed`
  (supporting entries remain but none is confirmed), or `topic_merged` (A4 consolidated the
  topic). The reason must never be LLM-generated.
- **A2-03 (MUST):** the withdrawal is surfaced to the user the next time they open Insights —
  e.g., a "recently withdrawn" section — and states the numbers: "meetings → anxious was
  withdrawn: 3 occurrences, now 2 — below the minimum of 3."
- **A2-04 (MUST):** a withdrawn pattern is never re-surfaced as an active pattern while the
  withdrawal reason still holds.
- **A2-05 (MUST):** if the evidence returns (an edited entry re-mentions the topic with a
  confirmed feeling), the pattern is re-created and the withdrawal record for it is marked
  `superseded` — the user is not told "withdrawn" and "active" for the same pattern at once.
- **A2-06 (MUST):** withdrawal history is bounded (the most recent N, N a backend constant) so
  the database does not grow without limit.
- **A2-07 (SHOULD):** Insights shows a count of withdrawals since the user's last visit ("2
  patterns were withdrawn since you last looked") so a withdrawal is never missed silently.
- **A2-08 (NOT):** withdrawal records contain no diary text — only pattern identity, counts,
  reason, and timestamps.
- **A2-09 (NOT):** the engine must not hide a withdrawal because narration/suggestion is
  unfinished; withdrawal is computed, narration is decoration.

**Success criteria**

- **A2-SC1:** create 3 confirmed occurrences → pattern appears; edit one entry to drop the topic
  and recompute → Insights shows the withdrawal with "3 → 2" and reason `below_threshold`.
- **A2-SC2:** edit that entry back → recompute → pattern is active again and the withdrawal is
  marked superseded (never shown as both at once).
- **A2-SC3:** a user who opens Insights after the withdrawal cannot miss it — it is visible
  without navigating to a buried settings screen.

---

### I3 — Pattern recency: active vs. historical, windowed counts

**Business idea:** the audit found the count is lifetime while the narrative says "recent". This
item makes the count mean what it says: a windowed count (last 30 days), an active/historical
label, and a truthful narrative.

**Functional requirements**

- **I3-01 (MUST):** the backend defines a window length (30 days) as a constant and serves it to
  clients; clients must not hardcode it (C-01).
- **I3-02 (MUST):** every pattern carries two counts: `occurrence_count` (window) and
  `lifetime_count` (all history). The displayed count is the window count.
- **I3-03 (MUST):** a pattern is labelled **active** when it has at least
  `MIN_OCCURRENCE_THRESHOLD` occurrences inside the window, **historical** otherwise.
- **I3-04 (MUST):** the narrative text uses windowed wording that matches the number exactly —
  "in the last 30 days" — and never contains "recent" when referring to a lifetime count
  (absorbs audit fix A5).
- **I3-05 (MUST):** historical patterns remain visible (sorted below active, visually distinct)
  with their lifetime count and last-occurrence date; they are not deleted automatically.
- **I3-06 (MUST):** the evidence trail (A1) for a pattern shows only the entries inside the
  window, and A1-02's count equality holds against the window count.
- **I3-07 (SHOULD):** a historical pattern's card states how long ago its last occurrence was
  ("last seen 62 days ago").
- **I3-08 (NOT):** the user is never shown a pattern whose window count is below the threshold as
  if it were active.
- **I3-09 (NOT):** historical patterns must not silently vanish — withdrawal (A2) is the only
  removal path.

**Success criteria**

- **I3-SC1:** with 3 confirmed occurrences 90 days ago and 2 this week for the same pair, the
  pattern is **historical** with window count 2, lifetime 5, narrative reading "in the last 30
  days".
- **I3-SC2:** with 3 occurrences this week, the pattern is **active** and identical on both
  clients.
- **I3-SC3:** no narrative text in any fixture contains "recent" unless a 30-day window is
  actually applied.

---

## 2. Phase 2 — Make the evidence honest

### A4 — LLM topic normalization: canonical names and aliases

**Business idea:** the audit found LLM-proposed topics are one-shot and unmerged ("project
review" / "project meeting" / "review" never cross the threshold). This item makes the model
propose and the backend decide: proposals are mapped onto canonical topics and aliases before
storage, and previously fragmented topics are merged once.

**Functional requirements**

- **A4-01 (MUST):** every LLM-proposed topic is normalized deterministically before storage:
  lowercase, trimmed, punctuation stripped, whitespace collapsed (extending the existing
  `normalizeTopics`), then matched against the canonical topic list and the alias table.
- **A4-02 (MUST):** a proposal that matches a canonical topic or any of its aliases is stored as
  that canonical topic — never as a new row. Matching is whole-word/stemmed, never substring
  (the "steamed" ≠ "tea" rule from `topics.service.ts` applies).
- **A4-03 (MUST):** the LLM is never asked to decide equivalence; the mapping is deterministic
  backend code (C-03).
- **A4-04 (MUST):** the alias table is editable by the user (add/remove aliases for a topic),
  and edits take effect on the next recompute without re-running the model.
- **A4-05 (MUST):** a one-time migration merges existing fragmented topic rows: all
  `entry_topics` links and `pattern_entries` links are re-pointed at the canonical row, and
  orphaned rows are removed. No diary entry is deleted or altered by the merge.
- **A4-06 (MUST):** after a merge, occurrences are re-counted so an entry that mentioned a topic
  once is never counted twice for it.
- **A4-07 (MUST):** topics that were themselves evidence are re-surfaced correctly: patterns
  whose topic merged re-point to the canonical topic with a merged-count recompute.
- **A4-08 (SHOULD):** the merge is idempotent and safe to run repeatedly (no-op on second run).
- **A4-09 (NOT):** the merge never deletes an entry, an `entry_feelings` row, or a confirmed
  feeling.
- **A4-10 (NOT):** LLM topics that match nothing are still stored as new topics — normalization
  must not silently drop legitimate novel topics; the mapping is a preference, not a filter.

**Success criteria**

- **A4-SC1:** three entries mentioning "project review", "project meeting" and "review"
  respectively, after analysis and recompute, contribute to a single canonical topic row (or
  three rows merged by the migration) whose count is 3.
- **A4-SC2:** running the migration twice yields identical counts (idempotence).
- **A4-SC3:** a user adding the alias "gym session" → exercise causes the next recompute to
  re-point existing "gym session" links at exercise without model involvement.

---

### A3 — Base-rate / statistical lift

**Business idea:** every pattern states strength: how much more likely the feeling is with the
topic than without it. This closes the audit's biggest correctness gap — 3 "tired" entries prove
nothing if the user is tired most of the time.

**Functional requirements**

- **A3-01 (MUST):** for each qualifying (topic, feeling) pair, the backend computes: present
  count (entries with topic and feeling), present total (entries with topic), absent count
  (entries without topic but with feeling), absent total (entries without topic), all restricted
  to confirmed-source entries (C-04) inside the recency window (I3).
- **A3-02 (MUST):** lift is computed as `(present_count / present_total) / (absent_count /
  absent_total)`, guarding division by zero; when the absent side is undefined, lift is reported
  as `undefined` with a stated reason, never as a fabricated number.
- **A3-03 (MUST):** both rates, the base rate (feeling rate over all entries), and the lift are
  returned with the pattern and displayed.
- **A3-04 (MUST):** a pair whose lift is below the minimum (e.g., < 1.5×) is suppressed even if
  it meets the ≥3 occurrence rule; the minimum lift is a backend constant served to clients.
- **A3-05 (MUST):** when the absent side has too few entries to compare (e.g., fewer than the
  comparison minimum), the pattern is shown with the note "not enough entries without {topic} to
  compare" — it is not presented as strong evidence.
- **A3-06 (MUST):** the narrative includes the real numbers, deterministically — "anxious in 8
  of 12 entries mentioning meetings (67%) vs 3 of 28 without (11%)" — and the LLM is never asked
  to produce or paraphrase them (C-03; the existing `statesEvidence` guard keeps suggestions
  free of invented numbers).
- **A3-07 (SHOULD):** a pair with high lift (≥ 3.0×) and ≥ 5 window occurrences is visually
  marked as a strong pattern.
- **A3-08 (NOT):** lift is never presented as causation; the card and narrative use
  association language.
- **A3-09 (NOT):** the ≥3 occurrence rule is not removed — lift filters and ranks; it does not
  replace the minimum.

**Success criteria**

- **A3-SC1:** fixture: 12 entries with meetings (8 anxious), 28 without (3 anxious) → lift ≈ 6.2×,
  both rates and the base rate shown; the same fixture with all numbers generated deterministically
  by unit test.
- **A3-SC2:** fixture: topic appears in 5 tired entries while 80% of all entries are tired → lift
  < 1.5× → pattern suppressed despite meeting the occurrence rule.
- **A3-SC3:** fixture: every entry mentions the topic (absent side empty) → pattern shows the
  insufficient-comparison note, never a lift number.
- **A3-SC4:** both clients display identical lift, rates, and base rate for the same data.

---

### I1 — Inverse patterns: "what helps", not just "what hurts"

**Business idea:** the "without" half of the lift table becomes its own card: "on days without
exercise, low mood is 3× more likely." The product gains a positive, do-more-of-this surface for
the first time.

**Functional requirements**

- **I1-01 (MUST):** for each qualifying pair, the backend also evaluates the absent-side
  association: if the feeling rate without the topic exceeds the rate with it by the same
  minimum lift (A3-04), an inverse pattern is produced.
- **I1-02 (MUST):** inverse patterns obey every evidence rule of forward patterns: confirmed
  sources only, windowed counts, minimum comparison data, withdrawal, recency labelling.
- **I1-03 (MUST):** inverse patterns are a distinct card type with distinct phrasing
  ("associated with feeling less {feeling}") and are visually distinguishable from forward
  patterns on both clients.
- **I1-04 (MUST):** the inverse card states both rates and the lift, deterministically — "low
  mood in 4 of 10 entries without exercise (40%) vs 9 of 12 with (75%)".
- **I1-05 (MUST):** direction logic extends: a pattern is `keep` when the association is
  positive — forward pair with positive feeling, or inverse pair whose absence coincides with a
  negative feeling.
- **I1-06 (MUST):** inverse patterns are ranked and capped per Insights view (e.g., top N by
  lift) so they never flood the forward list.
- **I1-07 (NOT):** inverse phrasing must not claim protection or causation ("absence protects
  you") — association language only, same as forward patterns.
- **I1-08 (NOT):** an inverse pattern is never produced when the absent side lacks the
  comparison minimum (A3-05 applies identically).

**Success criteria**

- **I1-SC1:** fixture where low mood is rare on no-exercise days → inverse card appears with the
  correct numbers; the same fixture's forward side (exercise → low mood) is correctly absent.
- **I1-SC2:** an inverse pattern whose evidence is edited away is withdrawn with a visible notice
  (A2) exactly like a forward pattern.
- **I1-SC3:** inverse cards on web and Android show identical numbers and phrasing.

---

### I2 — Confounder warnings: collinear topic pairs

**Business idea:** when two topics always travel together, a pattern on one may really be about
the other. The app detects this in the user's own data and says so — the step past Bearable,
which only warns that confounders exist.

**Functional requirements**

- **I2-01 (MUST):** the backend computes, for each pair of topics that both appear in the same
  entry at least once, the co-occurrence rate: share of topic X's entries that also contain topic
  Y.
- **I2-02 (MUST):** when X and Y are collinear (co-occurrence rate ≥ a backend constant, e.g.,
  80%) and X has a surfaced pattern, the pattern carries a deterministic annotation naming Y and
  the rate: "X and Y appear together in 9 of 10 entries — the association with X could really be
  about Y."
- **I2-03 (MUST):** the annotation includes the four-cell split: entries with X∧Y, X∧¬Y, ¬X∧Y,
  ¬X∧¬Y (counts), restricted to confirmed sources and the recency window.
- **I2-04 (MUST):** when either split cell is empty (e.g., no entry with X without Y), the
  annotation states "cannot separate X from Y with the current data" instead of implying a
  conclusion.
- **I2-05 (MUST):** the computation is deterministic; no LLM participates (C-03).
- **I2-06 (SHOULD):** pairs that A4 merged as synonyms never produce a confounder annotation
  (they are the same topic by then).
- **I2-07 (NOT):** patterns are never hidden because of a confounder — only annotated. Withholding
  evidence would contradict the product's own explainability principle.
- **I2-08 (NOT):** the confounder note never names a third-party topic or implies causality
  between the two topics.

**Success criteria**

- **I2-SC1:** fixture where coffee and work co-occur in 9 of 10 work entries, with a work →
  anxiety pattern → the annotation appears with the split and the 90% rate.
- **I2-SC2:** same fixture with a single entry containing work but not coffee → annotation shows
  the non-empty split cell (X∧¬Y = 1) and states the separation is possible but thin.
- **I2-SC3:** annotation text is identical on both clients (it is backend-served).

---

## 3. Phase 3 — Make the engine daily

### I4 — Pattern echo at finalize

**Business idea:** when the user finishes an entry that matches an active pattern, the app shows
the historical association at the moment it is lived — "this entry mentions meetings; anxious in
8 of 12 such entries" — after writing, never during.

**Functional requirements**

- **I4-01 (MUST):** on entry finalize (guided or freeform), the backend computes the entry's
  topics and returns any active patterns (I3) matching them, as a read-only echo payload.
- **I4-02 (MUST):** the echo is shown only after the entry is saved, never during composition,
  so it cannot bias what the user writes.
- **I4-03 (MUST):** the echo is deterministic observation — the same numbers as the pattern card
  (window count, rates when lift exists) — and contains no suggestion, no prediction, and no
  statement about how the user feels today.
- **I4-04 (MUST):** the echo links back to the pattern card and its evidence trail (A1).
- **I4-05 (MUST):** echo eligibility uses the same confirmed-evidence and active-pattern rules;
  a historical or below-threshold pattern never echoes.
- **I4-06 (SHOULD):** at most one echo per pattern per calendar day, so repeated same-topic
  entries do not nag.
- **I4-07 (SHOULD):** the echo is dismissible, and dismissal does not affect the pattern itself.
- **I4-08 (NOT):** the echo is never inserted into the entry's stored text or answers.
- **I4-09 (NOT):** the echo never appears for an entry whose topics have no pattern — no
  invented "maybe this matters" content.

**Success criteria**

- **I4-SC1:** with an active coffee → anxious pattern (8 of 12 windowed), finalizing an entry
  mentioning coffee shows the echo with count 8 and the pattern link; the stored entry text is
  byte-identical to what the user wrote.
- **I4-SC2:** finalizing the same entry with the model's feeling still `suggested` shows no echo
  for the suggested feeling (C-04).
- **I4-SC3:** opening the composer and typing coffee shows no echo at any point before save.

---

### I6 — Feeling intensity (1–5, optional)

**Business idea:** a dial on the primary feeling at confirmation. User-set intensity is the
continuous signal `diff-3` (trajectory) needs; model confidence is never treated as intensity.

**Functional requirements**

- **I6-01 (MUST):** at the confirm/override step the user MAY set an intensity of 1–5 on the
  primary feeling; it is optional and never required (capture speed, Principle VI).
- **I6-02 (MUST):** intensity is stored per entry, only when the user sets it; the model's
  confidence value is never stored or displayed as intensity.
- **I6-03 (MUST):** intensity survives subsequent edits unless the user changes it; re-confirming
  the same feeling keeps the stored intensity.
- **I6-04 (MUST):** intensity is served to both clients and shown in entry detail and on the
  calendar day cell (how bad, not just which).
- **I6-05 (MUST):** trajectory (diff-3) uses intensity when present and falls back to discrete
  feeling valence when absent — never mixing the two scales in one number.
- **I6-06 (MUST):** intensity never affects pattern eligibility or lift; it is a display and
  trajectory signal only.
- **I6-07 (SHOULD):** the confirm UI offers intensity as one optional tap, defaulting to off, so
  the two-tap capture flow is not degraded for users who skip it.
- **I6-08 (NOT):** intensity is not a 1–100 scale and does not replace the feeling vocabulary
  (that is Daylio's model and it loses the word that makes patterns meaningful).

**Success criteria**

- **I6-SC1:** setting intensity 4 on "anxious" stores 4, returns it on read, and shows it on the
  calendar; an entry without intensity shows none and is unaffected.
- **I6-SC2:** re-editing the entry without touching intensity keeps 4; changing the feeling to
  "calm" without setting intensity stores no intensity for the new feeling.
- **I6-SC3:** identical intensity values on web and Android for the same entry.

---

## 4. Phase 4 — Widen the insight surface

### I5 — Day-of-week and time-of-day insights

**Business idea:** answer "when am I worst?" with data already collected — average valence by
weekday and by time of day, each with base rates and evidence rules.

**Functional requirements**

- **I5-01 (MUST):** the backend computes, over confirmed-source entries in the recency window:
  average feeling valence per weekday (Mon–Sun) and per time-of-day bucket (morning/afternoon/
  evening, derived from `created_at`).
- **I5-02 (MUST):** each bucket shows its count and base rate; a bucket with fewer than the
  minimum entries (e.g., < 3) is labelled "insufficient data", never shown as a number.
- **I5-03 (MUST):** valence averaging is deterministic and defined (documented mapping of the
  three valences to −1/0/+1 or equivalent); the mapping is a backend constant.
- **I5-04 (MUST):** insights are computed by the backend and served; clients render only
  (C-01), identical on both (C-02).
- **I5-05 (SHOULD):** the view highlights the best and worst weekday/time bucket.
- **I5-06 (NOT):** "when" insights never claim a cause; they are time patterns and are labelled
  as such, and may be cross-checked by the confounder tooling (I2) against topics.
- **I5-07 (NOT):** weekday/time insights never include unconfirmed-feeling entries.

**Success criteria**

- **I5-SC1:** a fixture with Mondays consistently negative and Saturdays positive shows Monday as
  worst with the supporting counts; identical on both clients.
- **I5-SC2:** a weekday with one entry shows "insufficient data", not an average.
- **I5-SC3:** the same fixture produces identical outputs across two recomputes (determinism).

---

### A6 — Time-slot guided questions

**Business idea:** seed morning/afternoon/evening variants of the guided questions so temporal
precedence (`diff-2`) becomes computable — the research's premise ("the flow already segments the
day") is currently false, and this item makes it true.

**Functional requirements**

- **A6-01 (MUST):** the seed adds new guiding questions carrying a time-slot category
  (`morning`, `afternoon`, `evening`) alongside the existing categories; each new question has a
  unique key, prompt text, and empty trigger-keyword list unless a trigger is genuinely intended.
- **A6-02 (MUST):** existing question keys keep their exact prompts and remain served unchanged;
  entries already stored with `question_text_snapshot` from old keys are unaffected (no migration
  of stored answers).
- **A6-03 (MUST):** the new slot questions are non-mandatory — the mandatory general prompt
  (FR-004/FR-005) is unchanged, so existing users' flows are not broken.
- **A6-04 (MUST):** guided composition follows the existing rule — `raw_text` composed as
  `"{prompt} {answer}"` per answer joined by a space; slot questions are no exception.
- **A6-05 (MUST):** the backend serves the slot category with each question so the temporal
  engine (diff-2) can order entries by slot without guessing.
- **A6-06 (MUST):** if a client cannot render slot questions (older client), it ignores them —
  the API is additive.
- **A6-07 (SHOULD):** clients surface slot questions at the matching time of day (presentation
  choice; the backend only serves them).
- **A6-08 (NOT):** the day-segmentation claim is not made in product copy or docs until slot
  questions exist in the seed.
- **A6-09 (NOT):** slot questions do not change how existing freeform entries are composed.

**Success criteria**

- **A6-SC1:** `GET /guiding-questions` returns the previous questions unchanged plus new ones
  with `category` ∈ {morning, afternoon, evening}.
- **A6-SC2:** an existing diary (seeded before this item) starts with no new questions inserted
  into its stored answers; `seed()` remains a no-op on non-empty tables.
- **A6-SC3:** a guided entry answered via a slot question stores the same derived-value shape as
  any other guided entry.

---

## 5. Phase 5 — Portability

### I7 — Plain-text export (Markdown/JSON)

**Business idea:** the diary must come out as readable text. The only export today is a raw
SQLite copy; this item makes "your words, your rules" real.

**Functional requirements**

- **I7-01 (MUST):** the backend provides an export that renders every entry as human-readable
  Markdown: date, mode, each question and its answer (with the stored question snapshot), the
  raw text, the confirmed feelings, and the topics.
- **I7-02 (MUST):** the export is deterministic — identical data always produces byte-identical
  output, with stable ordering (by date, then creation time, then id).
- **I7-03 (MUST):** the export states each entry's feeling source (`confirmed`/`overridden`/
  `suggested`/`unset`) so provenance survives the export.
- **I7-04 (MUST):** no diary text is omitted: every entry's raw text is present, including
  guided entries' composed text.
- **I7-05 (MUST):** the export is available through the API (download) and/or as an extension of
  the existing backup command; it requires no cloud service.
- **I7-06 (SHOULD):** export accepts an optional date range for incremental use.
- **I7-07 (SHOULD):** export is also available as JSON with the same guarantees, to feed import
  (I8) and future tooling.
- **I7-08 (NOT):** the export must not include inference internals (confidence values, job rows,
  model outputs) unless explicitly labelled as such in a separate section.
- **I7-09 (NOT):** export never alters diary data — it is strictly read-only.

**Success criteria**

- **I7-SC1:** exporting a seeded diary and parsing the Markdown yields per-entry data equal to
  the API's entry list (counts match; texts match).
- **I7-SC2:** exporting the same diary twice yields byte-identical files.
- **I7-SC3:** every entry's raw text is present in the export, verified by unit test over a
  fixture with guided and freeform entries.

---

### I8 — Import from Daylio / Bearable

**Business idea:** the audience the research identified — people tracking mood in cloud apps who
want to switch — arrives with their history intact and a warm pattern engine.

**Functional requirements**

- **I8-01 (MUST):** import accepts CSV files in the documented Daylio and Bearable export
  formats and rejects files it cannot parse with a clear error listing the first offending row.
- **I8-02 (MUST):** imported entries are stored with a distinct feeling source, `imported`, which
  is **not** in `CONFIRMED_FEELING_SOURCES` — imported feelings are never pattern evidence until
  the user reviews and confirms them.
- **I8-03 (MUST):** the UI provides a review step: the user sees every mapped entry (source mood,
  mapped feeling, date, note text) and can confirm in bulk or per entry; confirming flips the
  source to `confirmed`.
- **I8-04 (MUST):** the mood/tag mapping tables (Daylio mood ↔ MPD feeling; activity tag ↔ MPD
  topic) are fixed, documented, and applied deterministically; unmappable rows are reported in
  the review summary, never silently dropped.
- **I8-05 (MUST):** import is idempotent — importing the same file twice creates no duplicate
  entries (verified by a content/date fingerprint per row).
- **I8-06 (MUST):** imported entries carry provenance (source app, import date) stored in the
  database, visible in the entry detail; the raw note text is never altered by mapping.
- **I8-07 (MUST):** import never modifies, deletes, or reorders existing entries.
- **I8-08 (MUST):** the import transaction is atomic — a failure mid-import leaves the diary
  unchanged.
- **I8-09 (SHOULD):** an import batch can be discarded entirely before confirmation (the review
  step is the safety net; nothing is written until the user commits).
- **I8-10 (NOT):** import never connects to Daylio, Bearable, or any third-party service — file
  input only.
- **I8-11 (NOT):** imported topics do not trigger A4 merges or confounder annotations until
  their entries are confirmed (they are not evidence before that).

**Success criteria**

- **I8-SC1:** importing a real Daylio export twice yields the same entry count (no duplicates)
  and every row in the source file is accounted for (mapped or reported unmapped).
- **I8-SC2:** before confirmation, patterns and insights are byte-identical to the pre-import
  state (imported data is inert); after confirmation, counts rise exactly by the confirmed rows.
- **I8-SC3:** an import that fails on row 50 leaves the diary exactly as it was (atomicity).

---

## 6. Phase acceptance and cross-phase checks

- **P1 (MUST):** no Phase 2 item ships before A1, A2, and I3 are live on both clients — the
  evidence trail and withdrawal notices are what make lift's legitimate downgrades (A3) legible
  instead of regressions.
- **P2 (MUST):** no Phase 4 item ships before I5's "when" insights exist; A6 is the prerequisite
  for `diff-2` temporal precedence, not a standalone feature.
- **P3 (MUST):** every item above ships with at least one automated test per MUST requirement —
  unit tests for backend math (lift, collinearity, windows, merges), contract tests for payload
  shape and count equality (A1-02), and cross-client parity checks where the existing harness
  allows (SC-005 pattern).
- **P4 (MUST):** after each phase, both clients render the same numbers for the same fixture
  (C-02); a golden fixture per phase is committed to the test suite.
- **P5 (NOT):** no phase is considered done while any of its MUST requirements lacks a passing
  automated test.

---

## 7. Explicit non-goals (verified against the code, decided not to build)

- **Reminders on web** — Android already ships four daily alarms (FR-013); a web nudge is a
  possible thin add-on, not part of this program.
- **Multi-user, sharing, social, wearables, chat-AI, gamification** — rejected in
  `differentiator-opportunities.md` and not reopened here.
- **Photos/media in entries** — adds capture burden without feeding the pattern engine.
- **Removing or relaxing the ≥3 threshold** — A3 filters and ranks on top of it; the minimum
  stays.
- **Cloud analysis of any kind** — every item above runs on the existing local stack (C-07).
