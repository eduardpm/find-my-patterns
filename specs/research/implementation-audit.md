# Implementation Audit — does the app hold up against the research?

**Date:** 2026-08-26
**Scope:** Read the actual backend, web, and Android code against every factual claim in
`competitive-landscape.md` and `differentiator-opportunities.md`. Every verdict below cites the
file and line that proves it. No build, no run — this is a static audit of what the code ships.

**Companion to:** `competitive-landscape.md`, `differentiator-opportunities.md`, and the eight
per-differentiator plan docs in this directory.

---

## Verdict summary

**Structurally: yes, it holds up.** Every architectural claim the research makes about this app is
real, shipped code — not a slide. The confirmed-feeling gate, the deterministic threshold, the
lazy withdrawal, the local-only inference, the word-faithful transcription, the two thin clients
over one backend: all verified line-by-line.

**Product-wise: partially.** The research's headline position — "patterns you can audit" — is
underdelivered in exactly the two places the research itself flagged, and both are confirmed in
code: the evidence trail exists in the database but no client shows it, and the base-rate gap is
real. Additionally, two overclaims in the research documents themselves were found (free-text
topics as "built with Ollama", and "the guided flow already segments the day").

| Research claim about the app | Verified in code? | Verdict |
|---|---|---|
| Confirmed feelings are the only evidence (`CONFIRMED_FEELING_SOURCES`) | ✅ Fully | **Holds — strongest differentiator, more precise than the research describes** |
| ≥3 occurrence threshold, deterministic, no LLM in counting | ✅ Fully | Holds — but see base-rate gap |
| Patterns withdrawn when evidence changes | ✅ Mostly | Holds lazily (next Insights view) and **silently** — no UI signal |
| Evidence trail exists (supporting entries) | ⚠️ Data exists, **no client shows it** | Underdelivered — the audit claim is invisible to users |
| Fully local inference on a self-hosted backend | ✅ Fully | Holds |
| Word-faithful transcription, structurally enforced | ✅ Fully | Holds — stronger than the research credits |
| Free-text topic extraction ("write naturally, we find the topics") | ⚠️ Hybrid — curated keywords are primary, LLM topics are weak | **Biggest gap vs. the pitch**; research overstates it |
| Guided questions engineered for pattern detection (FR-006) | ✅ Intent real, set is thin | Holds in intent; research's diff-2 overclaims time-slot segmentation |
| Base-rate awareness (lift) | ❌ Absent | **Research §10's biggest correctness gap — confirmed in code** |

---

## 1. Confirmed feelings — fully holds (and is better than the research says)

**Claim:** "Only a feeling the user acted on is evidence — a mere suggestion is not a fact."

**Verified:** `backend/src/insights/patterns.service.ts` — `CONFIRMED_FEELING_SOURCES =
['confirmed', 'overridden']`, and the pattern engine's entry query filters on exactly that set.
The `feeling_source` lifecycle is enforced in `backend/src/entries/entries.service.ts`: entries
are created `'unset'`, the worker sets `'suggested'` (only while still `'unset'` — a confirmed
entry is never overwritten), and `updateEntry` computes `'confirmed'` vs `'overridden'` by
comparing the user's chosen set against the previously suggested set.

**Stronger than the research credits:** the confirm/override distinction is set-equality based —
re-ordering the same feelings is *not* an override. That is a real semantic the research
summarized as "suggest → confirm or override" without capturing. The suggestion is also only
offered when it *differs* from what the entry carries (`analysisFor`), so the UI never shows
"we suggest: happy" under a feeling that is already happy.

**Verdict:** This is the cleanest unclaimed idea in the whole set, and the implementation is
precise. The research's #1 differentiator is real code.

---

## 2. Deterministic threshold and withdrawal — holds, with two caveats

**Verified:** `MIN_OCCURRENCE_THRESHOLD = 3` and pure `qualifyingPairs` (count, filter, no DB, no
LLM) in `patterns.service.ts`. The "no model near the observation" rule is real:
`observationFor()` is deterministic string building, and the LLM is only ever asked to phrase the
*suggestion* (`narrateNextPattern` in `backend/src/inference/worker.ts`).

