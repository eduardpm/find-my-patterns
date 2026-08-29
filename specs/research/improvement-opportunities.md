# Improvement Opportunities — beyond the eight plans and the audit

**Date:** 2026-08-26
**Scope:** Improvements *not* already covered by the three new-differentiator plans
(`diff-1/2/3`), the five existing-differentiator plans (`diff-existing-1..5`), or the six ranked
fixes in `implementation-audit.md`. Every gap named here was verified against the code before
being written (API surface, data model, both clients). Same style as the other plans: the
business idea, the logic, the value — no implementation detail.

**Companion to:** `implementation-audit.md`, `differentiator-opportunities.md`.

---

## Tier 1 — build next (cheap, honest, makes the core thesis stronger)

### 1. Inverse patterns — "what helps", not just "what hurts"

**The gap:** every pattern the app shows is a *positive* association: topic present → feeling.
But the lift computation planned in diff-1 produces a "without" half for free — and that half is
the most actionable thing in the whole product. "On days you don't mention exercise, you're 3×
more likely to feel low" is a recommendation hiding inside a statistic.

**The logic:** for each (feeling, topic) pair, the same 2×2 table that produces lift also answers
"what happens when the topic is *absent*." If the feeling rate is much higher in entries without
the topic than with it, that is an inverse pattern: the topic appears to protect against the
feeling. Surfaced as a second card type ("associated with feeling *less* anxious"), with the same
threshold, the same evidence trail, the same withdrawal rule.

**The value:** no competitor shows the absence side as its own insight — Bearable computes it and
buries it in a table; Daylio's "influence on mood" is with-vs-without but presented as one number.
Inverse patterns turn the product from a warning system ("avoid meetings") into a discovery
system ("do more of whatever goes with feeling good"). It also gives the "keep" direction of a
pattern real substance: right now `direction = keep` merely means the paired feeling is positive.

**What it does NOT do:** it does not claim the topic *causes* the good feeling — it is presented
as association, exactly like forward patterns.

---

### 2. Confounder warnings — the statistically honest next step after lift

**The gap:** Bearable's own docs admit correlations mislead through confounding variables; no
product detects them. The audit found MPD's engine is a pure co-occurrence counter. After lift
(diff-1) the biggest remaining correctness hole is: *two topics that always travel together.*

**The logic:** whenever topic X and topic Y appear in the same entries more than ~80% of the time
(they are collinear), and there is a surfaced pattern for X → feeling, the engine notes: "X and Y
appear together in 9 of 10 entries — the association with X could really be about Y." The user
can then split the evidence: entries with X but not Y, and Y but not X. If one side is empty, the
pattern is honestly labelled "cannot separate X from Y yet."

**The value:** this is the difference between an app that *warns about* confounders (Bearable) and
one that *detects them in the user's own data*. It is the natural completion of the "patterns you
can audit" promise: after "here is the math", the next sentence is "here is what could be wrong
with the math." No free-text journal on the market does this.

**What it does NOT do:** it does not block or hide patterns — it annotates them. Withholding
evidence would violate the "withdrawal must be explainable" principle this product is built on.

---

### 3. Pattern recency — "active now" versus "used to be true"

**The gap:** the audit found the occurrence count is *lifetime* while the narrative says "in N
recent entries". A pattern from three months ago and one from this week are presented identically.

**The logic:** every pattern gets a recency window — occurrences in the last 30 days vs. ever. A
pattern is "active" if it has ≥1 (or ≥2) occurrence in the window; otherwise it is shown as
"historical" or faded, and the count on the card is the window count, not the lifetime count. The
narrative then truthfully says "recent". This is different from diff-3 (emotional trajectory,
which trends the *feeling*): this changes *which* patterns surface and how current they are.

**The value:** it fixes a factual bug in what the app tells the user, and it makes Insights honest
about "is this still true?" — which is the exact question the "prove what it claims" thesis
promises to answer. Cheap: a date filter on the existing occurrence query.

**What it does NOT do:** it does not delete old patterns or hide history — it labels age. Deletion
would lose the "pattern lifecycle" story the user can see in their own data.

---

### 4. Pattern echo at finalize — the engine speaks on the day you write

**The gap:** the pattern engine only speaks in the Insights view, which a user may open weekly.
The single most valuable moment for a pattern to appear is when the user is *in the situation that
triggers it* — i.e., while writing an entry that matches one.

**The logic:** when an entry is finalized (or when an existing entry is viewed), the backend
checks the entry's topics against active patterns and, on a match, returns a read-only note: "This
entry mentions meetings — you've felt anxious in 8 of 12 such entries (worth changing)." The note
is computed from the same deterministic evidence as the Insights card, shows the same numbers, and
links to the same supporting entries.

**The value:** it makes the engine a daily presence instead of a weekly report, and it gives the
user the pattern *at the moment of action* — while the memory is fresh and change is possible. No
competitor surfaces patterns at capture time; all of them report after the fact.

