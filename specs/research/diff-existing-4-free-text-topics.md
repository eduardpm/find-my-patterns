# Existing Differentiator Plan: Free-Text Topic Extraction Without Pre-Defined Trackers

**Date:** 2026-08-24
**Part of:** `specs/research/differentiator-opportunities.md` — Existing Differentiator #4
**Other existing diff plans:** `diff-existing-1-auditable-patterns.md`, `diff-existing-2-confirmed-feelings.md`, `diff-existing-3-local-inference.md`, `diff-existing-5-guided-questions.md`
**New diff plans:** `diff-1-base-rate-patterns.md`, `diff-2-temporal-precedence.md`, `diff-3-emotional-trajectory.md`

---

## What it is today

Every correlation product on the market requires the user to define what to track before tracking begins. Daylio: pick activities from a pre-set icon grid. Bearable: "Make a decision about what aspect of health you want to learn more about," then create custom factors. Exist.io: define numeric attributes and tags. Apple State of Mind: select from a fixed word list. The user must know in advance what matters.

Mood Pattern Diary is different: the user writes naturally, and the AI extracts topics from the text afterward. There are no pre-defined trackers, no icon grids, no factor configuration screens. The user writes "had a long meeting about the Q3 budget with Sarah, then grabbed takeaway on the way home" and the system extracts "meeting," "Q3 budget," "Sarah," "takeaway." The pattern engine then watches which of these topics co-occur with which feelings over time.

This is partially occupied — Mindsera and Rosebud both extract topics from free text, and Memex does it locally. But none of them pairs the extracted topic with a counted feeling. The differentiation is not "we read your text" but "we read your text and then count."

The weakness is the model. `qwen3:4b` is a capable small model, but topic extraction quality is variable. The competitive review flagged this as the weakest link: "Topic extraction quality determines whether patterns are meaningful, and it is the one place where 'local only' costs real capability."

---

## The business idea

**The user writes naturally. The system finds what matters. No configuration, no icon grids, no guessing in advance.**

This is the entry point to the entire value proposition. Every other product starts with a configuration step — pick your activities, define your factors, set up your trackers. MPD starts with "write about your day." The topic extraction is the magic that makes the simplicity thesis possible: you don't need to know what to track because the system figures it out.

But the magic needs to be more reliable than it is today. A 4B model extracting topics from diary text will sometimes miss important topics, hallucinate irrelevant ones, or produce inconsistent labels (e.g., "meeting" on Monday and "meetings" on Tuesday). The product needs a deterministic normalization layer between the model's output and the pattern engine's input.

---

## The logic

### 1. The model proposes; the backend normalizes

The key insight is that topic extraction has two stages, and only the first needs AI. The model produces raw topic strings from the entry text. The backend then normalizes them:

- **Lowercase and de-pluralize**: "Meetings" → "meeting"
- **Merge near-synonyms against a curated map**: "workout" and "exercise" and "gym" → "exercise"
- **Drop noise**: single-character topics, URLs, numbers, fragments
- **Filter against a stop-topic list**: words like "thing," "stuff," "someone," "today" that appear everywhere and tell the engine nothing

This normalization layer is deterministic code, not another LLM call. It costs nothing to run, it's auditable (the map is in the repo), and it dramatically improves pattern quality by merging what the model sees as distinct topics into what the engine treats as one.

### 2. The normalization map is a product asset, not just code

The synonym map (e.g., "workout" = "exercise" = "gym") should be curated, versioned, and eventually user-editable. A user who writes about "jiu jitsu" and "BJJ" and "rolling" knows these are the same thing. The system should learn from them.

This starts simple: a YAML or JSON file in the repo maps common synonyms. Over time, the user can add their own mappings through a Settings panel: "Treat 'BJJ,' 'jiu jitsu,' and 'rolling' as the same topic." This makes the topic extraction personal — it learns the user's vocabulary.

### 3. Topic quality should be measurable and visible

If the extraction is unreliable, the pattern engine is unreliable, and the whole product thesis collapses. The system should measure its own extraction quality:

- **Topic consistency**: how often the same real-world thing gets the same topic label across entries (before normalization handles it)
- **Topic yield**: what fraction of entries produce at least one usable topic (this maps to SC-008, "90% of guided entries yield a usable topic")
- **Noise rate**: what fraction of extracted topics are single-use, never recur, and never contribute to a pattern

