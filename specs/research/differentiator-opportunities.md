# Differentiator Opportunities — Mood Pattern Diary

**Date:** 2026-08-24
**Companion to:** `competitive-landscape.md` (market landscape, competitor analysis, positioning)
**Focus:** What additional value Mood Pattern Diary could add beyond current differentiators, ranked by feasibility × impact.

---

## 1. What Mood Pattern Diary uniquely brings today

The existing competitive analysis (`competitive-landscape.md`) identified the unoccupied combination:
**free-text topic extraction → paired with a *user-confirmed* feeling → counted deterministically against a threshold → withdrawn when evidence changes → computed entirely on hardware the user owns.**

This breaks down into five distinct differentiators, all already shipped or partially shipped:

| Differentiator | Status | Occupied elsewhere? |
|---|---|---|
| **Patterns you can audit** — counted evidence with visible supporting entries, withdrawal on edit/delete, no black-box AI prose | Built; evidence trail not yet surfaced in UI | No — every other AI journal produces narrative prose you can't verify |
| **Confirmed feelings** — AI suggests, human confirms or overrides; only confirmed feelings count as evidence | Built (`CONFIRMED_FEELING_SOURCES`) | No — every other app either infers the feeling (Mindsera, Rosebud) or asks you to pick one (Daylio, Bearable), never *suggests then confirms* |
| **Fully local inference on a user-owned backend** — Ollama + whisper.cpp, no cloud AI vendor, diary text never leaves the machine | Built | Partly — Memex supports local Ollama but is a phone app, not a server; Journiv is self-hosted but has zero AI; the combination (self-hosted server + local AI + multiple thin clients) is unoccupied |
| **Free-text topic extraction without pre-defined trackers** — user writes naturally; the system finds the topics | Built (Ollama/qwen3) | Partly — Mindsera and Rosebud extract topics from text but in the cloud and don't pair them with counted feelings |
| **Guided questions engineered for pattern detection** — the question set is designed to surface extractable topics, not just for reflection | Built (FR-006); the framing is unique | No — every guided-prompt product (Stoic, Rosebud, Mindsera, Day One) frames prompts as *reflection aids*, never as input to a correlation engine |

The user's thesis — "simplicity and good pattern matching and detection" — maps directly to the first two rows. The rest of this document explores **what else could be added** to strengthen that thesis and open new ground.

**Deep-dive plans for strengthening each existing differentiator:**
- [diff-existing-1-auditable-patterns.md](diff-existing-1-auditable-patterns.md) — make the audit trail the product
- [diff-existing-2-confirmed-feelings.md](diff-existing-2-confirmed-feelings.md) — AI proposes, human decides
- [diff-existing-3-local-inference.md](diff-existing-3-local-inference.md) — your diary, your machine, your rules
- [diff-existing-4-free-text-topics.md](diff-existing-4-free-text-topics.md) — write naturally, we find the topics
- [diff-existing-5-guided-questions.md](diff-existing-5-guided-questions.md) — questions engineered for the pattern engine

**Deep-dive plans for the three new differentiators:**
- [diff-1-base-rate-patterns.md](diff-1-base-rate-patterns.md) — statistical lift instead of raw co-occurrence
- [diff-2-temporal-precedence.md](diff-2-temporal-precedence.md) — does the topic precede the feeling?
- [diff-3-emotional-trajectory.md](diff-3-emotional-trajectory.md) — is it getting better or worse?

---

## 2. The opportunity landscape — what's unsolved

After surveying 20+ competitors, four gaps stand out that no product addresses well:

1. **No product explains *why* a pattern exists.** They say "coffee and anxiety correlate," not "coffee consistently precedes anxiety by 2-4 hours."
2. **No product shows emotional *trajectory*.** They show mood levels over time, not whether a specific topic → feeling relationship is improving or worsening.
3. **No product does base-rate-aware correlation.** Bearable's own docs acknowledge it, but they don't display base rates. Every simple co-occurrence pattern that ignores how often the feeling occurs *without* the topic is statistically weak.
4. **No product supports n-of-1 experimentation.** They observe passively. None helps you *test* whether a pattern is causal.

Mood Pattern Diary is positioned to solve all four — uniquely — because its deterministic pattern engine can compute things cloud LLMs cannot and closed-source trackers will not.

---

## 3. New differentiator ideas, ranked

### Tier 1 — Build this first (high impact, moderate effort, directly strengthens the core thesis)

#### A. Base-rate-aware patterns (statistical lift instead of raw co-occurrence)

