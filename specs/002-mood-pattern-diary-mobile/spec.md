# Feature Specification: Mood Pattern Diary Mobile App

**Feature Branch**: `002-mood-pattern-diary-mobile`

**Created**: 2026-07-27

**Status**: Draft

**Input**: User description: "so, I still want it to be a diary app. I want it to be really easy to enter diary entries in a day. i can enter multiple in a day. the UI should be very modern, sleek and easy to use. I want it to be a pleasure to write. I want this to be a mobile app for Android, with a backend on the current machine. it's a diary app, but the main goal is much more dramatic and usable and this should be the main driver of this app. I want to detect patterns in my daily life. from what I write, detect feelings or ask me to select among feelings, and then match these with the text I write. for example, I drank coca cola today and I felt really sleepy. or I ate takeout and I felt like real shit and fat after. these are some non exhaustive examples. I want to detect patterns in my life, and based on these, to suggest improvements or what to keep doing. so it's important to write multiple entries a day. the mobile app should be able to notify me at 9am, 12pm, 6pm and 9pm. the main goal is pattern identification, but this is not the only goal, to suggest improvements. I want to be able to track my feelings per month, in a calendar of sorts. how many times I felt happy, how many times I felt shit, exhausted, depressed, excited, neutral etc. and the anaverage per day. again, extremely modern, easy to use and sleek UI UX. this is a very important part of the mobile app side"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Capture a diary entry in seconds, as many times a day as needed (Priority: P1)

The user opens the app at any point in their day and writes a short, free-text entry about what just happened, then tags or confirms the feeling that goes with it. They can do this several times a day (e.g., after breakfast, after lunch, in the evening) without it ever feeling like a chore.

**Why this priority**: Every other capability (pattern detection, monthly summaries, reminders) depends entirely on entries existing. If capturing an entry isn't fast and enjoyable, the user won't produce the data the rest of the app relies on.

**Independent Test**: Can be fully tested by opening the app, starting a new entry, writing a sentence, confirming a feeling, and saving — then repeating it a second time the same day and confirming both entries are kept separately under that day.

**Acceptance Scenarios**:

1. **Given** the app is open, **When** the user starts a new entry, writes free text, and saves it, **Then** the entry is stored with a timestamp and immediately appears in today's entry list.
2. **Given** the user already saved one entry today, **When** they create another entry later the same day, **Then** both entries remain separate and are both visible under today's date, in order.
3. **Given** the user is finishing an entry, **When** they save it, **Then** the app suggests a feeling inferred from the entry text and requires the user to confirm or override that suggestion before the entry is considered complete.
4. **Given** a previously saved entry, **When** the user opens it again, **Then** they can edit its text/feeling or delete it entirely.

---

### User Story 2 - Be guided by structured questions while writing an entry (Priority: P2)

Instead of facing a blank page, the user is walked through a short set of prompts when creating an entry — some general (e.g., "How are you feeling right now?", "What just happened?") and some more specific or situational — so they always know what to write. Answering the prompts becomes the entry itself, removing the blank-page hesitation while also giving the app cleanly structured input to work with.

**Why this priority**: This directly serves the app's two biggest goals at once — it removes the main thing that makes diary-writing feel like a chore (extends Story 1), and it produces the consistent, structured signal that pattern detection (Story 3) depends on to work reliably, which is the single most important payoff of this feature.

**Independent Test**: Start a new entry and confirm the app presents a short sequence of guiding questions instead of an empty text box; answer them and confirm the entry is saved with both the free text and the structured answers attached.

**Acceptance Scenarios**:

1. **Given** the user starts a new entry, **When** the entry screen opens, **Then** the user sees a short sequence of guiding questions — a mix of general and more specific ones — instead of only a blank text field.
2. **Given** the guiding questions, **When** the user answers them, **Then** their answers become the entry's content without requiring them to compose free-form text from scratch.
3. **Given** a user who prefers to write freely, **When** they are in the entry flow, **Then** they can bypass the guided questions and write an unstructured entry instead.
4. **Given** entries created through the guided flow, **When** the pattern-detection engine processes them, **Then** it can reliably use the structured answers — not just raw free text — as input for detecting topic-feeling correlations.

