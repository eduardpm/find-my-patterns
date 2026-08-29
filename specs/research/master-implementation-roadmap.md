# Master Implementation Roadmap

**Date:** 2026-08-26
**What this is:** the single build sequence for everything outstanding after the research phase —
the **6 audit fixes** from `implementation-audit.md` §9 plus the **8 improvement ideas** from
`improvement-opportunities.md` — sequenced against the **8 existing differentiator plans**
(`diff-1/2/3`, `diff-existing-1..5`). Business level: what, why, in what order, what it unlocks.
No implementation detail — that lives in the individual plan docs.

**How to read the IDs:** `A1–A6` are audit fixes; `I1–I8` are improvement ideas. Where a row
already has a dedicated plan, that plan is the owner and this roadmap only sequences it.

---

## 1. The full backlog

| ID | Item | Source | Effort | Depends on | Plan owner |
|---|---|---|---|---|---|
| A1 | Evidence trail — tap a pattern → its supporting entries | Audit fix 1 | S | — | `diff-existing-1` |
| A2 | Visible withdrawals — "this pattern was dropped, and why" | Audit fix 2 | S | — | `diff-existing-1` |
| A3 | Base-rate / statistical lift | Audit fix 3 | M | **A4** (topic quality gates every number) | `diff-1-base-rate-patterns.md` |
| A4 | LLM topic normalization — canonical names + aliases | Audit fix 4 | M | — | `diff-existing-4` |
| A5 | Fix the "recent entries" wording | Audit fix 5 | XS | — | folded into **I3** |
| A6 | Time-slot guided questions (morning/afternoon/evening) | Audit fix 6 | M | — | `diff-2-temporal-precedence.md` (prerequisite) |
| I1 | Inverse patterns — the "without" side as its own card | Improvement 1 | M | **A3** (needs the 2×2 table) | new |
| I2 | Confounder warnings — collinear topic pairs | Improvement 2 | M | **A3** | new |
| I3 | Pattern recency — active vs. historical, window count | Improvement 3 | S | — | new |
| I4 | Pattern echo at finalize — engine speaks on write | Improvement 4 | M | **I3** (needs active patterns) | new |
| I5 | Day-of-week and time-of-day insights | Improvement 5 | S | **A3** (base rates keep "when" honest) | new |
| I6 | Feeling intensity (1–5, optional, on confirm) | Improvement 6 | S | — | feeds `diff-3-emotional-trajectory.md` |
| I7 | Plain-text export (Markdown/JSON) | Improvement 7 | S | — | new |
| I8 | Import from Daylio/Bearable CSV | Improvement 8 | M | **I7** (export shapes the import contract) | new |

**Not in this program:** the three remaining existing plans that are positioning/UX work rather
than backlog items — `diff-existing-2` (confirmed-feelings teaching), `diff-existing-3` (privacy
framing), `diff-existing-5` (question effectiveness). They run in parallel, any time, and their
value is independent of the phases below.

---

## 2. Sequencing logic — three rules

1. **Honesty before breadth.** A claim must be true before it is shown in more places. Topic
   quality (**A4**) gates every number the engine prints; lift (**A3**) gates inverse patterns and
   confounder warnings. Build the foundation before the features that sit on it.
2. **Presentation before engine.** The evidence trail (**A1**), withdrawals (**A2**) and recency
   (**I3**) make existing claims checkable with zero engine risk — they are the cheapest wins and
   they de-risk the later engine work by forcing the numbers to be legible first.
3. **Dependencies first.** Lift before inverse/confounders. Recency before the echo. Intensity
   before trajectory. Time-slot questions before temporal precedence. Export before import.

---

## 3. Phase 1 — "Make the evidence visible" *(S, zero engine risk)*

**Items:** A1 (evidence trail), A2 (visible withdrawals), I3 (pattern recency), A5 (folded into I3).

**What the user gets:** every pattern card becomes tappable — behind it, the actual entries, with
their dates, texts and confirmed feelings. Patterns carry a window count ("5 in the last 30 days")
instead of a lifetime count, and are labelled **active** or **historical**. When a pattern is
withdrawn, a notice explains it ("2 supporting entries remain — below the threshold of 3"). The
narrative stops saying "recent" when it means "ever".

**Why first:** the audit found the evidence trail already exists in the database but no client
shows it. This phase is almost entirely UI over data that is already correct. It converts the
product's headline claim — *patterns you can audit* — from an internal property into a visible
feature, with nothing that can break the engine.

**Done when:** a user can answer "show me why" on every pattern, and can see when and why a
pattern disappeared.

---

## 4. Phase 2 — "Make the evidence honest" *(M, engine + tests)*

**Items, in order:** A4 (topic normalization) → A3 (lift) → I1 (inverse patterns) → I2
(confounder warnings).

**A4 first, deliberately:** the audit found LLM-proposed topics are one-shot and unmerged
("project review" / "project meeting" / "review" never cross the threshold). Everything after this
phase counts topics, so topic identity must be stable *before* any new number is printed. This is
the one item that must not be skipped or deferred.

