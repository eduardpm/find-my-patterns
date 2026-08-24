# Differentiator Plan: Emotional Trajectory per Topic

**Date:** 2026-08-24
**Part of:** `specs/research/differentiator-opportunities.md` — Tier 1, Build After Lift & Precedence
**Companion plans:** `diff-1-base-rate-patterns.md`, `diff-2-temporal-precedence.md`

---

## The business idea

**A pattern is not a fact. It's a story with a beginning, a middle, and — importantly — a direction.**

Every pattern engine on the market answers the question "what goes with what." Lift (diff-1) answers "how much does it matter." Precedence (diff-2) answers "what comes first." But none of them answer the question users actually care about most: *"Is it getting better?"*

A pattern that says "commute → angry, 8 times" is a static snapshot. It could mean the commute has been reliably angering for months. It could mean the user was angry about the commute during a bad week in March and it's never recurred. The count alone can't distinguish a fresh wound from a scar.

Emotional trajectory answers this by showing the direction. Each pattern gets a trend: improving (the associated feelings are getting more positive over time), worsening (they're getting more negative), or stable (they're holding steady). This turns every pattern from a dead statistic into a living story — and it gives the user the single most emotionally useful piece of information the app can provide: whether things are moving in the right direction.

---

## The logic

### 1. Every feeling has a position on a valence scale

The feeling set already includes a valence — how negative-to-positive the feeling is. The existing feelings (happy, excited, neutral, sleepy, exhausted, stressed, sad, depressed, and more) each sit somewhere on this scale. A confirmed or overridden entry carries both a feeling key and, through it, a valence score.

For trajectory to work, the engine needs a consistent numeric scale. The simplest version: assign each feeling an integer from most negative (e.g. depressed = 0, sad = 1, exhausted = 2, stressed = 3, sleepy = 4, neutral = 5, calm = 6, content = 7, happy = 8, excited = 9). This scale already exists implicitly in the feeling data — it just needs to be made explicit and stable.

### 2. The trend is the slope of feeling scores over time

For each pattern (topic→feeling pair), the engine takes every entry where the topic appeared, ordered by date, and plots the feeling score:

```
"commute" entries over time:
  March 3:   angry (1)
  March 7:   angry (1)
  March 12:  frustrated (2)
  March 18:  frustrated (2)
  March 25:  neutral (5)
  April 1:   neutral (5)
  April 5:   calm (7)

  First half average:   (1+1+2+2) / 4 = 1.5
  Second half average:  (5+5+7) / 3 = 5.7
  Trend: ↑ Improving (score rose from 1.5 to 5.7)
```

The engine splits the occurrences in half chronologically and compares the average feeling score of the first half against the second half. A rising score = improving. A falling score = worsening. Scores within a narrow band of each other = stable.

### 3. Three trend states, with thresholds to prevent noise

| Trend | Condition | Display |
|---|---|---|
| ↑ Improving | Second-half average is meaningfully higher than first-half average | Green up arrow + "Getting better" |
| ↓ Worsening | Second-half average is meaningfully lower than first-half average | Red down arrow + "Getting worse" |
| → Stable | Difference between halves is small, or there are too few data points to split | Gray arrow + "Steady" |

"Meaningfully higher" needs a threshold — otherwise a 0.1-point difference on 4 entries reads as "improving." A reasonable minimum: the difference between halves must cross at least one full feeling step on the valence scale (e.g., a shift from "stressed" to "neutral" territory, not just from "sad" to "slightly less sad"). This prevents the engine from overclaiming.

### 4. "Too few to trend" is a valid answer

A pattern with 3 occurrences — the minimum threshold — can't meaningfully trend. There's no "first half" and "second half" with three data points. The engine should show "Not enough data yet" instead of forcing a trend. As the pattern grows to 5, 8, 12 occurrences, the trend becomes more reliable and the engine gains confidence.

This naturally rewards consistency — the user who writes regularly gets richer trajectory data than the user who writes sporadically. The feature teaches the value of the habit.

### 5. The trend arrow is the headline; the timeline is the proof