**Caveat 1 — withdrawal is lazy, not event-driven.** `recomputePatterns()` runs only on `GET
/insights`. Edit/delete correct the underlying data immediately (topic links deleted, jobs
re-enqueued in `entries.service.ts`), but a pattern disappears on the *next* Insights view, not
when the evidence changes. For a single-user app that is acceptable — the research presents it as
"withdrawn when supporting entries are edited or deleted," which is true on read, not on write.

**Caveat 2 — withdrawal is silent.** Nothing records or shows "this pattern was withdrawn and
why." The research's own strengthening plan (diff-existing-1) asks for exactly this, and it is
currently absent.

**Caveat 3 (found in audit, not in research):** the narrative says *"You felt X in N **recent**
entries mentioning Y"* — but the count is lifetime, over all history, with no recency window.
"Recent" is not what the number is. Small, but it is precisely the kind of wording an
auditability claim gets caught on.

---

## 3. Evidence trail — the data exists, the product doesn't show it

**Verified:** `pattern_entries` is written on every recompute (`patterns.service.ts`) and pruned on
delete (`entries.service.ts`). `PatternOut` carries `occurrence_count`. Both clients render a flat
`PatternCard` with topic, direction badge, narrative, suggestion, and the count
(`web/src/components/PatternCard.tsx`, `android/.../InsightsApi.kt`) — and **no link to the
supporting entries**.

`web/src/screens/InsightsScreen.tsx` renders a flat list; there is no drill-down route. The
research's statement — "the count exists in `PatternOut.occurrence_count` but the evidence trail
is not a product feature" — is verified word-for-word. Making the trail visible is the cheapest
high-value fix in the entire audit: the data is already there.

---

## 4. Local inference on a user-owned backend — fully holds

**Verified:** the API process never talks to Ollama — it only enqueues jobs into SQLite
(`inference/enqueueEntry`, `entries.service.ts` calls `this.inference.enqueueEntry`), and a
separate worker (`backend/src/inference/worker.ts`) processes them. Audio: ffmpeg → whisper.cpp →
local Qwen punctuation restoration, per the README. The research's "empty cell" (self-hosted
server + local AI + multiple thin clients) is occupied by real code.

**Word-faithfulness is structurally enforced, not prompt-discipline.** `projectTranscriptFormatting`
aligns the model's output to Whisper's token sequence with an LCS and reconstructs from source
words; the fallback `acceptFormattedTranscript` requires an identical word sequence. The research
got this right — and it is worth noting this guarantee is *stronger* than Verity's stated intent.

**One asymmetry found (minor):** the recompute re-extracts *keyword* topic links on every pass
but never re-runs LLM analysis, so LLM topic links persist until the user edits the text. The
evidence trail can contain LLM topics the current text no longer supports. Auditable in theory,
stale in practice for that subset.

---

## 5. Free-text topics — the biggest gap between the pitch and the code

This is where reality diverges most from the research's optimistic framing.

**What is actually built** (`backend/src/topics/topics.service.ts` + `worker.ts`):

1. **Deterministic keyword path (primary):** a *curated* list of ~50 canonical topics
   (`CURATED_TOPIC_KEYWORDS`), whole-word matched, `extracted_by = 'keyword'`. This is
   pre-defined tracking wearing a free-text costume: the app finds *only* topics that are already
   in its vocabulary.
2. **LLM path (secondary):** the Ollama model proposes up to 10 free-text topics
   (`extracted_by = 'llm'`), normalized (lowercase, punctuation stripped, de-duplicated) and told
   to prefer canonical names — a soft constraint with no post-hoc enforcement.

**The research overstates this as "Built (Ollama/qwen3)"** in its summary table. The honest
description is: deterministic curated keywords with a free-text LLM supplement that is
one-shot and unmerged. `topics.aliases` exists but LLM topics are created with `aliases = []`, so
"project review", "project meeting" and "review" become three separate topics that can never
accumulate enough occurrences to cross the ≥3 threshold. That is the fragmentation failure the
research's own §10 mitigation describes ("the model proposes and the backend decides") — and the
backend currently does *not* decide. The mitigation is prescribed but not implemented.

