# Feature Specification: Mood Pattern Diary Web App

**Feature Branch**: `003-web-client`

**Created**: 2026-07-28

**Status**: Draft

**Input**: User description: "besides an Android app and the backend, I want a webapp as well. should have the same functionality"

> ✅ **Constitution conflict resolved (2026-07-28).** Constitution v1.0.0 restricted v1 clients to
> Android and excluded a web client "unless a future amendment changes this." That amendment was
> made: **v1.1.0** now names an Android app and a web app as the supported client platforms, and
> adds **Principle VII (One Backend, Thin Clients)**, which this spec must be planned against. See
> Assumptions for what that principle constrains here.

## Clarifications

### Session 2026-07-28

- Q: FR-011 requires 100% conflict protection (SC-008) but FR-018 forbids changing the Android app — conflict detection needs the editing client to send the version it was based on. Which scope? → A: This feature includes updating the Android app to participate in conflict detection; both clients protected, API contract gains a version field, FR-018 reworded to permit additive changes.
- Q: When a conflict is detected, what happens to the text the user just wrote? → A: Reject and preserve — the user's text stays on screen next to the current server version, and they choose whether to retry, discard, or copy across. Writing is never discarded automatically.
- Q: What may the web client leave behind on the computer (URLs, history, local storage)? → A: No diary content in URLs or in persistent browser storage. Addresses may identify which view is open, but never carry entry text or feelings; nothing containing diary content survives the tab closing.
- Q: What happens to unsaved writing if the tab is closed mid-entry, given FR-025 forbids local draft storage? → A: Warn before leaving — the browser asks the user to confirm when there is unsaved text. Nothing is stored locally; the loss becomes a deliberate choice rather than a silent one.
- Q: What accessibility bar applies to the web client beyond keyboard operability? → A: A pragmatic baseline — visible focus indicators, readable text contrast, and clearly labelled controls — verifiable by inspection. No formal conformance standard is invoked.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Write and manage diary entries from a computer (Priority: P1)

The user is at their computer — where they already spend most of the day — and wants to log an
entry without picking up their phone. They open the diary in a browser, write what just happened,
confirm or override the feeling the app suggests, and save. They can do this several times a day,
and can go back and edit or delete anything they've written.

**Why this priority**: This is the whole point of the request. A real keyboard and a large screen
make writing materially faster and more pleasant than a phone, which directly serves the app's
load-bearing constraint — entries must keep getting written, or pattern detection has nothing to
work with. Every other web capability is a view over data this story produces.

**Independent Test**: Can be fully tested by opening the web app, writing an entry, confirming a
feeling, and saving — then writing a second entry the same day and confirming both are kept
separately under today's date, and that one can be edited and the other deleted.

**Acceptance Scenarios**:

1. **Given** the web app is open, **When** the user writes free text and saves, **Then** the entry is stored with a timestamp and immediately appears in today's entry list.
2. **Given** the user already saved one entry today, **When** they create another later the same day, **Then** both remain separate and both appear under today's date, in order.
3. **Given** the user is finishing an entry, **When** they save it, **Then** the app suggests a feeling inferred from the text and requires the user to confirm or override it before the entry is considered complete.
4. **Given** a previously saved entry, **When** the user opens it, **Then** they can edit its text/feeling or delete it entirely.
5. **Given** the user is typing an entry, **When** they use the keyboard alone, **Then** they can complete the whole flow — write, pick a feeling, save — without reaching for the mouse.

---

### User Story 2 - One diary, whichever device I'm on (Priority: P2)

The user writes some entries on their phone during the day and others at their computer, and
expects a single diary — not two. Anything written on one shows up on the other, edits and
deletions propagate, and the insights and monthly totals count every entry exactly once regardless
of where it was written.

**Why this priority**: This is the biggest new risk the web app introduces, and the one that can
actively damage the product. A split or double-counted diary would corrupt exactly the thing the
app exists for — accurate pattern detection — so it ranks above the remaining feature-parity work.
It must hold true before adding a second client is a net gain rather than a liability.

**Independent Test**: Create an entry on the phone, open the web app, and confirm it appears with
the same text, timestamp and feeling; then edit it on the web, return to the phone, and confirm
the edit is reflected there — and that insights/monthly counts changed by one entry, not two.

**Acceptance Scenarios**:

1. **Given** an entry was created on the Android app, **When** the user opens the web app, **Then** that entry appears with identical text, timestamp, and feeling.
2. **Given** an entry was created on the web app, **When** the user opens the Android app, **Then** that entry appears identically there.
3. **Given** an entry is edited or deleted on one client, **When** the user views it on the other, **Then** the change is reflected and no stale copy remains.
4. **Given** entries created from both clients, **When** the user views insights or the monthly summary from either client, **Then** each entry is counted exactly once and both clients show the same totals.
5. **Given** the same entry is open on both clients, **When** it is changed on one and then saved on the other, **Then** the user is told their view was out of date rather than silently overwriting the newer change.
6. **Given** a change was just rejected as out of date, **When** the user looks at the screen, **Then** the text they wrote is still there next to the current stored version, and they can retry, discard, or carry their text across — nothing they typed is lost.

---

### User Story 3 - Be guided by structured questions in the browser (Priority: P3)

Rather than facing a blank page, the user is walked through the same short set of guiding prompts
the phone offers — some general, some situational — so they always know what to write. They can
also skip the prompts and write freely if they prefer.

**Why this priority**: It carries the phone's answer to blank-page hesitation over to the web, and
produces the structured signal the pattern engine depends on. It extends Story 1 rather than
standing alone, and the web app is already usable without it.

**Independent Test**: Start a new entry in the browser and confirm a short sequence of guiding
questions appears instead of only an empty text box; answer them, save, and confirm the entry
carries both the composed text and the structured answers — then repeat, choosing to skip the
prompts, and confirm a free-form entry saves fine.

**Acceptance Scenarios**:

1. **Given** the user starts a new entry in the browser, **When** the composer opens, **Then** they see the same short sequence of guiding questions the Android app offers — a mix of general and situational — instead of only a blank field.
2. **Given** the guiding questions, **When** the user answers them, **Then** their answers become the entry's content without requiring them to compose free-form text from scratch.
3. **Given** a user who prefers to write freely, **When** they are in the entry flow, **Then** they can bypass the guided questions and write an unstructured entry instead.
4. **Given** a guided entry created on the web, **When** it is viewed on the Android app or fed to pattern detection, **Then** its structured answers are available and usable exactly as if it had been created on the phone.

---

### User Story 4 - Review patterns and suggestions on a big screen (Priority: P4)

The user opens the Insights view in the browser to read the correlations the app has found between
recurring topics in their life and the feelings attached to them, along with the suggestion for
each — either to change the habit or to keep it up.

**Why this priority**: Insights are the app's central payoff and benefit from a larger screen, but
this is a read-only view over data Stories 1–3 produce, and the same information is already
reachable on the phone.

**Independent Test**: Seed the diary with entries that repeatedly pair a recurring topic with the
same feeling across several days, open Insights in the browser, and confirm the correlation and
its suggestion appear — matching what the Android app shows.

**Acceptance Scenarios**:

1. **Given** a recurring topic has been paired with the same feeling across multiple entries, **When** the user opens Insights in the browser, **Then** the pattern is displayed in plain language.
2. **Given** a pattern linked to a negative feeling, **When** the user views it, **Then** a concrete suggestion for change is shown; **and** for a positive feeling, a suggestion to keep the habit.
3. **Given** too few entries exist to support a pattern, **When** the user opens Insights, **Then** the app explains more entries are needed rather than showing an unsupported pattern.
4. **Given** the same underlying data, **When** the user compares Insights on web and on the phone, **Then** both show the same patterns with the same occurrence counts.

---

### User Story 5 - See a month of feelings in a calendar on the web (Priority: P5)

The user opens a monthly calendar view in the browser showing which feelings were logged on each
day, plus per-feeling totals for the month and the average number of entries per day.

**Why this priority**: A retrospective reporting layer over data already captured, and the last
piece of parity with the phone. Genuinely nicer on a wide screen, but nothing else depends on it.

**Independent Test**: Seed a month of entries with varied feelings, open the monthly view in the
browser, and confirm each day cell reflects the feelings logged and that month-level totals and
the daily average are shown — matching the Android app for the same month.

**Acceptance Scenarios**:

1. **Given** entries exist across a month, **When** the user opens the monthly view, **Then** each day cell visually indicates the feeling(s) logged that day.
2. **Given** a month of data, **When** the user views the summary, **Then** a count per feeling category and the average number of entries per day are shown.
3. **Given** a day with more than one feeling logged, **When** it is shown on the calendar, **Then** the day reflects that mix rather than only a single feeling.
4. **Given** a month where some days have no entries, **When** the calendar renders, **Then** empty days are visually distinguishable from days with entries.