**The problem:** If a user is "tired" in 80% of all entries, then *any* topic appearing in 3 "tired" entries means nothing. The current ≥3 co-occurrence rule cannot distinguish a signal from high background rate.

**The idea:** Compute and display **lift** — how much more likely feeling Y is when topic X is present versus absent. This is what Bearable *wants* to do but can't without free-text mining, and what no free-text journal does at all.

```
"meetings" → "anxious"
  Present: 8 of 12 entries mention meetings → 67% anxious
  Absent:  3 of 28 entries without meetings → 11% anxious
  Lift:    6.1×  (meetings make anxious 6× more likely)
  Base rate: 26% of all entries are anxious
```

This is strictly stronger evidence than raw co-occurrences. It also lets the app raise the bar naturally: a pattern with lift <2.0× could be suppressed as noise, while lift >3.0× with ≥5 occurrences could be highlighted as strong.

**What it needs:** The pattern engine already has the data. Add a single SQL query: SELECT feeling, topic, COUNT when both present, COUNT when topic present but feeling absent, COUNT when feeling present but topic absent, COUNT when neither. Display lift in the Insights UI alongside the occurrence count.

**Why it matters competitively:** Nobody does this in a free-text product. Bearable does it for pre-defined factors but is the only one, and its UI buries the numbers. If MPD is the only journal that shows *statistically meaningful* patterns rather than LLM-generated vibes, it wins the "good pattern matching" claim outright.

---

#### B. Temporal precedence — does the topic precede the feeling?

**The problem:** "Meetings and anxiety co-occur" is a weaker claim than "meetings consistently *precede* anxiety by 1-3 hours." The former is correlation; the latter suggests causation. No product found does this.

**The idea:** Each entry has a timestamp and a question it answers. If entry A at 9:00 (guided question about morning) mentions "project review" and the feeling is "neutral", and entry B at 15:00 (afternoon check-in) is "anxious" and also mentions "project review", the engine can note the temporal order. Over months, if topic X consistently appears in earlier entries where the feeling is neutral, and the same topic later appears in entries where the feeling is negative, that's causal evidence.

**Implementation sketch:**
- For each topic→feeling pair, track which questions (morning/afternoon/evening) the topic appears in and which the feeling appears in.
- If the topic consistently appears in *earlier* entries than the feeling, flag it as "Topic precedes Feeling: N of M occurrences."
- If they co-appear in the same entry, flag it as "concurrent" instead.
- Display: "When meetings are mentioned in morning entries, anxiety appears in afternoon entries 5 of 7 times."

**What it needs:** The guided question metadata already exists (each entry answers a known question key at a known time). The pattern engine needs a time-gap column. The Insight UI needs a "timing" section per pattern.

**Why it matters:** This is a genuine hard-problem advance over every competitor. Bearable does "previous day/same day/next day" for pre-defined factors, but nobody does intra-day temporal precedence from free text. It also gives a natural answer to "what should I do about it?" — if meetings *precede* anxiety, the intervention is clear.

---

#### C. Emotional trajectory per topic — is it getting better or worse?

**The problem:** A pattern that says "topic X + anxiety 5 times" is static. The user wants to know: is it still true? Is it getting better?

**The idea:** For each surfaced pattern, compute a trend line. "When 'commute' appears, you felt angry the first 3 times, then frustrated the next 2, then neutral the last 2. The trend is improving." This is a simple recency-weighted feeling score.

**Implementation sketch:**
- For each topic→feeling pair, list the entries chronologically and score feeling valence.
- Apply a simple slope (linear regression over the feeling scores, or just compare first-half average vs. second-half average).
- Display a trend arrow (↑ improving, ↓ worsening, → stable) next to each pattern.

**What it needs:** Feelings already have a defined order (e.g., from negative to positive). The pattern engine computes the pair anyway. A trend column is a scalar addition.

**Why it matters:** Rosebud and Mindsera use LLMs to produce prose about "how things are going." Nobody shows a deterministic trend of the data itself. This makes MPD's deterministic engine look smarter than the LLM journals, not less capable.

---

### Tier 2 — Build next (high impact, higher effort, broadens the product's value)

#### D. N-of-1 experiment design

**The problem:** The user sees "meetings → anxious," but is it causal? The app could help them find out.

**The idea:** When a strong pattern is detected (lift >3×, ≥5 occurrences, temporal precedence), offer: "Would you like to test this? For the next week, try one day *without* meetings and log how you feel." The app creates a lightweight experiment: a control period (normal days), a treatment suggestion (avoid the trigger), and a results view comparing the two.

