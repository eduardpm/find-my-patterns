# Existing Differentiator Plan: Confirmed Feelings

**Date:** 2026-08-24
**Part of:** `specs/research/differentiator-opportunities.md` — Existing Differentiator #2
**Other existing diff plans:** `diff-existing-1-auditable-patterns.md`, `diff-existing-3-local-inference.md`, `diff-existing-4-free-text-topics.md`, `diff-existing-5-guided-questions.md`
**New diff plans:** `diff-1-base-rate-patterns.md`, `diff-2-temporal-precedence.md`, `diff-3-emotional-trajectory.md`

---

## What it is today

Every mood or journaling product handles feelings in one of two ways. Either it asks the user to pick a mood (Daylio, Bearable, Apple State of Mind, How We Feel) — tap an icon, select a word, drag a slider. Or it infers the mood from text using AI and shows the result as fact (Rosebud, Mindsera). Nobody does both in sequence.

Mood Pattern Diary does a third thing: **suggest → confirm or override.** The AI reads the entry text and proposes a feeling. The user sees it, decides whether it's right, and either confirms or picks a different one. Only feelings the user acted on — `confirmed` or `overridden` — count as evidence for patterns. A `suggested` feeling that the user never saw or ignored is treated as if it doesn't exist.

This is already built and constitutionally protected. The `CONFIRMED_FEELING_SOURCES = ['confirmed', 'overridden']` constant in `patterns.service.ts` gates every pattern computation. The `feeling_source` column in `diary_entries` tracks the full lifecycle: `unset → suggested → confirmed | overridden`. The inference worker in `inference/worker.ts` writes `suggested` and never writes `confirmed` — only the user's explicit action through the API can set a feeling to `confirmed` or `overridden`.

The competitive research confirmed this is genuinely unoccupied: every other product does one or the other, never the hybrid. And the `overridden` state is particularly interesting — it means the user explicitly rejected the AI's suggestion. That's a signal about the AI's accuracy, and a signal about the user's self-awareness. Neither is being used today.

---

## The business idea

**The AI proposes. The human decides. The engine respects the difference.**

This is more than a UX pattern. It's a statement about who is in charge. The AI is a helpful assistant that reads your writing and makes a guess. The human is the authority that accepts or rejects the guess. The pattern engine is the impartial recorder that only counts what the human confirmed.

The current implementation is functionally correct but invisible. The confirmation step feels like a chore — a required tap before saving. It should feel like the most important tap in the app, because it is the moment the human asserts authority over the machine.

---

## The logic

### 1. The confirmation step should teach, not just gate

Today, confirming a feeling is a single tap: tap the feeling chip, save. The user gets no feedback about what happened or why. A richer confirmation step would:
- Show why the AI suggested this particular feeling (e.g., "Suggested because your entry mentions meetings and deadlines — words that often appear alongside anxious in your diary.")
- Show how this feeling compares to the user's baseline ("You've felt anxious in 12% of your entries this month.")
- If the user is about to override, note that too ("You usually feel neutral when writing about this topic. Are you sure?")

The confirmation step becomes a moment of self-reflection, not a hurdle.

### 2. Override data is a quality signal — use it

Every time the user overrides the AI's suggestion, that's a data point about the AI's accuracy. Over time, the engine can compute:
- **Per-feeling accuracy:** which feelings does the AI get right most often? Which does it miss?
- **Per-topic accuracy:** does the model consistently misread certain topics?
- **Trend over time:** is the model getting better (the user confirms more) or worse (the user overrides more)?

This data can be used to tune the inference prompt, adjust the model's confidence threshold, or surface to the user: "The AI gets your feelings right 78% of the time. It does best with 'anxious' and 'happy,' and struggles most with 'tired' vs. 'exhausted.'"

This turns the override from a failure into a feature — the app learns from being wrong, and the user can see it learning.

### 3. The confirmation ratio is a product metric the user should see

A user who confirms 90% of suggestions is having a different experience than one who confirms 30%. The first user trusts the AI; the second is fighting it. The product should surface this: "You agree with the AI's suggestions 82% of the time. When you don't, you usually feel more [feeling] than the AI guessed."

This is honest, and honesty builds trust. Rosebud and Mindsera cannot show this because their AI inferences are final — there's no confirmation step to measure against.