---

### User Story 3 - Discover patterns between daily life and feelings, with suggestions (Priority: P3)

The user wants the app to notice, over time, that certain things they do or consume tend to line up with certain feelings (e.g., drinking soda with feeling sleepy, eating takeout with feeling bad/heavy), and to surface those patterns along with a suggestion — either to change the habit or to keep doing it.

**Why this priority**: This is the app's central, differentiating purpose — the user described it as "the main driver" of the app, more important than the diary-writing itself. It only becomes usable once User Story 1 (and ideally Story 2's structured answers) has produced entries to analyze.

**Independent Test**: Seed the diary with entries that repeatedly pair a recurring topic (e.g., "coca cola") with the same feeling (e.g., "sleepy") several times across different days, then open the Insights view and confirm the app surfaces that correlation with a related suggestion.

**Acceptance Scenarios**:

1. **Given** a recurring topic has been paired with the same feeling across multiple separate entries, **When** the user opens the Insights view, **Then** the app displays that pattern in plain language (e.g., "You felt sleepy in 4 of the last 5 entries that mentioned Coca-Cola").
2. **Given** a detected pattern links a topic to a negative feeling, **When** the user views that pattern, **Then** the app offers a concrete suggestion for change (e.g., "consider cutting back on takeout").
3. **Given** a detected pattern links a topic to a positive feeling, **When** the user views that pattern, **Then** the app suggests keeping that habit.
4. **Given** too few entries exist to support a pattern, **When** the user opens Insights, **Then** the app explains more entries are needed instead of showing an unsupported pattern.

---

### User Story 4 - Get reminded to check in throughout the day (Priority: P4)

The user gets a notification on their phone at four points during the day, prompting them to log how they're doing, so entries build up consistently rather than relying on the user remembering on their own.

**Why this priority**: Directly increases how many entries get logged per day, which is what makes pattern detection (Story 3) and the monthly view (Story 5) useful in the first place — but the app is still usable without it if the user opens it on their own.

**Independent Test**: Enable notifications, wait for (or simulate) 9:00, 12:00, 18:00, and 21:00, and confirm a reminder notification arrives at each and opens directly into a new entry when tapped.

**Acceptance Scenarios**:

1. **Given** notifications are enabled, **When** the device clock reaches 9:00, 12:00, 18:00, or 21:00, **Then** the user receives a notification prompting them to check in.
2. **Given** a reminder notification has arrived, **When** the user taps it, **Then** the app opens directly to the new-entry screen.
3. **Given** the user already logged an entry recently, **When** the next scheduled reminder time arrives, **Then** the reminder still fires as normal.

---

### User Story 5 - Review a month of feelings in a calendar view (Priority: P5)

The user opens a monthly, calendar-style view that shows which feelings they logged on each day, plus totals for the month (how many days/entries were happy, exhausted, depressed, excited, neutral, etc.) and the average number of entries per day.

**Why this priority**: A retrospective, satisfying summary that reinforces the habit and complements the pattern insights, but it is a reporting layer on top of data already captured by Stories 1–4.

**Independent Test**: Seed a month of entries with varied feelings, open the monthly view, and confirm each day cell reflects the feeling(s) logged and that month-level totals and the daily average are shown.

**Acceptance Scenarios**:

1. **Given** entries exist across a month, **When** the user opens the monthly view, **Then** each day cell visually indicates the feeling(s) logged that day.
2. **Given** a month of data, **When** the user views the summary for that month, **Then** the app shows a count per feeling category (e.g., "Happy: 12 days, Exhausted: 5 days") and the average number of entries per day.
3. **Given** a day with more than one feeling logged, **When** it's shown on the calendar, **Then** the day reflects that mix rather than only a single feeling.