This reframes the app from passive observer to active coach. It also deepens engagement — the user comes back not just to log but to test hypotheses about themselves.

**Implementation sketch:**
- "Start an experiment" button on any pattern card.
- Experiment has a name, a hypothesis, start/end dates, and a counter-hypothesis (what happens when the trigger is avoided).
- During the experiment period, the daily entry UI shows a subtle "Experiment active: X" banner.
- Results view: compare feeling distribution during experiment period vs. baseline.

**Why it matters:** Exist.io does correlations but explicitly says "correlations can't determine causation." Nobody offers a workflow to *test* causality. This is a genuinely novel product capability and a strong differentiator for the "patterns you can audit" brand.

---

#### E. "This day in emotional history" — temporal comparison

**The problem:** Journal apps have "on this day" (show the entry from exactly one year ago). Nobody does emotional comparison across time.

**The idea:** "One year ago today, you wrote about 'project deadline' and felt anxious. Today you wrote about 'project deadline' and felt in control. Your relationship with deadlines has changed."

Implementation:
- For each topic in today's entry, find the most recent past day with the same topic (at least 6 months ago).
- Compare the feelings and display the delta.
- Surface the most dramatic positive shifts as a weekly highlight.

**Why it matters:** This is emotionally resonant in a way that charts are not. It tells a story about growth. Day One has "on this day" for entries; Dabble Me has "blasts from the past." Nobody uses it to show emotional *change.*

---

#### F. Anomaly detection — "this is different"

**The problem:** Patterns explain the *usual.* The unusual is more interesting.

**The idea:** When a topic that usually triggers one feeling suddenly triggers a different one, flag it. "You usually feel calm when writing about 'morning routine,' but today you felt anxious. Something was different."

Implementation: for each topic, maintain a most-common-feeling baseline. When today's feeling deviates from the baseline, surface a gentle prompt: "What was different about today's [topic]?"

**Why it matters:** This turns pattern detection on its head — instead of finding what's consistent, it finds what broke the pattern. It also generates the most useful journaling prompts because they're grounded in real-life deviations, not generic reflection text.

---

### Tier 3 — Build later (lower impact or higher complexity, but strategically interesting)

#### G. Emotional vocabulary expansion

**The problem:** Many users use 3-5 feeling words ("good", "bad", "tired", "anxious", "happy"). A narrow vocabulary limits pattern resolution — "bad" could mean sad, angry, frustrated, or disappointed, and the pattern engine can't distinguish them.

**The idea:** When the user confirms a feeling, offer richer alternatives. "You selected 'bad.' Would 'frustrated,' 'disappointed,' or 'overwhelmed' be more precise?" Over time, the user's vocabulary expands, and the pattern engine's resolution improves.

**Implementation sketch:** A feeling-to-feeling expansion map (curated, not LLM-generated). Display synonyms inline during the confirmation step. Track vocabulary breadth as a metric and celebrate when it grows.

**Why it matters:** The app gets better the more the user uses it, because richer feeling labels produce richer patterns. It also quietly teaches emotional literacy.

---

#### H. Cross-question pattern synthesis

**The problem:** Today's entry answers "What happened this morning?" and mentions "meetings." Yesterday's entry answered "What's weighing on you?" and also mentions "meetings." The guided question keys differ, but the topic is the same.

**The idea:** Patterns should span question boundaries. The Insights view should note: "Topic 'meetings' appears across your morning check-ins, your evening reflections, and your free-form entries — regardless of the question asked."

**Implementation sketch:** Already partially built — topic extraction runs per entry, and the pattern engine aggregates across entries. The missing piece is showing the question-key distribution per pattern so the user can see the scope.

---

#### I. Pattern lifecycle — birth, peak, and fade

**The problem:** Patterns are presented as static facts. In reality, a topic→feeling relationship has a lifecycle: it first appears, strengthens, plateaus, and sometimes disappears.

**The idea:** When the user opens a pattern detail, show a miniature timeline: "This pattern first appeared in March (3 occurrences), peaked in May (7 occurrences), and has faded since — only 1 occurrence in the last 30 days." This tells the user whether the pattern is active, resolving, or resolved.

**Implementation:** Rolling 30-day and 90-day occurrence counts per pattern, displayed as a sparkline or three-segment summary.

---

#### J. Therapy-export report

**The problem:** Many diary users are also in therapy. Therapists love data-driven session material but won't install an app to get it.