**Then A3:** every pattern states its lift — "anxious in 8 of 12 entries mentioning meetings (67%)
vs. 3 of 28 without (11%) — 6× more likely". The base-rate problem the research flagged as its
biggest correctness gap is closed, and the ≥3 rule stops surfacing noise.

**Then I1:** the "without" half of that same table becomes its own card — "on days without
exercise, low mood is 3× more likely" — giving the product a positive, do-more-of-this surface
for the first time.

**Then I2:** when two topics travel together (>80% co-occurrence), any pattern on one carries the
note "could really be about Y", with a split view of the evidence. This is the step past every
competitor — they warn that confounders exist; this app detects them in the user's own data.

**Done when:** every pattern states strength (lift), scope (recency), possible confound, and the
inverse side. The "prove what it claims" thesis is no longer aspirational.

---

## 5. Phase 3 — "Make the engine daily" *(M)*

**Items:** I4 (pattern echo at finalize), I6 (feeling intensity).

**I4:** when an entry is finalized and matches an active pattern, the app shows the historical
association — "this entry mentions meetings; you've felt anxious in 8 of 12 such entries". Shown
*after* writing, never during (no bias), with the same numbers as the Insights card. The engine
stops being a weekly report and becomes a presence on the day the pattern is lived.

**I6:** an optional 1–5 intensity dial on the primary feeling at confirmation. Only user-set
intensity counts (model confidence is never treated as evidence). This gives `diff-3` (emotional
trajectory) the continuous signal it needs to trend "anxiety, typically 4/5" instead of just
"anxious", and makes the calendar say *how bad*, not just *which*.

**Done when:** patterns appear at the moment of writing, and trajectory has a continuous signal to
trend.

---

## 6. Phase 4 — "Widen the insight surface" *(S–M)*

**Items:** I5 (day-of-week / time-of-day), A6 (time-slot questions).

**I5:** two aggregations over data already collected — average valence by day of week ("Tuesdays
are your lowest day") and by time of day ("evenings are when anxiety peaks") — each with the same
base-rate and evidence rules as patterns. This answers the question mood-tracker users ask first
("when am I worst?") with zero new capture burden.

**A6:** seed morning/afternoon/evening variants of the guided questions. This is the audit's fix 6
and it is what makes `diff-2` (temporal precedence) actually computable — the research's premise
("the guided flow already segments the day") is currently false, and this phase makes it true. It
also feeds I5's time-of-day half with richer signal than raw timestamps.

**Done when:** "when" insights exist, and temporal precedence has the question slots it needs.

---

## 7. Phase 5 — "Portability" *(S–M)*

**Items:** I7 (plain-text export), I8 (import from Daylio/Bearable).

**I7:** entries leave as Markdown/JSON — date, mode, question/answer pairs, confirmed feelings,
topics. Verified as the only real gap in the "your words, your rules" promise (the sole export
today is a raw SQLite copy). Export shapes the contract that import then implements.

**I8:** Daylio/Bearable CSV import maps their moods and activity tags onto MPD's vocabulary,
conservatively and visibly — imported feelings are marked `overridden` (never silently treated as
evidence the user didn't see), provenance is shown, every mapped row is reviewable before commit.
This converts the competitive research into onboarding: the exact audience the landscape analysis
identified arrives with their history intact and a warm pattern engine.

**Done when:** the diary goes in and out as plain text, and a migration path exists from the two
nearest competitors.

---

## 8. Effort and risk summary *(relative, solo dev)*

| Phase | Items | Size | Main risk |
|---|---|---|---|
| 1 — Evidence visible | A1, A2, I3 | S | None — UI over existing data |
| 2 — Evidence honest | A4, A3, I1, I2 | M | Topic normalization quality (A4) is the whole ballgame; lift changes which patterns surface (a visible behaviour change to explain) |
| 3 — Engine daily | I4, I6 | M | Echo must never read as prediction; intensity must stay optional (friction on capture) |
| 4 — Insight surface | I5, A6 | S–M | New questions change entry composition → derived `raw_text` changes; keep old keys' prompts stable |
| 5 — Portability | I7, I8 | S–M | Import mapping quality — a sloppy mapping poisons the evidence base |

**Sequencing risk note:** A3 (lift) will legitimately remove or downgrade patterns that were
surfaced under the raw ≥3 rule. Do Phase 1 first so the user can *see* the evidence behind that
change — withdrawal notices and the evidence trail are what make a downgraded pattern
understandable instead of a regression.

---

## 9. The payoff

Five phases, five sentences: the evidence becomes visible (1), then true (2), then present daily
(3), then broader (4), then portable (5). Everything stays inside the thesis — counted evidence,
confirmed feelings, local computation. Nothing in this program is a cloud feature, a social
feature, or a chatbot. When it ships, the product statement is simply: **every pattern you are
shown carries its own numbers, its own date, its own counter-evidence, and its own way out of the
app.**