---

### Edge Cases

- What happens when the user skips one of the guided questions — is it left blank, or does the flow require a minimal answer before moving on?
- Should the set of guiding questions be identical for every entry, or vary/adapt based on time of day, prior answers, or what has proven useful for detecting patterns?
- What happens when the user saves an entry without confirming a feeling — is the entry blocked, or saved as "unclassified"?
- How does the system handle entries whose text doesn't clearly match any of the predefined feelings?
- What happens in the first days of use, before enough entries exist to detect any pattern?
- How are conflicting signals handled, e.g., the same topic correlates with different feelings on different occasions?
- What happens if the phone can't reach the home-machine backend when the user tries to save an entry (e.g., away from home Wi-Fi)? Since offline creation is out of scope for v1, the app must clearly tell the user the entry could not be saved rather than silently losing it.
- How does the monthly calendar represent a day with zero entries?
- What happens to an already-surfaced pattern/insight when one of the entries it was based on is edited or deleted?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST allow the user to create a free-text diary entry at any time.
- **FR-002**: The system MUST allow multiple entries on the same calendar day, each stored with its own timestamp, without overwriting or merging them.
- **FR-003**: The entry-creation flow MUST be completable in a short number of steps, prioritizing writing speed and a pleasant experience over additional required fields.
- **FR-004**: The system MUST guide entry creation with a structured set of questions/prompts — a mix of general and more specific, situational ones — rather than only offering a blank free-text field.
- **FR-005**: The system MUST let the user bypass the guided questions and write a free-form entry instead, at their discretion.
- **FR-006**: The set of guiding questions MUST be designed so that, beyond making entries easy to write, the answers they produce are reliable inputs for feeling inference and pattern detection — this is the primary design criterion for the question set, and MUST be established through dedicated research/design work before implementation.
- **FR-007**: The system MUST capture a feeling for each entry using a hybrid flow: it suggests a feeling inferred from the entry text/answers, and the user confirms or overrides that suggestion before the entry is saved.
- **FR-008**: The system MUST let the user edit or delete a previously saved entry.
- **FR-009**: The system MUST analyze saved entries over time to detect recurring correlations between topics/activities mentioned in entry content (e.g., foods, drinks, activities) and the feelings attached to those entries.
- **FR-010**: The system MUST present detected patterns to the user in a dedicated Insights view, described in plain, specific language rather than raw statistics.
- **FR-011**: For each detected pattern, the system MUST provide an actionable suggestion — to reduce/change the habit when linked to a negative feeling, or to keep the habit when linked to a positive feeling.
- **FR-012**: The system MUST NOT present something as a "pattern" until it has recurred a minimum number of times, to avoid false positives from a single occurrence.
- **FR-013**: The system MUST send a local reminder notification at 9:00, 12:00, 18:00, and 21:00 every day, prompting the user to log an entry.
- **FR-014**: Tapping a reminder notification MUST take the user directly into the new-entry flow.
- **FR-015**: The system MUST provide a monthly, calendar-style view showing which feeling(s) were logged on each day.
- **FR-016**: The system MUST show, per month, a count of days/entries for each feeling category and the average number of entries logged per day.
- **FR-017**: The diary-writing, reminder, insights, and monthly-view experiences MUST be delivered as an Android mobile app.
- **FR-018**: All diary data MUST be stored on a backend the user runs themselves (on their own machine), rather than a third-party cloud service.
- **FR-019**: The system relies on the phone's own device lock and the privacy of the home network for protection; no additional in-app authentication (PIN, biometric, or backend login) is required for v1.
- **FR-020**: The system MUST support entry creation and viewing only while the phone can reach the home-machine backend directly (e.g., connected to the same home Wi-Fi or a VPN back to it); offline entry creation away from that network is out of scope for v1.

### Key Entities *(include if feature involves data)*

