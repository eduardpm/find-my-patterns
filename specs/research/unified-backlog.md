# Unified Backlog — research + UI review, consolidated

**Date:** 2026-08-28
**What this is:** the single source for splitting into individual implementation tasks. It merges:

1. The competitive research and its strategy addendum
   (`daylio-competitive-analysis.md`, especially §9 charts and §11 monetization/recommendations),
2. the sibling plans it sequences (`master-implementation-roadmap.md` A1–A6 / I1–I8,
   `differentiator-opportunities.md`, `improvement-opportunities.md`),
3. the **hands-on UI/UX review of the Flutter app** performed on the emulator on 2026-08-28
   (screenshots archived in the session scratchpad; findings reproduced in full here).

Each item is written to stand alone as a task: ID, what, why, where it came from, effort
(S/M/L, solo dev), and dependencies. Where an item already has an owning plan doc, the task
should link to it; this file only carries enough to scope the ticket.

**Decided constraints (do not re-litigate in tasks):**

- **Scope:** the product is a diary whose added value is inferred correlations between entries,
  shown to the user, plus recommendations. Features that neither feed nor present that are out
  (goals/gamification, chat AI, wearables — see §7 below).
- **Hosting:** customers never self-host. One central backend operated by the owner (local now,
  cloud later). **The clients are the paid product**; entitlements are validated server-side.
- **Monetization rules:** never paywall writing, reading back, or export; paywall the derived
  insight layer; offer a lifetime option. (`daylio-competitive-analysis.md` §11.2)
- **Evidence rules:** only user-confirmed data is evidence; every claim carries its numbers and
  its entries; recommendations must cite the user's own entries, never generic advice.
