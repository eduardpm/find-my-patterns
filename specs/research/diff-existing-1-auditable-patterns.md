# Existing Differentiator Plan: Patterns You Can Audit

**Date:** 2026-08-24
**Part of:** `specs/research/differentiator-opportunities.md` — Existing Differentiator #1
**Other existing diff plans:** `diff-existing-2-confirmed-feelings.md`, `diff-existing-3-local-inference.md`, `diff-existing-4-free-text-topics.md`, `diff-existing-5-guided-questions.md`
**New diff plans:** `diff-1-base-rate-patterns.md`, `diff-2-temporal-precedence.md`, `diff-3-emotional-trajectory.md`

---

## What it is today

Every AI journal on the market produces insights the user cannot verify. Rosebud generates LLM prose about patterns and warns about "hallucinations" in its own docs. Mindsera shows topics in one panel and emotions in another, leaving the user to connect them. Daylio and Bearable do real counting, but only for pre-defined icons and tags — and they're closed-source, so the user can't inspect the calculation.

Mood Pattern Diary is different in one structural way: every pattern claim is **recomputed from the database on read.** There is no generated prose that goes stale. If the user edits or deletes an entry, the pattern engine reruns the count, and if the count drops below the threshold (≥3), the pattern is withdrawn. The claim disappears the moment the evidence does.

This is already built. The `patterns.service.ts` file recomputes patterns from `diary_entries` and `topics` on every `GET /insights` call, filtering to only entries where `feeling_source IN ('confirmed', 'overridden')`. Patterns that fall below the threshold are dropped. The `occurrence_count` is a live number.

But right now, almost none of this is visible to the user. The Insight screen shows narrative text — "You felt sleepy in 4 recent entries mentioning coca cola" — but doesn't show *which* 4 entries, doesn't show that the pattern would disappear if one of them were edited, and doesn't explain the rule. The audit trail exists in data but not in product.

---

## The business idea

**Make the audit trail the product.**

Every pattern card should function like a small investigative report. The user can tap into it and see exactly which entries produced it, what feeling each had, when they were written, and what the threshold rule is. If the pattern was withdrawn — either because entries were edited or deleted, or because the count fell — the user should see that too, with the reason.

This transforms Insights from a passive read into an active tool. The user doesn't just receive claims — they cross-examine them. And when one disappears, they understand why.

---

## The logic

### 1. Every pattern needs an evidence section

Currently a pattern has `occurrence_count` but no entry references. The engine should additionally return the list of entry IDs (and any summary needed for display: date, feeling label, snippet of topic context) that back the pattern. The UI shows these as a tappable list inside the pattern detail view.

### 2. The rule should be stated in the UI

"3 of 3 entries mentioning 'meetings' felt anxious" is more honest than "You felt anxious in 3 entries mentioning meetings." The first version states the rule — the user can see that the claim rests on exactly 3 entries, that 3 is the minimum, and that adding or removing one would change the outcome.

### 3. Withdrawn patterns need a place

When a user edits an entry and a pattern disappears, they currently see nothing. That's unsettling — a claim they had come to rely on is gone with no explanation. Instead, a withdrawn pattern should leave a trace: a muted card in the Insights view that says "This pattern was withdrawn on [date] because the supporting evidence changed. You edited an entry from 'anxious' to 'neutral' on [date]." The user can tap to see the remaining entries that *almost* support the pattern (if any still exist).

This sounds like a small feature but it's the accountability thesis in one interaction. No other product even attempts it — their insights are generated prose that simply disappears when the prompt is regenerated.

### 4. The evidence count should be prominent, not buried

The pattern card's most visible number should be the occurrence count — e.g., a badge that says "4 entries." This is the user's first cue that the claim is countable, not AI prose. Tapping the badge opens the evidence list.

### 5. Patterns should note their own recency

A pattern with 4 occurrences from the last 7 days is more relevant than one with 4 occurrences spread across 6 months. The evidence section should show the date range: "Based on 4 entries from March 3 to August 18, 2026." This also implicitly tells the user whether the pattern is active or dormant.

---

## The value

### vs. Rosebud / Mindsera

Their insights are LLM prose. The user cannot verify them. Rosebud's own docs warn about hallucinations. A pattern with a visible evidence trail is the anti-Rosebud — every claim is falsifiable.

### vs. Daylio / Bearable

They do real counting but hide the raw data. Daylio shows "Influence on Mood" as a confidence band (Low/Medium/High) without the numbers behind it. Bearable shows correlations but doesn't let you click through to the supporting days. MPD would be the only product where every pattern is transparent down to the entry level.

### vs. the current MPD

The user currently reads a sentence like "You felt sleepy in 4 recent entries mentioning coca cola" and has to trust it. Adding evidence makes the experience go from "the app says" to "I can see." That's the shift from a consumer product to a tool.

---

## How to make it stronger

1. **Evidence trail in the API.** The `PatternOut` interface should include an `entries` array — the IDs, dates, feelings, and a short text snippet per supporting entry. The web and Android clients render these as a tappable list.

2. **Withdrawn patterns endpoint or section.** When recomputation drops a pattern, don't silently delete it — store a `withdrawn_patterns` record (pattern ID, previous count, previous narrative, withdrawn date, reason code like `below_threshold` or `entry_edited`). Show these in a collapsed "Withdrawn" section on the Insights screen.

3. **Rule visibility.** Add a small line to every pattern card that states the rule: "Based on 4 entries (threshold: 3)." The user learns how the system works by reading it.

4. **Entry-to-pattern navigation.** From any entry in the Today or Calendar view, show which patterns (if any) it supports. "This entry is part of the 'meetings → anxious' pattern." This makes the connection between writing and patterns concrete — every entry matters.

5. **"Proof of work" in onboarding.** On first run, after the user has enough entries to produce a pattern, show a brief tutorial: "This pattern exists because you felt anxious in these 3 specific entries. If you edit any one of them, the pattern may disappear. Try it." Let them test the system. Nothing builds trust like letting the user break a claim and see it vanish.

---

## How to leverage it better

### In the README and marketing

Don't say "pattern detection." Say "every pattern shows its receipts." The entire competitive position rests on the difference between AI prose and counted evidence. Every piece of copy should emphasize that the user can check every claim.

### Against specific competitors

- "Rosebud warns you about AI hallucinations. We don't have to — every claim is backed by entries you can read."
- "Daylio shows you Low/Medium/High confidence. We show you the numbers and the entries."
- "Bearable requires you to define what to track first. We find it from your writing, and then show you exactly where."

### In the product itself

The Insights screen should have a one-sentence explanation at the top that never goes away: "Every pattern below is counted from your confirmed entries. Tap any pattern to see which entries it comes from." This is the product promise, stated in the product.

---

## What this differentiator does NOT do

- It does not make the patterns more statistically sophisticated (that's diff-1, lift).
- It does not add new pattern types (that's diff-2 and diff-3, precedence and trajectory).
- It does not change how patterns are computed — only how they're presented and what the user can do with them.