---

### Edge Cases

- What happens when the browser cannot reach the backend (machine asleep, user away from the home network, backend not running)? The web app must say so clearly rather than appearing to save an entry that was lost.
- What happens when the user has the web app open and an entry is created or deleted on the phone? Per FR-019 the page shows stale data until refreshed — so what happens if they then act on that stale view (edit an entry the phone already deleted, or delete one the phone already changed)? See FR-011/FR-021.
- How does the user know a view might be stale — is there any indication of when it was last loaded, or does it look identical to fresh data?
- What happens when the same entry is edited on both clients at once? (Covered by US2 AC5/AC6 and FR-023 — the second save is rejected, and the user's text is preserved on screen for them to resolve.)
- What happens when the computer's clock or timezone differs from the phone's — which day does an entry written near midnight belong to, and do both clients agree?
- What happens if the user closes the browser tab mid-entry? (Addressed by FR-026: the user is warned and must confirm. Note the residual risk this does *not* cover — a browser or machine crash gives no chance to warn, and FR-025 rules out recovering the draft, so that writing is genuinely lost.)
- What happens when a very long entry is written on a real keyboard — is there any length beyond which the app misbehaves?
- How does the web app behave in a narrow browser window or on a mobile browser — is it usable, or is it desktop-only?
- What could someone else using the same computer see — browser history, the back button, a left-open tab? (Addressed by FR-024/FR-025: no diary content in addresses or persistent browser storage. A left-open, unlocked tab remains visible to anyone at the machine — that is accepted, per the lock-screen assumption below.)
- What happens when the browser is left open and unattended? (See Assumptions on access control.)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide a web-browser client offering the same diary capabilities as the Android app: entry creation, guided questions, feeling confirmation, editing/deleting, insights, and the monthly calendar view.
- **FR-002**: The web client MUST allow the user to create a free-text diary entry at any time, and multiple entries on the same calendar day, each with its own timestamp, without overwriting or merging them.
- **FR-003**: The web entry-creation flow MUST be completable in a short number of steps, prioritizing writing speed and a pleasant experience over additional required fields.
- **FR-004**: The web client MUST guide entry creation with the same structured set of questions/prompts the Android app uses, and MUST let the user bypass them to write free-form.
- **FR-005**: The web client MUST capture a feeling for each entry using the same hybrid flow as the Android app: a suggested feeling that the user confirms or overrides before the entry is saved.
- **FR-006**: The web client MUST let the user edit or delete a previously saved entry.
- **FR-007**: The web client MUST present detected patterns in a dedicated Insights view, in plain language, each with its actionable suggestion.
- **FR-008**: The web client MUST provide a monthly, calendar-style view showing which feeling(s) were logged on each day, per-feeling counts for the month, and the average number of entries per day.
- **FR-009**: The web and Android clients MUST read and write the same single body of diary data, such that an entry created, edited, or deleted on one is reflected on the other.
- **FR-010**: Insights and monthly totals MUST count each entry exactly once regardless of which client created it, and MUST be identical when viewed from either client for the same data.
- **FR-011**: When two clients attempt to modify the same entry concurrently, the system MUST NOT silently discard the earlier change; the user making the later, stale-based change MUST be informed their view was out of date. **Every client MUST participate** — a client that edits or deletes an entry MUST identify which version of that entry it was working from, and the backend MUST reject a change based on a version that is no longer current.
- **FR-012**: All clients MUST agree on which calendar day a given entry belongs to, so that day grouping, the monthly calendar, and per-day averages are consistent across clients.
- **FR-013**: When the backend is unreachable, the web client MUST clearly tell the user the operation failed rather than silently losing the entry or appearing to succeed.
- **FR-014**: The web client MUST be fully operable from the keyboard for the core entry-creation flow, without requiring a pointing device.
- **FR-015**: The web client MUST meet the same visual and interaction bar as the Android app — modern, sleek, and pleasant to write in — and MUST remain usable when the browser window is narrow (including on a mobile browser).
- **FR-016**: The web client MUST be usable only while the user's device can reach the self-hosted backend directly (same home network or a VPN to it); it MUST NOT be exposed to the public internet, and offline entry creation is out of scope.
- **FR-017**: All diary data MUST continue to be stored only on the backend the user runs themselves; the web client MUST NOT introduce any additional third-party storage of diary content.
- **FR-018**: Adding the web client MUST NOT degrade existing Android app behavior; all previously specified Android functionality MUST continue to work as before. Additive changes to the Android client that are required to satisfy other requirements in this spec (specifically FR-011/FR-022) are permitted, provided no existing Android capability is removed or made slower to use.
- **FR-019**: The web client MUST give the user an explicit way to refresh the view they are on, so data changed elsewhere can be pulled in without restarting the app or losing their place. Live/push updates are out of scope for v1: the web client MUST NOT maintain a persistent connection to the backend for the purpose of receiving changes it did not initiate.
- **FR-020**: The Android app remains the sole reminder surface. The web client MUST NOT schedule, request permission for, or deliver its own daily check-in reminders, so the user is never reminded twice for the same check-in.
- **FR-021**: Because the web client's view can be stale between refreshes (FR-019), it MUST NOT present stale data as current in a way that causes a destructive action — specifically, deleting or editing an entry from a stale view MUST be subject to the concurrent-modification protection in FR-011.
- **FR-022**: The Android client MUST be updated to participate in the concurrent-modification protection of FR-011 — identifying the version it is editing and surfacing the same rejected-change outcome defined in FR-023 — so that protection holds regardless of which client makes the later change.
- **FR-023**: When a change is rejected as out of date, the client MUST NOT discard what the user wrote. It MUST keep the user's unsaved text visible alongside the current stored version of that entry, and MUST let the user choose what happens next — retry their change against the current version, discard their change, or carry their text across. The system MUST NOT automatically merge the two versions or silently pick a winner.
- **FR-024**: The web client MUST NOT place diary content in addresses the browser records. An address MAY identify which view is open (today's list, a given month, a given entry's identifier), but MUST NOT carry entry text, guided answers, or feelings.
- **FR-025**: The web client MUST NOT write diary content to persistent browser storage. Nothing containing entry text, guided answers, or feelings may survive the tab being closed; diary content held while the app is open is working state only, discarded with the tab.
- **FR-026**: When an entry has unsaved text, the web client MUST prompt the user to confirm before the tab is closed or navigated away from, so unsaved writing is never lost without the user choosing to lose it. No prompt may appear when there is nothing unsaved. Because FR-025 forbids local draft storage, this warning — not recovery — is the protection for in-progress writing.
- **FR-027**: The web client MUST meet a baseline of accessible interaction, verifiable by inspection rather than by a formal conformance standard: every interactive element shows a visible focus indicator when reached by keyboard, text is legible against its background, and every control states what it does rather than relying on an unlabelled icon alone. This is what makes FR-014's keyboard operability usable in practice rather than merely possible.

### Key Entities *(include if feature involves data)*

This feature introduces **no new persistent diary entities**. It adds a second client over the
existing data — Diary Entry, Guiding Question (and Answer), Feeling, Topic, Pattern/Insight, and
the derived Monthly Summary — all of which keep their current meaning and remain owned by the
self-hosted backend.

- **Entry revision marker** *(new, non-diary metadata)*: a per-entry version indicator that lets the backend tell that a client's copy of an entry is out of date, so FR-011's concurrent-edit protection can be enforced. Served to every client when an entry is read, and sent back by every client when editing or deleting it (FR-022). It carries no diary content.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can go from opening the web app to saving their first diary entry in under 30 seconds.
- **SC-002**: A user can save a second same-day entry in under 15 seconds from starting a new entry.
- **SC-003**: A user can complete the entire entry flow — write, choose feeling, save — using only the keyboard, with no pointing-device input.
- **SC-004**: An entry created on one client is visible on the other within one refresh of the relevant view, 100% of the time.
- **SC-005**: For any given month and any given set of entries, the per-feeling counts, daily average, and detected patterns shown on web and on Android are identical, 100% of the time.
- **SC-006**: A user can see their full month's feeling breakdown (per-feeling counts and daily average) on a single screen without additional navigation.
- **SC-007**: When the backend is unreachable, the user is told within 10 seconds of attempting to save, and no entry is ever reported as saved when it was not.
- **SC-008**: Concurrent edits to the same entry from two clients never result in a lost change — in 100% of such attempts, on either client, the user is informed rather than overwritten, and the text they wrote is still recoverable from the screen rather than discarded.
- **SC-009**: Users rate the web writing experience as modern and pleasant in at least 90% of feedback collected during testing, matching the bar set for the Android app.
- **SC-010**: The web app is usable — every screen readable and every control reachable — at browser widths from a narrow phone screen up to a wide desktop monitor.
- **SC-011**: The user receives exactly four check-in reminders per day, from the phone only, whether or not the web app is open or has ever been used.
- **SC-012**: After a session of writing and browsing entries, no diary text, guided answer, or feeling can be found in the browser's history or in any storage that survives closing the tab.
- **SC-013**: Unsaved writing is never lost without the user confirming it: in 100% of attempts to close or navigate away with unsaved text, the user is asked first.
- **SC-014**: Navigating the entire app by keyboard, the user can see at every step which element is focused — no interactive element is reachable without a visible focus indicator.

## Assumptions

- **The constitution has been amended to permit this feature** (v1.0.0 → v1.1.0, 2026-07-28). Product Constraints now name an Android app and a web app as the supported clients, and require every client to be LAN-only and never exposed to the public internet — which FR-016 already states. No principle is in conflict: the app stays single-user and self-hosted (Principles II and IV), factual claims stay deterministic in the backend (Principle III), and the writing-speed bar (Principle VI) is carried into FR-003/SC-001/SC-002 rather than relaxed.
- **Principle VII (One Backend, Thin Clients) governs this feature directly.** The web client MUST NOT hardcode or recompute the feeling set, the guiding-question library, the minimum-occurrence threshold, topic extraction, pattern detection, or any count/average — all of it is served by the backend. This is what FR-009, FR-010 and SC-005 exist to enforce. Purely presentational choices (icons, ordering, layout, animation) remain the client's own. Note the known pre-existing deviation flagged in the constitution's Sync Impact Report: the Android app currently hardcodes the feeling set rather than fetching it, which should be reconciled so both clients source it the same way.
- The web client is an **additional peer client, not a replacement** — the Android app remains fully supported, and receives only the additive change needed for shared conflict protection (FR-018/FR-022). This feature therefore spans three components, not one: the web client, a backend API contract addition, and a small Android client update.
- The web client is a **client of the existing self-hosted backend**, reusing the same diary data and the same behavior for feeling suggestion, topic extraction, and pattern detection. It does not get its own storage, its own pattern logic, or its own copy of the data.
- **No in-app authentication**, consistent with the Android app's existing decision: access control relies on the computer's own lock screen and the privacy of the home network. A laptop browser on the home LAN is treated as an equivalent threat model to a phone on the home LAN. This is revisited only if the web app is ever exposed beyond the home network — which FR-016 forbids for v1.
- **Home-network-only, no offline mode**, matching the Android app: entry creation and viewing require the backend to be reachable. No local queuing or sync layer is built for v1.
- The same **fixed feeling set** and the same **guiding-question library** are served from the backend, so the two clients can never drift apart on either.
- The same **minimum-occurrence threshold** governs when a pattern is surfaced, since pattern detection stays in the backend and is not reimplemented per client.
- Diary content continues to be sent to a third-party LLM (Claude) in real time for feeling suggestion and pattern narration, exactly as disclosed and justified in the Android feature's spec. The web client adds **no new** off-machine data flow — it triggers the same backend behavior.
- **Reminders stay on the phone** (decided 2026-07-28). The four daily check-ins (9:00, 12:00, 18:00, 21:00) remain an Android-only capability. Browser reminders would only fire while a page or background worker is active — unreliable by nature, and a reliable version would require exposing the backend over a secure connection, which FR-016 forbids. Duplicating them would also mean being buzzed twice at 9:00. "Same functionality" is therefore scoped to the same *diary* functionality, not the same notification behavior.
- **Manual refresh, not live updates** (decided 2026-07-28). The web client pulls data when the user opens a view or explicitly refreshes it. It does not hold a persistent connection to watch for changes made on the phone. A persistent update channel for a single-user app is exactly the speculative generality constitution Principle II rules out, and the cost of staleness is bounded by FR-011's concurrent-modification protection. Refetching when the browser tab regains focus is permitted as a cheap improvement but is not required, and does not change the guarantee: the explicit refresh is what the user can rely on.
- **Modern evergreen browsers only** (current versions of Chromium-based browsers, Firefox, and Safari). Legacy browser support is out of scope.
- **Single-user still applies**: the web client introduces no accounts, sharing, multi-user access, or any notion of a second person's diary.
- **English-language entries only**, as with the Android app.
- The web app is reached at the same self-hosted backend the phone already talks to, so the user does not configure a separate address for it.