- **North-star metric:** time-to-first-trusted-pattern — median days/entries from first use to
  the first surfaced pattern with lift. Instrument early; SC-003 ("meaningful pattern within two
  weeks") is the SLA. (`daylio-competitive-analysis.md` §11.6)

**Status observed in the running app (2026-08-28):** the rewrite already ships a working echo
(I4), withdrawal notices (A2), lift with the 2×2 panel (A3), inverse pattern cards (I1), 30-day
recency framing (I3), the When panel (I5), optional intensity (I6), the evidence trail (A1), and
topic aliases UI (part of A4). Statuses below reflect that.

---

## 1. P0 — Fix before anything else (bugs and thesis-breakers, from the UI review)

| ID | Task | Detail | Effort | Depends on |
|---|---|---|---|---|
| P0-1 | **Wire suggest→confirm feelings into the capture flow** | After save, the feelings screen says "Nothing chosen yet — pick a group" and no AI suggestion ever appears, even though topic extraction demonstrably ran (the echo referenced the new entry's topics). The user picks manually — Daylio's model. This silently drops the product's cleanest differentiator (AI proposes, human confirms; only confirmed counts). Either the client must wait/poll for the worker's suggestion (with a graceful "still reading your entry…" state and manual fallback), or the wiring is missing entirely — diagnose first. | M | worker pipeline |
| P0-2 | **Fix direction badge semantics on pattern cards** | "Walking → calm" (positive association, lift 5.0×) is badged red CONSIDER CHANGING while the adjacent inverse card ("anxious without walking") is green KEEP DOING. Same topic, contradictory advice, side by side. Define the mapping once (feeling valence × pattern kind → keep/change), test all four combinations, and make the badge color match the advice. | S | — |
| P0-3 | **Refresh Today after composing** | After saving a new entry, Today still showed the old count ("14 entries"), the old time range, and no new entry card; the day view (via Calendar) showed 15. The screen the user lands on after writing must reflect the write. | S | — |
| P0-4 | **Dismiss guard + draft autosave in the composer** | Tapping X with typed text silently destroys it — no confirmation, no draft. For a diary this is the cardinal failure. Add a discard-confirm sheet and autosave drafts (restore on next open). | S–M | — |
| P0-5 | **Fix the echo card overflow** | The echo card's title row renders Flutter's "RIGHT OVERFLOWED BY 20 PIXELS" stripe ("You have written about this before" + sparkle + close don't fit). | S | — |
| P0-6 | **Stop badging patterns with undefined lift** | Inverse cards showing "LIFT —" ("no ratio to state") still carry CONSIDER CHANGING badges — advice on a number the card admits it can't compute. Cards below the lift threshold (or with an undefined ratio) get no action badge and rank last (see UX-2). | S | P0-2 |

---

## 2. P1 — Presentation debt (the engine's honesty made it to the screen; the hierarchy didn't)

| ID | Task | Detail | Effort | Depends on |
|---|---|---|---|---|
| UX-1 | **Rebuild the entry detail screen** | Today it shows only text + two gray chips, ~70% blank, title "Entry", with a redundant pencil icon *and* full-width Edit button. It must show: date/time, mode (guided/freeform), extracted topics, feeling source (suggested/confirmed/overridden) and intensity, and "this entry supports pattern X" links (the echo data already exists). One Edit affordance. Style Delete as destructive in the confirm dialog. | M | — |
| UX-2 | **Rank and compact the Insights feed** | Cards are ~1.5 screens tall each, near-duplicates stack unranked, and every card ends with the same filler sentence ("Pay attention to how X affects your Y feeling"). Rank by strength (lift × recency), collapse weak/undefined-lift cards into a "weaker signals" group, and delete the template tip — the recommendation slot belongs to R-1's derived cards. | M | P0-6 |
| UX-3 | **When panel: finish the presentation** | Raw "-0.27 / 15" with no axis or labels; five "fewer than 3 entries" text apologies. Implement §9.1 item 5 of the Daylio doc: shared −1…+1 axis with tick labels and a zero rule, hollow markers for insufficient buckets, and a legend for what the count means. | S | — |
| UX-4 | **Edge-to-edge insets** | Content scrolls under the status bar and collides with the clock on Today and Insights (no top scrim/inset); the FAB covers the last card's text (no bottom content inset). Add proper safe-area padding and scroll-under scrim; keep the pill→"+" FAB collapse. | S | — |
| UX-5 | **One chip system** | Three visual languages exist: outlined valence chips (Today), flat gray pills (detail), emoji pills 🙂🌊 (evidence list — the only emojis in the app). Define one feeling-chip component (valence color + dot, no emoji) and use it everywhere. | S | — |
| UX-6 | **Fix the day-summary card copy** | "STRONGEST — 3 of 5" names no feeling and no unit. Make it "Strongest: Stressed 3/5". While there: verify the next-day chevron is disabled on today. | S | — |
| UX-7 | **Topics as a first-class, compact screen** | Topics is buried behind an affordance-less card in Settings, and every topic renders a full-size alias field + Add button (50 topics would be unusable). Compact list (topic · count · 12-week trend sparkline), alias-on-demand, and a visible entry point — "what the diary noticed" is insight, not configuration. Sparkline needs the series endpoint (CH-0). | M | CH-0 for trend |
| UX-8 | **Capture friction pass** | (a) Auto-focus the answer field per step; (b) add Skip to guided questions (all three are currently mandatory); (c) shorten the questions — step 3 is eight lines enumerating ten factors, work the engine should do itself (see E-2); (d) state the 4-feeling limit in the picker copy; (e) consider a flat searchable feeling picker or cross-group selection — mixed feelings currently need two sheet round-trips. | M | E-2 for (c) |
| UX-9 | **Day view + calendar polish** | Day view prints all entries at full length — truncate with expand; add swipe between days (Daylio's 146-vote request, Q2). Calendar: quiet the 25 dashed empty cells, encode entry count/intensity in the day cell (a 14-entry day looks like a 2-entry day), and prepare the year-view toggle slot (CH-2). | M | — |
| UX-10 | **Settings for customers, reminders back** | Server host/port is the first section — developer plumbing that customers (who never self-host) must not see; move it behind a debug/advanced gate. Reminders regressed to zero (the Kotlin app had four alarms): rebuild configurable reminders (Q6). | M | — |
| UX-11 | **Accessibility + theming audit** | Untested in review and needs a pass: semantics/content descriptions on the 2×2 panels, When markers and chips; dynamic type at largest size; light theme and the other two papers; contrast of orange-on-navy chips. Charts must state their numbers in contentDescription (Daylio's admitted gap — cheap differentiator). | M | — |

---

## 3. Engine correctness (before widening any surface)

| ID | Task | Detail | Effort | Depends on |
|---|---|---|---|---|
| E-1 | **Mixed-valence pairing — confirmed topic↔feeling links** | Entry-level co-occurrence poisons the 2×2 when one entry has a negative part (missed sport → disappointed) and a positive part (talked to parents → warm): two of the four counts are wrong. Fix: LLM proposes topic↔feeling *pairs* (aspect-based sentiment); the pairing is confirmed by the user only when ambiguous (mixed-valence entries only); stored with the same suggested/confirmed/overridden source field; engine counts only confirmed pairs as pair-evidence, excludes unconfirmed mixed entries from cross-valence pairs. The LLM must never silently decide. Full spec: `daylio-competitive-analysis.md` §11.7. | L | P0-1 |
| E-2 | **Passive context factors (cheap half)** | Derive weekday/weekend, month/season, time-of-day factors from data already held, and feed them into the same 2×2 engine ("anxious entries are 2.4× more likely on Sundays"). Zero capture burden; unblocks shorter guided questions (UX-8c) and week-one observations (L-2). Weather/daylight is the M-sized opt-in second half (external API, label it). Spec: §11.4 N1. | S (+M for weather) | — |
| E-3 | **Verify A4 topic normalization end-to-end** | Alias UI exists, but the review couldn't confirm merged counting ("Age of empires 2" as a topic suggests one-shot extraction survives). Verify canonical names + aliases actually merge in pattern counts; this gates every number printed. Owner: `diff-existing-4`. | M | — |
| E-4 | **Confounder warnings (I2)** | Not observed in the UI; if unshipped, implement per `improvement-opportunities.md` §2: collinear topics (>80% co-occurrence) annotate patterns with "could really be about Y" and a split view. | M | A3 ✓ |

---

## 4. Insight surface growth (charts + first-30-days ladder)

Chart specs live in `daylio-competitive-analysis.md` §9.1 (stack decision: hand-drawn Compose/Flutter canvas + inline SVG on web; no chart library).

| ID | Task | Detail | Effort | Depends on |
|---|---|---|---|---|
| CH-0 | **Series endpoint + day score** | `GET /insights/series?from=&to=&granularity=` plus the day score (mean valence of confirmed feelings, −1…+1, with per-day entry count; intensity never silently folded in). Prerequisite for CH-1/2, UX-7, L-2, Year in Review. | M | — |
| CH-1 | **Mood-over-time line** | One point per day, zero line, opacity by entry count, gaps as gaps; 30/90/365 switcher. Top of Insights. | M | CH-0 |
| CH-2 | **Year in Pixels grid** | Tappable year grid colored by day score; reachable from Calendar via year/month toggle; exportable image later (feeds N-2). | S–M | CH-0 |
| CH-3 | **Feeling mix bar** | Stacked horizontal bar over the existing per-feeling totals on Calendar. Zero new data. | S | — |
| CH-4 | **Pattern strength bars on cards** | Two bars (present vs absent rate) with lift between them, replacing prose-only numbers. | S | — |
| CH-5 | **Time-of-day heat strip** | Hourly/3-bucket strip from `created_at`; extends When panel; answers Daylio's 201-vote "hourly view" request. | S–M | UX-3 |
| L-1 | **Import + backdating at onboarding** | Daylio/Bearable CSV import (I8, mapping rules in `improvement-opportunities.md` §8) plus backdate-recent-days prompts at first use. Biggest lever on time-to-first-pattern. | M | I7 export first |
| L-2 | **Insight progress surface** | After saving, show the counting in flight: "topics tracked: 7 · closest to a pattern: *work* — 2 of 3 confirmed occurrences." Honest (counts, not conclusions), shown post-save like the echo. Converts the cold-start silence into anticipation. New — no owning doc; spec in §11.6 rung 2. | S–M | — |
| L-3 | **First-pattern notification** | When the first pattern crosses the threshold, notify — don't leave the aha moment in an unvisited tab. Arrives with its receipts (evidence trail). | S | reminders infra (UX-10) |
| L-4 | **Guided-question topic yield measurement** | Instrument SC-008 (usable topic per guided entry); tune or cut questions that don't extract. Owner: `diff-existing-5`. | S | — |
| N-2 | **Year in Review** | Annual generated report: pixels grid, top patterns, biggest trajectory improvement, vocabulary growth; exportable image. The December retention/upsell moment. | S–M | CH-0, CH-2 |
| N-3 | **Writing streak** | Consecutive days with ≥1 entry, shown quietly on Today. No levels, no achievements. | S | — |

---

## 5. Recommendations (the product definition's missing half)

Spec: `daylio-competitive-analysis.md` §11.3. Hard rule R-0 applies to all: **every
recommendation cites the user's own entries; no generic advice.**

| ID | Task | Detail | Effort | Depends on |
|---|---|---|---|---|
| R-1 | **"Try more of this" cards** | Inverse patterns reframed as first-class recommendations with the same counts and evidence trail, phrased as action. Replaces UX-2's deleted filler tips. | S–M | I1 ✓, P0-2 |
| R-2 | **Weekly digest** | One pattern, one recommendation, one experiment result per week, delivered as a local notification; deterministic wording. The paid tier's retention engine (Rosebud model). | M | R-1, UX-10 reminders |
| R-3 | **N-of-1 experiments** | "Test this — one week, we compare the two periods with the same 2×2 arithmetic." Flagship of the paid tier; commercially validated by Bearable (ships and paywalls experiments). Spec: `differentiator-opportunities.md` §D. | L | A3 ✓, I3 ✓, R-1 |

---

## 6. Monetization enablers (sequence before any paid feature ships)

Spec: `daylio-competitive-analysis.md` §11.1–11.2.

| ID | Task | Detail | Effort | Depends on |
|---|---|---|---|---|
| M-1 | **Multi-tenant backend** | Accounts, per-user data isolation, per-user pattern computation. Constitution-level change; do it inside the current rewrite, not as a retrofit. Precedes every other M item. | L | — |
| M-2 | **Server-side entitlements** | Purchases happen in the client (Play Billing / App Store); the backend validates receipts and gates premium computation by account. A client-only paywall over an open API is decorative. | M | M-1 |
| M-3 | **Free/paid boundary implementation** | Free: diary, feelings, calendar, export, current-window (30-day) patterns. Paid: full-history patterns, trajectories, lagged patterns, confounder splits, experiments, digest, therapy report, Year in Review. Boundary by feature tier, never by platform (free web vs paid Android would self-compete). | M | M-2 |
| M-4 | **Lifetime purchase option** | The category's loudest complaint is subscription-only (Daylio's 351-vote top review). Price must cover indefinite inference cost or cap expensive operations. | S | M-3 |
| M-5 | **Privacy claims rewrite** | "Inference on hardware you own" becomes false for customers. Replacement claim: "no third-party AI vendor ever sees your diary — inference on our servers, not OpenAI's." Update README + `diff-existing-3` + app copy. | S | M-1 |
| M-6 | **Plain-text export (I7)** | Markdown/JSON export, free forever — the trust story that justifies the paid tier. Also the contract for L-1 import. | S | — |

---

## 7. Deliberately excluded (scope guard — reject in triage, don't re-argue)

Goals/levels/achievements · 2000+ icon libraries · Low/Med/High confidence labels in place of
numbers · photos in entries (until core is finished) · five-point mood scales · chat-with-your-
journal AI · social/sharing · wearable/biomarker integrations · habit tracking · gamification
beyond N-3's single quiet streak. Rationale: `daylio-competitive-analysis.md` §9.4,
`differentiator-opportunities.md` §3.

---

## 8. Suggested build order

1. **P0-1 … P0-6** — the app must not contradict its own thesis. (P0-1 first; it may be a
   worker-timing diagnosis rather than new UI.)
2. **UX-1, UX-2, UX-4, UX-5, UX-6** — the two thinnest screens are the two that define the
   product (entry detail, Insights ranking); insets and chip unification ride along.
3. **E-3, E-1, E-2(S)** — evidence honesty before widening: verify topic merging, fix the
   mixed-valence pairing, ship the cheap passive factors.
4. **CH-0 … CH-4, UX-3, UX-7** — the free tier must look like a product before anything is
   worth paying for.
5. **L-1 … L-4, N-3** — attack time-to-first-trusted-pattern.
6. **M-1 … M-6 in order, with R-1 → R-2 → R-3 landing as the paid tier's content** — R-3
   (experiments) + full-history entitlements are the launch features of paid.
7. **CH-5, N-2, UX-9, UX-10, UX-11** — polish and the December moment.

Items shipped already (A1 ✓ A2 ✓ A3 ✓ I1 ✓ I3 ✓ I4 ✓ I5 ✓ I6 ✓, alias UI) need no tasks beyond
the fixes listed above. B1 (lagged patterns), B3 (device lock), Q1 (search), Q3 (day boundary),
Q5 (On This Day) remain valid backlog from the owning docs and slot in after step 5 by taste —
Q1 and Q3 get cheaper the earlier they land.