### 4. "Suggested but not confirmed" entries are an untapped engagement lever

If a user writes an entry, gets a suggested feeling, but doesn't confirm or override before closing the app, that entry sits in `feeling_source = 'suggested'` limbo. It doesn't count toward patterns. The user might not even realize it's incomplete.

The app should surface these entries gently: "You have 2 entries waiting for a feeling. Your patterns are missing data until you confirm them." This turns a dead state into a prompt to return.

### 5. The feeling vocabulary itself is a differentiator — make it richer

The current feeling set (happy, excited, neutral, sleepy, exhausted, stressed, sad, depressed, plus variants) is a good start but small. The confirmation step is the natural place to expand it. When the user overrides to a different feeling, offer more precise alternatives within the same emotional neighborhood. "You selected 'angry.' Would 'frustrated,' 'irritated,' or 'resentful' be more precise?" This is the emotional vocabulary expansion from Tier 3 of the opportunities doc, positioned as a natural extension of confirmation rather than a separate feature.

---

## The value

### It's the cleanest unclaimed idea in the market

The competitive review was explicit about this: *"Every AI journal infers the mood and shows it; every tracker asks the user to pick it. Nothing found does suggest → confirm or override, and nothing found treats only user-acted feelings as evidence."* This is the idea that no competitor can accidentally stumble into — it requires building both the AI inference pipeline and the human gate, and choosing to treat only the human's decision as truth.

### It makes the privacy story concrete

"Your data never leaves the machine" is an abstract claim. "The AI suggests a feeling, but you decide — and only your decision counts" is a concrete experience. The user feels in control because they are in control. Every confirmation is a small reminder that the AI works for them, not the other way around.

### It makes the pattern engine defensible

If the user questions a pattern — "Why does it say I'm anxious about meetings?" — the answer is not "the AI thinks so" but "you confirmed anxious in these 4 entries." The feeling was the user's choice, not the AI's. This is the accountability thesis again, but at the level of individual feelings rather than aggregate patterns.

---

## How to make it stronger

1. **Explain the suggestion.** Add a one-line reason to every suggested feeling: "Suggested because..." powered by the same inference that produced the suggestion. The model already has the entry text; asking it to produce a short justification alongside the feeling key costs one extra inference token.

2. **Track and surface override statistics.** Store a simple `inference_accuracy` summary (per month, per feeling, per topic category) and show it on the Insights screen or a small settings panel. "AI accuracy: 78% this month."

3. **Incomplete-entry reminders.** Add a badge to the Today screen: "3 entries need your feeling." Tap to open a quick confirmation flow for all pending entries at once.

4. **Emotional neighborhood during override.** When the user overrides, show 2-3 adjacent feelings rather than the full list. This reduces decision fatigue and subtly teaches emotional granularity.

5. **Feeling history per topic.** When the user is about to confirm a feeling for an entry that mentions a known topic, show what they felt previous times: "You felt anxious the last 3 times you wrote about meetings. This time: [suggested feeling]." This closes the loop between individual entries and patterns.

---

## How to leverage it better

### In the README and marketing

"Other AI journals tell you how you feel. We suggest, and you decide — only the feelings you confirm ever count toward your patterns."

### Against specific competitors

- "Rosebud infers your mood from text. We ask you. If the AI is wrong, you override it — and only your answer counts."
- "Daylio makes you pick a mood from icons. We read your writing, make a suggestion, and let you confirm or change it — best of both."

### In the product itself

The confirmation step should never feel like a chore. Speed it up: the suggested feeling is pre-selected, the save button is prominent, and confirming takes one tap. Overriding takes two taps. The path of least resistance is agreeing with the AI — but disagreeing is deliberately easy. This is the UX equivalent of the constitutional principle: the AI suggests, the human decides, and the UI makes both actions equally accessible.

---

## What this differentiator does NOT do

- It does not make the AI better at guessing. That's a model quality problem, not a product problem. But the override data can inform model selection and prompt tuning over time.
- It does not require the user to know feeling vocabulary upfront. The AI suggestion lowers the barrier — the user can always just confirm and move on.
- It is not a therapy tool. The feeling confirmation is a data-quality gate, not a diagnostic instrument.