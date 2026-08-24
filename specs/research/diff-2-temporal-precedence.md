# Differentiator Plan: Temporal Precedence

**Date:** 2026-08-24
**Part of:** `specs/research/differentiator-opportunities.md` — Tier 1, Build After Lift
**Companion plans:** `diff-1-base-rate-patterns.md`, `diff-3-emotional-trajectory.md`

---

## The business idea

**"Meetings and anxiety co-occur" is a statistic. "Meetings precede anxiety by 2-4 hours" is a clue about cause.**

Every mood tracking and journaling product on the market answers the question "what goes with what." Daylio shows which activities influence your mood. Bearable shows which factors correlate with which symptoms. Mindsera shows which topics appear alongside which emotions. They all answer *co-occurrence.* None of them answer *sequence.*

But sequence is what turns a pattern from an observation into something the user can act on. Knowing that meetings and anxiety happen on the same day is mildly interesting. Knowing that meetings consistently appear in morning entries and anxiety consistently appears in afternoon entries — and that this order holds 5 out of 7 times — tells the user where to look and what to change.

Mood Pattern Diary is uniquely positioned to do this because its guided question flow already segments the day. Every entry answers a specific question at a specific time. "What happened this morning?" at 9 AM and "How are you feeling now?" at 3 PM produce entries that naturally carry temporal structure. No other product has this combination — guided questions with known time slots, free-text topic extraction, and a deterministic engine that can count across entries.

---

## The logic

### 1. Temporal precedence is not about timestamps — it's about question ordering

The engine doesn't need to compute exact hour differences between entries. It needs to know whether the topic typically appears in *earlier* entries than the feeling, regardless of how many hours apart they are. The guided question keys provide this naturally:

- Questions are ordered: morning questions come before afternoon questions, which come before evening questions.
- If the user answers "What's on your mind this morning?" and mentions "project review," and then answers "How are you feeling right now?" at 3 PM and reports "anxious," the engine can note that the topic appeared in an earlier slot than the feeling.
- If both appear in the same entry — the user writes about meetings and confirms "anxious" in a single session — the precedence is "concurrent."

The key insight: **the engine tracks which question key the topic appears in and which question key the feeling appears in, then compares their relative positions in the question order.** This works even for same-day entries where both topic and feeling appear but in different sessions — the morning check-in mentions the topic, the afternoon check-in confirms the feeling. The engine knows morning came first because the question set defines it that way.

### 2. Three precedence outcomes

For every topic→feeling pair that crosses the pattern threshold:

| Outcome | Definition | Display example |
|---|---|---|
| **Topic precedes feeling** | The topic consistently appears in earlier question slots than the feeling (e.g. morning mentions → afternoon anxiety in 5 of 7 matched entries) | "Meetings tend to come first — you mention them in morning entries, and anxiety appears in later check-ins 5 of 7 times." |
| **Concurrent** | Topic and feeling appear in the same entry session most of the time | "Meetings and anxiety tend to happen together — they appear in the same entry 6 of 8 times." |
| **Feeling precedes topic** | The feeling appears in earlier question slots than the topic (less common, but possible — e.g. morning anxiety → later mention of family) | "Anxiety tends to come first — it appears in your morning check-in, and you later write about family in the evening." |

The third outcome is rare but important. It might mean the user's emotional state colors what they choose to write about, rather than the topic triggering the feeling. That's a different kind of insight.

### 3. The precedence score is a consistency check, not a binary flag

The engine shouldn't say "precedes" if the order holds only 3 out of 7 times. It should report how consistent the order is:

- **Strong precedence** (≥70% of matched entries follow the same order): surface prominently — "Meetings consistently precede anxiety (7 of 9 times)"
- **Weak precedence** (50-70%): surface with a qualifier — "Meetings often precede anxiety, but not always (5 of 9 times)"
- **No clear order** (<50%): don't surface precedence at all; fall back to showing the pattern with the lift only

This prevents the engine from making confident-sounding claims about weak temporal signals.

### 4. Multi-entry days are the richest data

A day with a morning entry AND an afternoon entry AND an evening entry gives the engine the most to work with. If the user mentions "deadline" in the morning, feels "stressed" in the afternoon, and writes about "procrastination" in the evening — and this repeats — the engine can trace a full emotional arc through the day.

The guided question flow was designed to produce exactly this kind of multi-entry data. Temporal precedence is the feature that justifies why the questions exist in the first place, beyond being pleasant to answer.

### 5. What the UI shows per pattern

Each pattern card, in addition to lift and occurrence count, shows a precedence indicator:

```
meetings → anxious
  6.1× lift · 8 occurrences
  ⏱ Precedes — topic appears in morning entries,
  feeling appears in afternoon check-ins (7 of 8 times)
```

Tapping into the pattern detail shows all the entries that produced the precedence claim, ordered by the question slot, so the user can verify the sequence themselves.

### 6. Precedence works even for single-entry days

If the user writes only one entry per day and that entry mentions both the topic and the feeling, the precedence is "concurrent." This is the most common case for users who don't use multiple daily check-ins. It's still informative — it tells the user "these things happen at the same time" — but it doesn't unlock the full value of the feature. The precedence engine is strongest when the user uses the guided flow as designed: morning, afternoon, evening check-ins.

---

## The value

### It turns patterns into interventions

"Meetings and anxiety co-occur" provokes: *"Okay. What do I do?"* There's no obvious action.

"Meetings consistently precede anxiety by several hours" provokes: *"So if I schedule fewer meetings, or schedule them differently, or prepare differently for them, my anxiety might drop."* The action is implied by the order.

This is the difference between a product that *observes* your life and one that helps you *change* it. Every AI journal produces observations. None produces causal clues with a consistency score. This is the lever — and it's the reason temporal precedence belongs in Tier 1.

### It justifies the guided question design

The question set was always described as "engineered for pattern detection," but until temporal precedence ships, that's invisible to the user. With precedence, the user can see that answering the morning question and the afternoon question separately gives the app data it couldn't get from a single long entry. The structure of the product becomes the feature.

### It has no competitor

- **Bearable** does "previous day / same day / next day" correlations for pre-defined factors, but only across day boundaries, never within a day, and never from free text.
- **Daylio** shows "influence on mood" but with no time dimension at all.
- **Rosebud / Mindsera** produce LLM prose that might mention timing if the model guesses it, but the model has no structured access to question slots, no consistency scoring, and no way to prove what it claims.
- **No product found** does intra-day temporal precedence from free text. Not one.

---

## Relationship to the other differentiators

- **Lift** (diff-1) answers *how much.* Precedence answers *what order.* A pattern with 6.1× lift AND strong precedence is the most actionable thing in the entire Insights screen.
- **Emotional trajectory** (diff-3) answers *is it changing.* A pattern where precedence was strong in March but has faded to concurrent (the user resolved whatever was causing the sequence) tells a story that none of the three features alone could tell.

---

## What this differentiator does NOT do

- It does not prove causation. Precedence is temporal correlation, not experimental evidence. The "n-of-1 experiment" feature (Tier 2) would address causality.
- It does not work well for users who write only one entry per day — they'll see "concurrent" most of the time. The feature is at its best for users of the guided multi-entry flow.
- It does not compare across day boundaries by default (e.g. "topic on Monday, feeling on Tuesday"). The engine could be extended to do this, but the initial version is intra-day only — the day's question flow provides the most reliable temporal structure.