**The idea:** A one-tap "session summary" export that produces a one-page PDF with:
- Feelings calendar (last 30 days)
- Active patterns (topics + feelings + lift + trend)
- Topics mentioned this month (word cloud or frequency list)
- "Since last session" comparison if the user sets session dates

Everything designed to be handed to a therapist or shared in a session.

**Why it matters:** It's a channel to a motivated audience (people in therapy searching for "how to track my progress" or "what to bring to therapy"). No competitor product found offers a therapy-oriented export. Mindsera has frameworks; Rosebud has insights prose; nobody has a structured report.

---

### What NOT to add — ideas that would dilute the thesis

- **Chat-with-your-journal AI companion.** Mindsera, Rosebud, Day One Gold, and Memex all offer this. A 4B local model cannot compete with frontier models on conversation quality. This is a trap that would make the app look like a worse version of something established.
- **Social sharing of moods or entries.** Apple's Journal already does this, and Daylio/Reflectly have community features. It directly contradicts the privacy position.
- **Integration with wearables or 100+ biomarkers.** Welltory and Exist.io own this space. It adds complexity without strengthening the core pattern-matching thesis.
- **Habit tracking in the fitness-productivity sense.** Stoic and HabitBox already do this well. It blurs the app's identity as a diary that finds patterns.
- **Gamification.** Streaks and badges are table stakes (Daylio has them; Reflectly has them). They don't differentiate.

---

## 4. The synthesis — the strongest possible positioning

Mood Pattern Diary's strongest possible future positioning is:

> **The only diary that proves what it claims.**

Every other product — from Daylio's "influence on mood" to Rosebud's weekly insights to Mindsera's pattern analysis — produces claims the user cannot verify. The claims are algorithmic (closed-source trackers), statistical (correlation without base rates), or narrative (LLM prose). Nobody shows:

- The exact entries that produced the claim (evidence trail)
- The statistical basis for the claim (lift, not just count)
- The temporal relationship (precedes vs. co-occurs)
- Whether the claim is still true (trend)
- What happened when the claim was tested (experiment)

This is not a feature list. It is a single coherent product thesis: **accountable pattern detection.** The privacy story (fully local, self-hosted) supports it — privacy is the *precondition* for accountability, because if the data is in the cloud you can't audit the computation anyway. The simplicity story (no accounts, no registration, guided questions) supports it — simplicity is what makes it possible for a single user to maintain their own diary server. The confirmed-feeling step supports it — it is the gate that separates *what the AI guessed* from *what the user confirmed as evidence.*

Every idea in Tier 1 above strengthens this thesis. Every Tier 2 idea extends it into new territory without contradicting it. Every Tier 3 idea is a nice-to-have that reinforces it. And every "do not add" is rejected because it pulls away from it.

---

## 5. Recommended build order

| Order | Feature | Effort | Impact | Why this order |
|---|---|---|---|---|
| 1. | Base-rate-aware patterns (lift) | Low — one SQL query, one UI display | Very high — turns weak co-occurrence into meaningful evidence | The single biggest correctness gap identified in the competitive review. Fix it before building anything new. |
| 2. | Evidence trail in UI | Low — show supporting entries per pattern, tappable | High — makes the "auditable" claim visible to users | Already in `PatternOut.occurrence_count`; just needs a UI to show the entries behind it. |
| 3. | Temporal precedence | Medium — time-gap calculations, UI per pattern | High — no competitor does this; it addresses "so what should I do?" | Only works well with guided questions (which MPD uniquely has). |
| 4. | Emotional trajectory (trend) | Low — slope over feeling scores | Medium — tells the user whether things are changing | Reuses existing data; the trend arrow is a simple UI addition. |
| 5. | Anomaly detection | Low — deviation from most-common-feeling baseline | Medium — surfaces the most journaling-worthy days | Generates its own engagement loop. |
| 6. | N-of-1 experiments | High — new UI, experiment workflow, results view | Very high — genuinely novel, deeply engaging | Most ambitious Tier 2 idea; needs the above features as foundation. |
| 7. | Emotional vocabulary expansion | Low — curated synonym map, inline UI | Medium — improves data quality, teaches literacy | Quietly makes everything else better. |
| 8. | Therapy-export report | Medium — PDF generation, template | Medium — reaches a motivated audience | Opens a distribution channel. |
| 9. | "This day in emotional history" | Medium — temporal lookup, delta display | Medium — emotionally resonant | Best as a weekly highlight, not a daily feature. |
| 10. | Pattern lifecycle & cross-question synthesis | Low — rolling counts, question-key distribution | Low-Medium — adds depth but not urgency | Polish items; add after the core differentiators ship. |