The pattern card shows a compact trend indicator — an arrow and a label, placed next to the lift value. Tapping into the pattern detail shows the full chronological list: every entry where the topic appeared, ordered by date, with the feeling icon and valence score visible. The user can see the story for themselves: "angry, angry, frustrated, frustrated, neutral, neutral, calm."

This is the accountability thesis again — the trend is a computed claim, and the user can verify it by reading the timeline. No AI journal can make this offer.

### 6. The trend updates immediately when entries change

If the user edits an old entry and changes the feeling from "angry" to "neutral," the trend recomputes. A pattern that was "worsening" might become "improving" or "stable." This is the same withdrawal logic as the existing pattern engine, applied to a richer signal.

But here it's more emotionally powerful: an edit doesn't just withdraw a claim — it changes the *story* the pattern tells. The user can see that their relationship with a topic has shifted because they're re-evaluating past entries or because their present entries are different. The diary becomes a living document, not an archive.

---

## The value

### It answers the question every journal user actually has

The reason people keep diaries is not to accumulate data. It's to see their own arc — to know whether they're growing, healing, stuck, or backsliding. Every AI journal on the market produces insights that read like horoscopes: plausible, vague, untethered from evidence, and static. "You seem stressed about work lately." Thanks. Is that new? Is it getting worse? Is the thing I started doing three weeks ago helping?

Emotional trajectory answers those questions with data the user can see. It doesn't narrate growth in AI prose — it shows the arrow, the timeline, and says "here, you tell me."

### It makes long-term use rewarding

A pattern engine that only shows co-occurrences plateaus quickly. After two months, the user has seen every topic→feeling pair. The engine has nothing new to say.

A trajectory-aware engine has something new to say every week. The direction changes. New patterns emerge with enough data to trend. Old patterns fade. The user opens Insights and sees not a static report but a living dashboard — some things are getting better, some are holding steady, one thing is getting worse, and here it is. This is the difference between a tool you use for two months and a tool you use for two years.

### It deepens the confirmed-feeling differentiator

The confirmed-feeling step — AI suggests, human confirms or overrides — was already identified as the cleanest unclaimed idea in the market. But its value compound when combined with trajectory. A confirmed feeling isn't just a gate that produces cleaner patterns. It means the trajectory is built on data the user *chose.* They didn't just let the AI label them as "angry" — they confirmed it, or overrode it to "frustrated" because that's what they actually felt. The arrow on a pattern is built from decisions the user made, not inferences the model made.

### It has no competitor

- **Rosebud / Mindsera** produce LLM-generated "weekly insights" prose that might mention trends — but the prose is generated, not computed, and cannot show the data behind it.
- **Daylio / Bearable** show mood-over-time charts, but these are aggregate mood level lines, not per-topic trends. They can tell you "your mood has been improving" but not "your relationship with meetings is improving while your relationship with family is worsening."
- **Exist.io** does trend lines for numeric attributes but not for topic→feeling pairs from free text.
- **No product found** shows per-topic emotional trajectory. Not one.

---

## Relationship to the other differentiators

The three Tier 1 differentiators form a complete picture of every pattern:

| Dimension | Feature | Question answered |
|---|---|---|
| Strength | Lift (diff-1) | How much does this topic change my emotional state? |
| Order | Temporal precedence (diff-2) | Does the topic come before the feeling, or do they happen at the same time? |
| Direction | Emotional trajectory (diff-3) | Is this pattern getting better, worse, or staying the same? |

Together, a single pattern card says: *"Meetings make you 6.1× more likely to feel anxious (lift), they typically precede the anxiety by several hours (precedence), and the pattern has been improving over the last month (trajectory)."* That's a complete thought. No other product can produce a sentence like that.

---

## What this differentiator does NOT do

- It does not predict the future. The trend shows what has happened, not what will happen. A "worsening" arrow is a warning, not a forecast.
- It does not explain *why* the trend is what it is. The engine shows the data; the user provides the interpretation. The companion piece is the anomaly detection feature (Tier 2 in the opportunities doc), which could surface the inflection points.
- It requires a minimum number of occurrences to be meaningful (at least 5-6 before a trend emerges). New patterns will show "Not enough data yet" until they mature.