**Why it matters:** the entire "patterns you can audit" position rests on topic quality. A
fragmented topic space produces no patterns; a keyword-capped space silently limits what the user
can ever learn about. This is the highest-leverage correctness work after the base-rate gap.

---

## 6. Guided questions — intent is real, substance is thin, and diff-2 overclaims

**Verified:** `guiding_questions` table (key, category, prompt_text, trigger_keywords,
is_mandatory) seeded in `backend/src/db/seed.ts`; FR-006 in `specs/002` makes pattern-detection
input the primary design criterion; both clients render the flow.

**The engineering is real but small:** `small_influences` explicitly enumerates sleep, food,
drink, caffeine, alcohol, medication, movement, work, social contact, screen time, weather —
which maps almost 1:1 onto `CURATED_TOPIC_KEYWORDS` categories. The questions are worded to elicit
the vocabulary the deterministic extractor can count. That is genuine FR-006 design, not a
reflection prompt.

**But the set is four static questions** — three mandatory, one keyword-triggered — identical for
every user, forever. And **diff-2's claim that "the guided question flow already segments the day
(morning/afternoon/evening)" is not true of the current seed**: the question keys are
`general_feeling`, `mind_body`, `small_influences`, `response_outcome` — no time-slot dimension.
Temporal precedence would need either new time-slot questions or to lean on `created_at`
timestamps (which do exist). The research's plan doc built its core feasibility argument on a
feature that isn't there yet.

---

## 7. The base-rate gap — confirmed, and it is the research's most important finding

**Verified:** `qualifyingPairs` counts only co-occurrences of `(topicId, feelingKey)`. There is no
query comparing the feeling rate in entries *with* the topic against entries *without* it. A topic
appearing in 3 "tired" entries surfaces as a pattern even when the user is tired in 80% of all
entries. The research §10 statement — "a topic appearing in three 'tired' entries proves nothing
if the user is tired in most entries... this is the single biggest correctness gap" — is accurate
against the code, and it is directly at odds with the "patterns you can audit" position until
fixed. The fix (a lift computation) is one SQL query and is already scoped in
`diff-1-base-rate-patterns.md`.

---

## 8. Where the app is stronger than the research credits

1. **The suggestion layer already enforces "no invented evidence."** `acceptSuggestion` /
   `statesEvidence` in `worker.ts` reject any model suggestion that cites counts, entries,
   percentages, or the word "journal/diary" — the model is structurally prevented from quoting
   evidence it was never given. The research never mentions this, and it is a genuine
   auditability feature already shipped.
2. **Two-client parity is real.** Both clients render exactly the fields the backend returns and
   compute nothing (per `PatternCard`'s own header comment and `InsightsApi.kt`). The "one
   backend, thin clients" constitution holds.
3. **The confirm/override set-equality semantics** (reorder ≠ override) are more precise than the
   research's one-line description.
4. **`last_updated_at` discipline** — stamped only when a pattern actually changes, so unchanged
   data produces identical payloads across clients. Detail, but it is the kind of thing
   "deterministic" is supposed to mean.

---

## 9. Bottom line

The app holds up against the research **as an architecture**, and it is weaker than the research
**as a product** in the two places the research itself predicted — plus one overclaim the research
made about its own subject (free-text topics, time-slot questions). Ranked by urgency:

1. **Surface the evidence trail** — show the supporting entries behind each pattern, tappable.
   Data already exists (`pattern_entries`); zero backend work. This is the difference between
   claiming auditability and being auditable.
2. **Show withdrawals** — when a pattern is dropped on recompute, say so, and why.
3. **Base-rate / lift** — one query; turns the ≥3 rule into meaningful evidence.
4. **Normalize LLM topics** — map proposed topics onto canonical names and aliases; otherwise
   fragmentation silently caps pattern detection.
5. **Fix the "recent" wording** in `observationFor` — the count is lifetime, not recent.
6. **Either add time-slot questions or stop claiming the day is segmented** — diff-2's premise
   needs one or the other.