- **Diary Entry**: A single note the user wrote — either free text or answers to guiding questions — with a creation timestamp, the feeling(s) attached to it, and any topics/keywords identified in its content.
- **Guiding Question**: A predefined prompt (general or situation-specific) shown during entry creation; the user's answer to it becomes part of an entry's content and is a direct input to feeling inference and pattern detection.
- **Feeling**: A mood label attached to an entry (e.g., happy, excited, neutral, sleepy, exhausted, stressed, sad, depressed), drawn from a defined set used consistently across entries, insights, and the monthly view.
- **Topic**: A recurring subject mentioned across entries (e.g., "coca cola," "takeout," "exercise") that the pattern engine tracks to look for correlations with feelings.
- **Pattern/Insight**: A detected correlation between a Topic and a Feeling, backed by the entries that support it, along with the suggestion shown to the user.
- **Monthly Summary**: The aggregated view for a given month — per-feeling day/entry counts and the average number of entries per day.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can go from opening the app to saving their first diary entry in under 30 seconds.
- **SC-002**: A user can save a second same-day entry in under 15 seconds from tapping "new entry," reflecting the low-friction, pleasant writing goal.
- **SC-003**: After two weeks of regular use (at least one entry per day), the app surfaces at least one meaningful pattern in the Insights view.
- **SC-004**: Users rate the writing experience as modern and pleasant in at least 90% of feedback collected during testing.
- **SC-005**: A user can see their full month's feeling breakdown (per-feeling counts and daily average) on a single screen without additional navigation.
- **SC-006**: Reminder notifications arrive within one minute of each of the four scheduled times, every day.
- **SC-007**: Suggestions shown for a detected pattern are specific enough that a user can act on them immediately, without needing further explanation.
- **SC-008**: At least 90% of entries created through the guided-question flow yield a usable topic and feeling for pattern detection without the user needing to go back and add more detail.
- **SC-009**: Users report that starting an entry via the guided questions feels easier than facing a blank page in at least 90% of feedback collected during testing.

## Assumptions

- This is a single-user, personal app: no multi-user accounts, sharing, or social features are in scope.
- The feeling set is a fixed, predefined list covering common categories (e.g., happy, excited, neutral, sleepy, exhausted, stressed, sad, depressed) rather than free-form custom feelings, for v1.
- A pattern requires at least 3 occurrences of the same topic-feeling pairing before it is surfaced as an insight, unless a different threshold is specified later.
- Reminder notifications fire at all four scheduled times regardless of whether the user already logged an entry that day, to reinforce the habit.
- The app targets English-language entries only for v1.
- "Backend on the current machine" means the user's own existing computer hosts the diary data and pattern-analysis logic; the mobile app is a client to it.
- The app is only usable while the phone can reach that backend directly (same home network or VPN); no offline queuing/sync is built for v1.
- No in-app authentication is required; access control is left to the phone's own lock screen and the privacy of the home network.
- Feeling capture is hybrid: the app infers a suggested feeling from the entry text and the user confirms or overrides it, rather than always requiring manual selection or trusting automatic detection unconfirmed.
- The exact content of the guiding questions (which general ones, which specific/situational ones, how many, when each applies) is not yet defined. Determining them requires a dedicated research/design task — informed by what best supports feeling inference and pattern detection — before implementation can begin.
- Guided questions are optional per entry; free-form writing remains available for users who prefer it, so the framework is a scaffold rather than a restriction.
- FR-018's "stored on a backend the user runs themselves" governs persistent storage: entry data is never persisted anywhere but the user's own backend. It does not prohibit transient processing elsewhere — entry text and supporting-entry content are sent to a third-party LLM API (Claude) in real time for feeling suggestion (FR-007) and pattern narration (FR-010/FR-011), per the project constitution's Privacy by Architecture principle, which requires this kind of exception to be explicit rather than implicit. This is accepted as a deliberate trade-off: it's the only practical way to get natural-language feeling inference and pattern explanations without building and maintaining a local NLP/ML stack, and no diary content is retained by the app anywhere outside the user's own backend.
