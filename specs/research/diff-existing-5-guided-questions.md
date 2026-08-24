# Existing Differentiator Plan: Guided Questions Engineered for Pattern Detection

**Date:** 2026-08-24
**Part of:** `specs/research/differentiator-opportunities.md` — Existing Differentiator #5
**Other existing diff plans:** `diff-existing-1-auditable-patterns.md`, `diff-existing-2-confirmed-feelings.md`, `diff-existing-3-local-inference.md`, `diff-existing-4-free-text-topics.md`
**New diff plans:** `diff-1-base-rate-patterns.md`, `diff-2-temporal-precedence.md`, `diff-3-emotional-trajectory.md`

---

## What it is today

Every guided-prompt product on the market frames its questions as reflection aids. Stoic's prompts are "curated by experts" for depth. Rosebud's are "thought-provoking questions." Mindsera ships "50+ guided frameworks including CBT and anxiety templates." Day One offers "daily prompts" and templates. The user is asked to reflect, and the questions are designed to help them reflect better.

Mood Pattern Diary does something different, per FR-006 in the original spec: *"The set of guiding questions MUST be designed so that, beyond making entries easy to write, the answers they produce are reliable inputs for feeling inference and pattern detection — this is the primary design criterion for the question set."*

The questions are not just reflection aids. They're instruments. Every question is chosen because it produces answers that are likely to contain extractable topics and emotion-bearing language — the raw material the pattern engine needs. A question like "What happened this morning?" surfaces events (topics). A question like "How are you feeling right now?" surfaces emotional state (feelings). A question like "What's weighing on you?" surfaces stressors (topics with negative valence). The set is designed to produce data, not just prose.

The competitive review confirmed this framing is unique: "No product found frames its question set as engineered input to a correlation engine."

But the competitive review also identified the honest weakness: "This is invisible from the outside. A user cannot tell a pattern-engineered question from a reflection prompt until months of data have accumulated. It strengthens the product; it will not sell it on its own."

---

## The business idea

**The questions aren't just for you. They're for the pattern engine. And that's why they work.**

