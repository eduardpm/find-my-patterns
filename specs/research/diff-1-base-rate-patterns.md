# Differentiator Plan: Base-Rate-Aware Patterns (Statistical Lift)

**Date:** 2026-08-24
**Part of:** `specs/research/differentiator-opportunities.md` — Tier 1, Build First
**Companion plans:** `diff-2-temporal-precedence.md`, `diff-3-emotional-trajectory.md`

---

## The business idea

**Stop counting co-occurrences. Start measuring how much more likely a feeling becomes.**

Every pattern engine today — including Mood Pattern Diary's current one — works the same way: count how many times topic X and feeling Y appear together. When the count crosses 3, surface the pattern. The problem is that a pattern built this way is only as good as the user's baseline. If they're "tired" in 80% of all entries, then *any* topic will co-occur with "tired" most of the time. The same 3-entry threshold that catches real signals will also catch the user's dominant moods, treating them as discoveries when they're just the background radiation of their emotional life.

Base-rate-aware patterns change the question from "how often do these two things appear together?" to "how much more likely is this feeling when this topic is present than when it isn't?" A pattern stops being a fact about a topic — "meetings and anxiety appear together 8 times" — and becomes a fact about the topic's *relationship* to the feeling: "you are 6× more likely to feel anxious when meetings are in the picture."

This reframes the Insights screen entirely. Today it's a list of co-occurrences. Tomorrow it's a ranked report of the strongest emotional influences in the user's life, sorted by statistical strength, with the noise filtered out.

---

## The logic

### 1. The baseline is the entire diary, not just the match entries

For every topic→feeling pair that crosses the existing ≥3 co-occurrence threshold, the engine asks a second question:

- **With the topic present:** across all entries where topic X appears, what fraction have feeling Y?
- **With the topic absent:** across all entries where topic X does NOT appear, what fraction have feeling Y?
- **Lift** = (rate with topic) ÷ (rate without topic)

This requires looking at the whole diary, not just the entries that matched. That's the key — base-rate awareness means the engine knows how common the feeling is *in general.*

### 2. An example the user can understand

```
"meetings" → "anxious"

  With meetings:     8 of 12 entries → 67% anxious
  Without meetings:  3 of 28 entries → 11% anxious
  Lift:              6.1×

  Base rate:         26% of all entries are anxious
```

The user reads this as: "Meetings make me more than 6 times as likely to feel anxious compared to my normal baseline." That's a claim worth investigating. The current system just says "you felt anxious in 8 entries mentioning meetings" — which sounds like a lot until you realize the user is anxious all the time anyway.

### 3. Lift is a ranking function, not just a display value

The engine doesn't just compute lift — it uses it to decide which patterns matter:

| Lift range | Interpretation | UI treatment |
|---|---|---|
| < 1.0× | The feeling is *less* likely when the topic is present. This is an anti-pattern — worth surfacing if the gap is large. | Show as "Topic appears to reduce this feeling" |
| 1.0× – 2.0× | Negligible. The topic barely moves the needle. | Suppress; don't show even if co-occurrence count is ≥3. This is noise. |
| 2.0× – 3.0× | Moderate. Worth surfacing but not highlighting as strong. | Show at normal prominence |
| > 3.0× | Strong. The topic meaningfully changes the emotional landscape. | Show at high prominence with a "strong pattern" badge |
| > 5.0× | Very strong. This is the user's biggest emotional lever. | Pinned to the top of Insights with an "explore" prompt |

The minimum co-occurrence threshold (currently 3) still applies — lift on 1 or 2 co-occurrences is meaningless regardless of the ratio. But the threshold becomes a floor, not the decision. A pattern with 12 co-occurrences and 1.1× lift is noise. A pattern with 4 co-occurrences and 4.5× lift is a signal.

### 4. Direction flips — some topics reduce negative feelings