**The honest risk (design it in, don't hide it):** showing the association *before* the user
writes could bias what they write. So the echo appears on finalize, never during composition, and
it states the count without editorializing ("you've felt anxious in 8 of 12") — the user draws
the conclusion. Optionally off by default.

**What it does NOT do:** it does not predict or assert what the user will feel today — it reports
what past confirmed entries show.

---

## Tier 2 — build later (new surfaces, more breadth)

### 5. Day-of-week and time-of-day insights

**The gap:** the monthly calendar shows *which* feelings occurred on *which day* — but nobody has
aggregated the data the app already has into "when". The audit confirmed entries carry both
`entry_date` and `created_at` timestamps.

**The logic:** two cheap aggregations over confirmed-feeling entries: (a) average feeling valence
per day of week — "Tuesdays are your lowest day, Saturdays your highest"; (b) average valence per
time of day (morning/afternoon/evening from `created_at`) — "evenings are when anxiety peaks."
Each with the same evidence rule (minimum occurrences, base rate, show the supporting days).

**The value:** these are the insights a mood diary user asks for first ("when am I worst?") and
they are pure aggregation of data already collected — no new capture burden. They also feed
diff-2 (temporal precedence) with a day-level baseline to compare against.

**What it does NOT do:** it does not explain *why* Tuesday is bad — it is a pattern of time, not
of topic, and should be presented as such (and will itself be confounded by topics, which the
confounder warning can cross-check).

---

### 6. Feeling intensity — a dial on the confirmation step

**The gap:** feelings are a fixed vocabulary with no strength. "Anxious" on a bad Tuesday and
"anxious" during a panic episode are the same data point. diff-3 (emotional trajectory) needs a
continuous signal to trend, and today it only has discrete labels.

**The logic:** at the confirm/override step, the user optionally marks intensity (1–5) on the
primary feeling. Stored alongside the confirmed feeling; only user-set intensity counts (same
rule as confirmed feelings — the model's confidence is never treated as intensity). The trajectory
engine (diff-3) then trends intensity over time, and patterns can report "anxiety, typically 4/5"
instead of just "anxious".

**The value:** one extra tap that makes every downstream analysis strictly richer — trajectory,
comparison, and "how bad" on the calendar. It also quietly teaches emotional granularity, which
feeds diff-existing-2's teaching goal.

**The honest cost:** friction on the two-tap capture flow. So: optional, default off, and only on
the primary feeling — never a slider wall.

**What it does NOT do:** it does not replace the vocabulary with a 1–100 mood scale (that is
Daylio's model and it loses the *word* that makes patterns meaningful).

---

### 7. Plain-text export — the diary must come out as easily as it goes in

**The gap (verified):** the only export is a raw SQLite file copy (`npm run backup`). There is no
endpoint or command that turns the diary into human-readable text. For a product whose whole
position is "your words, your machine, your rules", the words currently can't leave in a form a
human can read.

**The logic:** one endpoint (or CLI flag on the existing backup command) that renders entries to
Markdown or JSON: date, mode, question and answer pairs, raw text, confirmed feelings, topics.
Plain text, no encryption (consistent with the existing backup posture — the user encrypts at
rest), deterministic ordering.

**The value:** it closes the lock-in argument completely — "self-hosted" means nothing if the data
is trapped in a SQLite schema. It is also the natural input to the therapy-export idea (J in the
opportunities doc) and to any future import path. Memex advertises "zero vendor lock-in" with
markdown export; MPD should not be behind a phone-app on this.

**What it does NOT do:** it does not add import — export first, import is a separate decision.

---

### 8. Import from Daylio / Bearable — the "switch to private" onboarding

**The gap:** the audience the research identified — people already tracking mood with Daylio or
Bearable who are dissatisfied with cloud data — has years of history locked in those apps, and
history is exactly what a pattern engine needs. Starting from zero is the biggest barrier to
switching.

**The logic:** Daylio and Bearable both offer CSV export of moods and activities. A one-time
import maps their mood scale and activity tags onto MPD's vocabulary (their tags become MPD
topics, their moods become feelings, mapped conservatively and marked `overridden` so nothing is
silently treated as evidence the user didn't see). Imported entries get a distinct source flag and
a clearly shown provenance.

**The value:** it converts the competitive research directly into onboarding — the same people the
landscape analysis identified as the target market arrive with their history intact, and the
pattern engine starts warm instead of cold. Nobody in the self-hosted space offers this.

**The honest caveat:** mapping quality is the whole feature. A conservative, transparent mapping
(never guessing feelings, showing every mapped row before committing) fits the product's honesty
thesis; a sloppy one would poison the evidence base with data the user never confirmed.

**What it does NOT do:** it does not accept cloud sync or API pulls — only user-exported files,
consistent with "the data comes to you, not you to the data."

---

## Checked and deliberately excluded

- **Reminders** — already shipped on Android (four daily alarms, FR-013). A web equivalent exists
  as a thin Notification-API nudge only when the tab is open; worth doing, not a differentiator.
- **Social, wearables, chat-AI, gamification** — already rejected in the opportunities doc; this
  list adds nothing to those.
- **Multi-user / shared diaries** — would violate the single-user constitution.
- **Photos/media in entries** — adds capture burden without feeding the pattern engine.
- **Topic editing UI** — real, but already covered by diff-existing-4 (synonym map, aliases).

---

## The pattern this all points to

Ideas 1–4 are one coherent move: **make every claim the app makes carry its own date, its own
numbers, and its own counter-evidence.** Lift (diff-1) says how strong; recency (3) says how
current; confounders (2) say what could be wrong; the echo (4) says it at the moment it matters;
inverse patterns (1) say what to do about it. Ideas 5–8 widen the surface: when-insights, richer
signal, and portability in and out. All of it stays inside the thesis — none of it is a cloud
feature, a social feature, or a chatbot.