Guided questions solve three problems simultaneously. They make writing easier (the user doesn't face a blank page). They structure the data (each answer carries a known question key, a time slot, and a category). And they train the user to write the kind of entries that produce the best patterns — entries with concrete events, emotional language, and temporal context.

The questions should be presented to the user as a writing aid first and a data instrument second — but the data-instrument rationale should be documented and measurable. If the question set isn't producing extractable topics at a high rate, it needs to be tuned. The user may never think about the engineering behind the questions, but they'll feel the results: patterns that make sense, surfaced quickly, from entries that were easy to write.

---

## The logic

### 1. The question set is a product asset that needs maintenance

The current question set exists in the database seed (`backend/src/db/seed.ts`) with keys, categories, prompt text, trigger keywords, and a mandatory flag. The seed is static — the same questions for every user, forever.

This should evolve. The question set should be measured against SC-008 ("90% of guided entries yield a usable topic") and tuned when it falls short. Questions that reliably produce extractable topics stay. Questions that produce vague, untaggable answers are replaced. The question set is a living product asset, not a one-time seed.

### 2. Questions should adapt to what the engine already knows

A user who has been writing for three months has established patterns. The engine knows their recurring topics and dominant feelings. The questions should respond to this:

- If the user hasn't mentioned "family" in two weeks and it was a strong pattern before: "You haven't written about family in a while. How are things on that front?"
- If a pattern is trending worse: "'Commute' has been appearing with more negative feelings lately. What's changed about your commute?"
- If an anomaly was detected yesterday: "Yesterday you felt calm about something that usually makes you anxious. What was different?"

These are not generic prompts. They're questions generated from the user's own pattern data. They make the guided flow feel personal and intelligent rather than repetitive. They also reinforce the pattern engine's value — the user sees the engine's output turning back into questions that help them write.

### 3. The question structure should be visible to the curious user

The question set's rationale doesn't need to be front-and-center — "these questions are engineered instruments" is not a sellable claim. But it should be visible to users who want to understand how the product works. A small "Why these questions?" link in the guided flow, leading to a short explanation: "Each question is designed to surface the events, people, and feelings that power your patterns. Morning questions capture what happened. Midday questions capture how you're feeling. Evening questions capture what stayed with you."

This is transparency, not marketing. It's the same accountability thesis applied to the questions themselves.

### 4. The mandatory prompt should justify itself

The guided flow's first question is mandatory (per FR-004/FR-005). The user must answer at least one question before the entry can be finalized. The mandatory prompt should explain why: "This first question helps the engine understand what your day was about. The more concrete your answer, the better your patterns will be."

The user isn't being forced to answer a question for the sake of it. They're being asked because a concrete answer produces better data than a vague one, and better data produces better patterns. The user who understands this answers differently.

### 5. The question flow should produce the multi-entry rhythm that powers temporal precedence

The temporal precedence differentiator (diff-2) depends on the user writing multiple entries per day at different times. The guided question flow is what makes this natural — morning question at 9 AM, afternoon check-in at 3 PM, evening reflection at 8 PM. The questions are spaced because the pattern engine needs them spaced.

The reminder schedule (9:00, 12:00, 18:00, 21:00 per FR-013) aligns with the question slots. The reminders are not just nudges to journal — they're the engine's way of ensuring it gets data at the right temporal resolution. The user who answers three questions a day gives the engine intra-day temporal data that a single-entry user never provides.

---

## The value

### It's the quiet engine behind every other differentiator

Guided questions don't sell the product. But they make every other differentiator possible. Temporal precedence (diff-2) needs known question slots. Topic extraction (diff-existing-4) needs entries with concrete language about events and feelings — and guided questions elicit that. Confirmed feelings (diff-existing-2) needs entries where the feeling can be reliably inferred — and guided questions produce more emotionally explicit text than free-form journaling.

### It eliminates the blank-page problem without reducing the product to an icon grid

Daylio solves the blank-page problem by eliminating text — pick an icon, pick a mood, done. Rosebud solves it with AI chat. MPD solves it with structured questions that produce better data than either approach. The questions are the middle path between too little structure (blank page) and too much structure (icon grid).

### It makes the product sticky through routine

Four daily reminders producing three structured entries per day creates a rhythm. The user doesn't just "journal when they feel like it" — they answer specific questions at specific times, and the pattern engine rewards consistency with richer data. The reminders are not nagging; they're the engine asking for its fuel.

---

## How to make it stronger

1. **Measure question effectiveness.** Track per-question topic yield — what fraction of answers to each question produce at least one extractable topic. Replace low-yield questions. This is a build-time activity, not a runtime feature, but it should be done periodically.

2. **Personalized follow-up questions.** After a user has enough pattern data, generate one personalized question per day based on their patterns. "You've felt stressed about deadlines 4 times this month. What deadline is on your mind today?" Shown alongside the standard questions, marked as "Based on your patterns."

3. **Question rationale visible on demand.** A "Why this question?" link that explains the design logic. Short, honest, dismissible.

4. **Mandatory prompt justification.** The mandatory first question should carry a one-line explanation of why it matters: "The more concrete your answer, the better your patterns." This turns a requirement into a value proposition.

5. **Question-time alignment documented.** The README and the app should note that the reminder schedule (9 AM / 12 PM / 6 PM / 9 PM) is designed to produce the multi-entry rhythm that powers pattern detection. This makes the reminders feel intentional, not intrusive.

---

## How to leverage it better

### In the README and marketing

Don't lead with "guided questions." Lead with what the questions produce: "Answer a few questions each day, and the app finds the patterns in your answers." The questions are the means; the patterns are the value.

### Against specific competitors

- "Stoic has expert-curated prompts for reflection. Our questions are designed to find patterns — and they do both."
- "Daylio's two-tap entry is fast but misses everything you'd actually write. Our questions take 60 seconds and capture what matters."
- "Rosebud's AI chat is conversational. Our guided flow is structured to give the pattern engine what it needs. You'll see the results in weeks, not months."

### In the product itself

The guided flow should never feel like a form. Each question should appear one at a time, with the text area focused and ready. The mandatory question should be short and concrete. The follow-up questions should feel optional but welcoming. The "write freely instead" escape hatch should be always visible. The fastest path — answer the mandatory question, confirm the feeling, save — should take under 30 seconds.

---

## What this differentiator does NOT do

- It does not replace free-form journaling. The "write freely instead" option must always be available. Some days the user has something to say that doesn't fit a question. The guided flow is the default, not the only path.
- It does not require the user to understand the engineering. The question rationale is available on demand but never forced. The user should feel helped, not instrumented.
- It does not produce therapeutic frameworks. The questions are designed for data quality, not CBT or clinical intervention. They may incidentally align with therapeutic techniques, but that's not the design goal.