Not every pattern is "topic X makes me feel worse." A user might write about "walking the dog" and consistently feel calm — but their base calm rate is low. The lift captures this too: "You are 4× more likely to feel calm when you mention walking the dog." These positive patterns are currently invisible in a co-occurrence-only engine because "calm" might still be less common than "tired" even after the lift, and a raw count wouldn't notice them.

The engine should deliberately surface positive-lift patterns, not just negative ones. They're the patterns the user wants to *encourage.*

### 5. Withdrawal still works — evidence changes, lift changes

If the user edits an entry and removes a topic mention, the lift is recomputed from the database. If the lift drops below 2.0×, the pattern is withdrawn — just like the current withdrawal rule, but triggered by statistical strength rather than raw count. If the user edits the feeling on enough entries, the same thing happens.

The lift-based pattern inherits the existing "disappears when evidence changes" property while making the evidence standard meaningfully higher.

### 6. The UI summary each pattern needs

Every pattern card should carry, in compact form:

- **The lift value** (e.g. "6.1×")
- **The with/without comparison** (e.g. "anxious in 8/12 entries with meetings, but only 3/28 without")
- **A strength label** derived from the lift range
- **Tap to see the entries** — the evidence trail, showing exactly which entries produced the with and without counts

---

## The value

### vs. the current MPD engine

The current ≥3 co-occurrence rule produces patterns that are *true but weak.* A topic that co-occurs with "tired" 8 times feels meaningful until you realize every topic co-occurs with "tired" because the user is always tired. Lift-based patterns don't have this problem — a topic can only surface if it *changes* the emotional baseline, not just rides on top of it.

### vs. Bearable

Bearable is the only commercial product that does something similar, and it does it for pre-defined user trackers, not free text. Its correlation engine requires "at least 3 days *with* a factor and at least 3 days *without* the same factor," and it admits in its own docs that correlations can mislead. But Bearable can't mine free text — the user must decide what to track in advance. MPD would be the only product that does statistical lift from *unprompted free text* that the user didn't pre-tag.

### vs. Rosebud / Mindsera

These use LLMs to narrate "insights" that the user cannot verify. The LLM has no access to the full statistical picture — it sees what the prompt gives it — and it cannot compute a true lift. It can only generate prose that sounds insightful. MPD's lift is a number with a formula the user could reproduce by hand from the entries shown. That's the accountability thesis in practice.

### vs. Daylio

Daylio's "Influence on Mood" statistic compares mood with an activity to mood without it, and rates results Low/Medium/High. It's functionally similar to lift, but the input is icons the user taps, not free text. And Daylio never shows the raw numbers — only a confidence band. MPD can show the exact fraction, the lift value, and the entries behind each side of the comparison.

### The user's emotional takeaway

A co-occurrence engine says: "Here's what happens." A lift-based engine says: "Here's what *matters.*" The user can look at a list of 20 topic→feeling pairs and instantly see which ones are background noise and which ones are real levers in their emotional life. That distinction is the whole point of a diary that detects patterns — and it's the one distinction no other product makes.

---

## Relationship to the other differentiators

- **Temporal precedence** (diff-2) answers *when.* Lift answers *how much.* Together they say "meetings make you 6× more likely to feel anxious, and they typically precede the anxiety by 2-4 hours."
- **Emotional trajectory** (diff-3) answers *is it changing.* A 6× lift that is trending down is a different story than a 6× lift that is stable. Lift gives the current state; trajectory gives the story over time.

The three together form a complete picture of a pattern: how strong it is, what order it happens in, and whether it's getting better.

---

## What this differentiator does NOT do

- It does not prove causation. Lift is still correlation — it just measures it honestly. The "n-of-1 experiment" feature (Tier 2 in the opportunities doc) would address causality later.
- It does not replace the co-occurrence threshold. Lift is meaningless on tiny sample sizes. The ≥3 minimum stays.
- It does not require more data from the user. All the information needed — topic presence per entry, feeling per entry — already exists in the database. The lift is a view on existing data, not a new data model.