These metrics don't need a UI — they need to exist so the builder can tune the prompt, the normalization map, and the model selection. If topic yield is 45%, the product has a problem. If it's 85%, the product works.

### 4. The user should see which topics were found in their entry

After saving an entry, the today view or entry detail should show the extracted topics: "Topics: meeting, Q3 budget, takeaway." This serves two purposes: it proves the extraction worked, and it lets the user mentally connect later patterns to specific entries. "Oh, 'takeaway' is a pattern? Right — I've mentioned it in 4 entries this month."

If a topic is wrong or missing, the user should be able to edit it. An "edit topics" button on the entry detail lets them add missing topics and remove noise. Every edit is a training signal for the normalization layer.

### 5. Topic discovery should be a product moment

When a new topic appears in the user's writing for the first time, that's interesting. "This is the first time you've mentioned 'running.' We'll watch how it relates to your feelings over time." Similarly, when a topic reaches the pattern threshold for the first time, it should be celebrated: "'Running' has appeared in 3 entries this month — that's enough to look for patterns. We'll let you know what we find."

These small moments turn topic extraction from invisible infrastructure into a product feature. The user feels the system paying attention.

---

## The value

### It's the enabler for the simplicity thesis

The user's stated differentiator — "simplicity and good pattern matching" — depends entirely on topic extraction. If the user has to configure trackers first, the product is no simpler than Daylio. Free-text extraction is the feature that lets the user show up and write, with zero setup.

### It removes the biggest friction in the competitor workflow

Bearable's onboarding is: "Make a decision about what aspect of health you want to learn more about. Then determine the things that might be impacting your chosen metric." That's work. Daylio's is: pick activities from a grid, and if your activity isn't there, create a custom one. Also work. MPD's is: write. That's not work — that's journaling.

### It creates the data for every other differentiator

Without topic extraction, there are no patterns to audit (diff-existing-1), no topics to pair with confirmed feelings (diff-existing-2), no data for lift calculations (diff-1), no subjects for temporal precedence (diff-2), and no stories for emotional trajectory (diff-3). This is the engine that feeds all the others.

---

## How to make it stronger

1. **Deterministic normalization layer.** A post-extraction pipeline that lowercases, de-pluralizes, merges synonyms from a curated map, and drops noise. Runs in TypeScript, not the LLM. Auditable, versioned, testable.

2. **User-editable synonym map.** A Settings section where the user can add personal mappings: "Treat X and Y as the same topic." Persisted in the database, merged with the curated map at extraction time.

3. **Topic visibility in entries.** Show extracted topics on every entry in Today, Calendar, and Entry Detail. Let the user add/remove topics per entry. The list of topics becomes part of the entry's metadata the user can interact with.

4. **Extraction quality metrics.** Instrument the topic extraction pipeline with counters: yield rate, consistency rate, noise rate. Not for a user-facing dashboard — for the builder to tune the prompt and normalization map. Track these in the repo or a dev tool.

5. **Topic discovery moments.** Surface "first mention" and "threshold reached" events as small in-app notifications or highlights. Make the user aware that the system is learning their vocabulary.

---

## How to leverage it better

### In the README and marketing

"You don't configure trackers. You don't pick from icon grids. You write — we find the patterns." This is the simplest possible description of the product, and it's only possible because of free-text extraction.

### Against specific competitors

- "Daylio makes you pick activities from a grid. We find them in your writing."
- "Bearable asks you to decide what to track before you start. We watch what you write and surface what emerges."
- "Mindsera finds topics in your entries too — but it shows them in a separate panel and never connects them to feelings with counted evidence."

### In the product itself

The first entry experience should be magical: write a sentence, save, and see extracted topics appear. "Topics found: commute, coffee, deadline." The user didn't configure anything. The system just understood them. That first moment sells the whole product.

---

## What this differentiator does NOT do

- It does not guarantee perfect extraction. The 4B model will miss topics and hallucinate. The normalization layer mitigates but doesn't eliminate this. The mitigation is user-editable topics — if the system gets it wrong, the user fixes it.
- It does not extract sentiment or emotion — that's the feeling suggestion step, which is a separate pipeline. Topic extraction is purely about identifying what the entry is about.
- It does not work for non-English text unless the model supports it. `qwen3:4b` has some multilingual capability but is primarily English. This is a documented limitation.