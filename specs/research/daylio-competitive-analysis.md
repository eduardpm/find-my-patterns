# Daylio: Competitive Analysis

**Researched**: 2026-08-28
**Scope**: what Daylio does, what its charts are, what its users praise and complain about, and what
Mood Pattern Diary should build in response — with charts and visualisation first.
**Evidence rule**: every claim links to the source that owns it — Daylio's own site, help centre,
privacy policy, or the two app-store listings. Reviews are quoted from the store listings, which are
the publisher of that text. Secondary write-ups are grouped separately and marked. Anything I could
not confirm from an owning source is labelled **[unverified]**.

---

## 1. Where we stand today (read from this repo)

Grounding for the comparison. This is what Mood Pattern Diary captures and computes right now.

**What we capture per entry** (`backend/src/db/schema.ts`, `android/.../domain/Entry.kt`):

| Field | Notes |
| --- | --- |
| `raw_text` | Free text. The core of the entry. |
| `mode` | `guided` or `freeform`. |
| `entry_date`, `created_at` | Several entries per day are allowed; they are never merged. |
| `feeling_key` + `entry_feelings` | Up to 4 feelings from a backend-owned set of ~31 words in 4 valence groups. |
| `feeling_source` | `suggested` / `confirmed` / `overridden` / `unset`. Only confirmed or overridden count as evidence. |
| `feeling_intensity` (1–5) | Optional, per feeling. Most entries may have none. |
| `guiding_question_answers` | Question key, the wording snapshot, and the answer text. |
| `entry_topics` | Topics extracted from free text by a local Qwen model, plus user aliases. |

**What we compute**: threshold-confirmed topic→feeling patterns with lift, base rate, present/absent
2×2 counts, confounders, and an entry-level evidence trail (`backend/src/insights/patterns.service.ts`);
inverse patterns; pattern withdrawals with a reason; a pattern echo on save
(`backend/src/insights/echo.service.ts`); weekday and time-of-day valence averages
(`backend/src/insights/when.service.ts`); and a monthly summary with per-day feelings, per-feeling
totals, and average entries per day (`backend/src/monthly-summary/monthly-summary.service.ts`).

**Screens**: Today, EntryComposer, GuidedQuestionFlow, EntryDetail, DayEntries, MonthlyCalendar,
Insights (PatternCard + WhenPanel + WithdrawalNotice), Topics, Settings — on Android
(`android/app/src/main/kotlin/com/moodpatterndiary/app/ui/`) and mirrored in `web/src/screens/`.

**We have no charts.** There is no chart library in either client — `android/app/build.gradle.kts`
has no Vico or MPAndroidChart, and `web/package.json` has exactly three runtime dependencies
(`react`, `react-dom`, `react-router-dom`). The only drawn things in the whole app are two
hand-placed `Box` elements: the −1…+1 marker track in `ui/WhenPanel.kt` and the 2 dp intensity bar in
the calendar cell in `ui/MonthlyCalendarScreen.kt`. Everything else is text, rows, and dots.

**One structural fact that matters below**: `GET /entries` accepts a single `date` only
(`backend/src/entries/entries.controller.ts`), and `GET /monthly-summary` accepts a single month.
There is no range or series endpoint, so almost every chart proposed later needs a new backend read.
The repository layer already has `findInDateRange`, so the work is an endpoint, not a query engine.

---

## 2. Daylio feature inventory

Daylio is a "micro-diary": pick a mood, tap activity icons, done. It has run since 2015 and claims
20 million+ users ([daylio.net](https://daylio.net/)). It is published by Relaxio s.r.o. on iOS and
Habitics on Android
([App Store](https://apps.apple.com/us/app/daylio-journal-mood-tracker/id1194023242),
[Google Play](https://play.google.com/store/apps/details?id=net.daylio)).

### Entry model

| Capability | Detail | Source |
| --- | --- | --- |
| Mood scale | Five default moods on a positivity scale. Users edit the emoji and name. | [Create and manage moods](https://daylio.net/faq/docs/daylio-faq/tutorials/create-and-manage-moods/), [How to track moods](https://daylio.net/how-to-track-moods/) |
| Custom moods | Unlimited, but each is filed **under one of the five default categories**. Premium only. | [Create and manage moods](https://daylio.net/faq/docs/daylio-faq/tutorials/create-and-manage-moods/), [Premium features](https://daylio.net/faq/docs/daylio-faq/about/daylio-premium-features/) |
| Activities | Tap icons from a large database; create custom ones; group them. | [daylio.net](https://daylio.net/) |
| Notes | "Quick Note" and "Full Note" with bold, italics and bullets. | [Add note to entry](https://daylio.net/faq/docs/daylio-faq/tutorials/add-note-to-entry/) |
| Writing templates | Built-in (Gratitude, Idea, To-Do, Night Brain Dump); custom templates are Premium. | [Add note to entry](https://daylio.net/faq/docs/daylio-faq/tutorials/add-note-to-entry/), [Premium features](https://daylio.net/faq/docs/daylio-faq/about/daylio-premium-features/) |
| Photos | Attached to entries. Up to three per entry. | [Adding and managing photos](https://daylio.net/faq/docs/daylio-faq/tutorials/adding-and-managing-photos/); count per entry from [Wikipedia](https://en.wikipedia.org/wiki/Daylio) (secondary) |
| Voice memos | Listed on the home page and in the Play description. | [daylio.net](https://daylio.net/), [Google Play](https://play.google.com/store/apps/details?id=net.daylio) |
| Scales | Sliders for things like sleep, stress, energy and pain. Shipped April 2026 (v1.70.0). | [App Store version history](https://apps.apple.com/us/app/daylio-journal-mood-tracker/id1194023242) |
| Multiple entries per day | Yes. The stats docs distinguish "one entry per day" from more. | [Activity and Mood Statistics](https://daylio.net/faq/docs/daylio-faq/about/activity-and-mood-statistics/) |
| Backdating | Yes. A reviewer notes going back and adding entries days later. | [App Store review, 05/04/2022](https://apps.apple.com/us/app/daylio-journal-mood-tracker/id1194023242) |

### Everything around the entry

- **Goals** — daily, weekly or custom repetition; current streak, longest streak, weekly and
  four-week success rate, total and monthly completions; levels and achievements that you do not lose
  ([Setting up goals](https://daylio.net/faq/docs/daylio-faq/tutorials/setting-up-goals/)).
- **Reminders** — customisable text and time; unlimited reminders are Premium
  ([Premium features](https://daylio.net/faq/docs/daylio-faq/about/daylio-premium-features/)).
- **Widgets** — a mood widget and a goals widget on Android, per user reviews
  ([Google Play reviews](https://play.google.com/store/apps/details?id=net.daylio)). Not documented
  on Daylio's own pages **[unverified as an official feature list item]**.
- **Lock** — PIN, fingerprint, Face ID. PIN lock on iOS is Premium
  ([daylio.net](https://daylio.net/), [Premium features](https://daylio.net/faq/docs/daylio-faq/about/daylio-premium-features/)).
- **Themes** — colour themes, dark mode, background themes and coloured emojis (v1.69, Dec 2025)
  ([daylio.net](https://daylio.net/), [App Store version history](https://apps.apple.com/us/app/daylio-journal-mood-tracker/id1194023242)).
- **On This Day** — a feed view of entries from the same date in earlier years (v1.74, Jul 2026)
  ([App Store version history](https://apps.apple.com/us/app/daylio-journal-mood-tracker/id1194023242)).
- **Export** — CSV and PDF. PDF covers last 7 days, last 30 days, last week, last month or all time,
  with an optional summary table; Daylio warns that large exports "is a demanding task for your
  phone" and may crash
  ([PDF export](https://daylio.net/faq/docs/daylio-faq/tutorials/pdf-export/), [daylio.net](https://daylio.net/)).
  PDF download is Premium ([Premium features](https://daylio.net/faq/docs/daylio-faq/about/daylio-premium-features/)).
- **Backup** — Google Drive on Android, iCloud on iOS, plus a manual backup file that carries all
  entries, moods, activities and settings and is the only way to move between iOS and Android.
  Roughly the last 100 backups are kept. Automatic backups are Premium
  ([Backup options](https://daylio.net/faq/docs/daylio-faq/backup/backup-options/),
  [Missing entries](https://daylio.net/faq/docs/daylio-faq/issues/missing-entries/),
  [Premium features](https://daylio.net/faq/docs/daylio-faq/about/daylio-premium-features/)).
- **No sync, by design** — "it's hard to do real-time sync between multiple devices" because nothing
  is on their servers; they recommend one primary device
  ([Can I use Daylio on multiple devices?](https://daylio.net/faq/can-i-use-daylio-on-multiple-devices/)).
- **No web or desktop app** — "Daylio is not being developed for computers or the web"
  ([Writing entries on computer](https://daylio.net/faq/docs/daylio-faq/tutorials/writing-entries-on-computer/)).
- **Apple Health** — two-way, with read and write permissions; sleep and activity are named. Apple
  Health data can be included in PDF exports since v1.68.6
  ([Apple Health troubleshooting](https://daylio.net/faq/docs/daylio-faq/issues/apple-health-troubleshooting/),
  [App Store version history](https://apps.apple.com/us/app/daylio-journal-mood-tracker/id1194023242)).
  No Google Fit or Health Connect equivalent is documented **[unverified]**.
- **Privacy** — entries stay on the device and "all calculations are done on your device as well".
  Daylio itself uses Google Analytics for Firebase and Firebase Crashlytics, and on Android may use
  the Google Advertising ID ([Privacy policy](https://daylio.net/faq/privacy-policy/)). Note the
  Play listing carries a "Contains ads" badge while the Play description says "No ads, no tracking"
  ([Google Play](https://play.google.com/store/apps/details?id=net.daylio)).
- **Accessibility** — Daylio's own page says "Daylio does not have universal support for font size at
  this point" and points users at OS-level settings
  ([Change font size and contrast](https://daylio.net/faq/docs/daylio-faq/tutorials/how-to-change-font-size-and-contrast/)).
  The iOS listing declares VoiceOver and Dark Interface support
  ([App Store](https://apps.apple.com/us/app/daylio-journal-mood-tracker/id1194023242)).

---

## 3. The charts, in detail

This is the part worth studying. Daylio calls the correlation view "the crown jewel"
([Activity and Mood Statistics](https://daylio.net/faq/docs/daylio-faq/about/activity-and-mood-statistics/)).

### 3.1 Main Stats screen

| Chart | Visual form | Data it needs | Our effort |
| --- | --- | --- | --- |
| **Mood chart over time** | Line, one point per day, smoothed curve, pinch to zoom (redesigned v1.72–1.73, 2026) ([App Store version history](https://apps.apple.com/us/app/daylio-journal-mood-tracker/id1194023242)) | A numeric score per day | **M** — we have no numeric day score yet (see §9.1) |
| **Average daily mood** | Bar chart, one bar per period ([Wikipedia](https://en.wikipedia.org/wiki/Daylio), secondary) | Same day score, bucketed by month | **S** once the score exists |
| **Mood count** | Counts per mood plus a stacked ratio bar ([Activity and Mood Statistics](https://daylio.net/faq/docs/daylio-faq/about/activity-and-mood-statistics/)) | Feeling counts in a period | **S** — `monthly-summary` already returns `totals_by_feeling` |
| **Year in Pixels** | A 12×31 grid of coloured cells, one per day, coloured by mood; exportable as an image ([daylio.net](https://daylio.net/)) | One colour per day | **S–M** — the hardest part is picking one colour for a multi-feeling day |
| **Monthly / yearly stats** | Period switcher over the charts above ([daylio.net](https://daylio.net/)) | Range queries | **S** on top of a series endpoint |
| **Goal streaks** | Current streak, longest streak, weekly and 4-week success rate with a trend arrow ([Setting up goals](https://daylio.net/faq/docs/daylio-faq/tutorials/setting-up-goals/)) | Goal completions | **N/A** — we have no goals |

### 3.2 Per-activity and per-mood deep dive ("Advanced Stats", Premium)

Tap any activity or mood in Stats. All of the below come from
[Activity and Mood Statistics](https://daylio.net/faq/docs/daylio-faq/about/activity-and-mood-statistics/).

1. **Frequency** — repetitions in the selected period against the period before, colour-coded to
   match mood colours. Visual form changes with the interval.
2. **Influence on Mood** — four percentage comparisons for one activity:
   - *With and without activity* — entries containing it against entries not containing it.
   - *Previous Day* — how the day **before** the activity looked.
   - *Same Day* — whole days compared, which differs from the first number only when there are
     several entries a day.
   - *Next Day* — the activity day against the day after. Their own example is drinking.
3. **Confidence** — Low / Medium / High, "how much we believe the number is correct". High needs
   "rich source data"; Low "might describe a specific trend, but you should not take it at face
   value". **No underlying counts are shown.**
4. **Longest Period** — longest run with the activity against the longest run without it.
5. **Mood Count** — exact numbers plus a ratio bar, for the selected activity.
6. **Related Activities** — for a selected mood, a percentage scale and a top-N list of the
   activities that occur most with it.
7. **Occurrence During Week** — a bar chart, x-axis = day of week, bar height = repetitions.

### 3.3 Reading of Daylio's chart design

- **Everything is a count on a pre-defined tag.** The whole engine rests on the user having tapped
  an activity icon. Nothing is derived from what they wrote.
- **The temporal comparisons are the genuinely good idea.** Previous Day / Same Day / Next Day is a
  cheap, honest way to hint at direction without claiming causation. We compute none of these.
- **Confidence is a shield, not an explanation.** Three words stand in for the counts. A user cannot
  check the arithmetic. Our pattern cards already show present/absent counts, base rate, lift and the
  actual entries — that is a real advantage, and it is worth keeping when we add charts.
- **Occurrence During Week is a weaker version of our WhenPanel.** Theirs counts repetitions; ours
  averages valence and suppresses thin buckets. Ours is better analysis and worse visual.

---

## 4. Free vs Premium, and price

Daylio's own list of "most important premium features"
([Premium features](https://daylio.net/faq/docs/daylio-faq/about/daylio-premium-features/), read
2026-08-28), verbatim:

> PIN lock (iOS) · Advanced Stats · Unlimited Moods · Extra 2000+ icons and emojis · Custom Note
> Templates · Infinite Reminders · Automatic Backups · Download records as PDF file · Extra color
> themes and custom colors · Unlimited Goals · Unlimited Important Days

They keep "a free unlimited version of Daylio the same as before", offer a 7-day trial, and say you
can downgrade "without fear of losing any data"
([Premium features](https://daylio.net/faq/docs/daylio-faq/about/daylio-premium-features/)).

The practical split: **basic charts are free; the per-activity correlation deep dive is Premium.**
Free users confirm they still get monthly and yearly reports, photos, voice memos and goals
([Google Play reviews](https://play.google.com/store/apps/details?id=net.daylio)).

**Prices, checked 2026-08-28, US storefronts:**

| Store | What is listed |
| --- | --- |
| Google Play | In-app purchases **$0.99 – $79.99 per item** ([listing](https://play.google.com/store/apps/details?id=net.daylio)) |
| App Store | Items named "Daylio Premium" at **$4.99, $17.99, $23.99, $35.99** and "PREMIUM" at **$59.99** ([listing](https://apps.apple.com/us/app/daylio-journal-mood-tracker/id1194023242)) |

Neither store page maps a price to a term, so which is monthly, yearly or lifetime is
**[unverified]**. Users describe roughly $20–25 a year and a lifetime licence that is per-platform
([Google Play reviews](https://play.google.com/store/apps/details?id=net.daylio)). Prices vary by
region and change often.

**Scale, checked 2026-08-28:**

| Store | Rating | Ratings | Other |
| --- | --- | --- | --- |
| Google Play | 4.7 | ~460,600 (5★ 383,903 · 4★ 49,675 · 3★ 14,820 · 2★ 3,902 · 1★ 8,311) | 10M+ downloads; released Aug 2015; "Contains ads" ([listing](https://play.google.com/store/apps/details?id=net.daylio)) |
| App Store (US) | 4.77 | 61,304 | v1.75.1, 27 Aug 2026 ([listing](https://apps.apple.com/us/app/daylio-journal-mood-tracker/id1194023242)) |

Note the 1★ count is more than double the 2★ count — the usual signature of a paywall or data-loss
complaint cluster, which §6 bears out.

---

## 5. What users praise

All quotes below are from reviews published on
[the Google Play listing](https://play.google.com/store/apps/details?id=net.daylio) unless marked, and
are given with their star rating and helpful-vote count.

- **Speed and the absence of friction.** This is the single most repeated theme. "So easy, it's life
  changing" (5★, 53 votes). Another: journaling is "as quick as sending a text" (5★, 53 votes).
- **It survives bad days.** One reviewer wanted an app that works "when I'm not" doing well and says
  "This covers both" (5★, 20 votes).
- **Customisation.** Custom activities, icons, colours and renamed moods come up constantly. One
  user repurposed the mood scale entirely: "Instead of different moods, I have them labeled as a
  scale of pain level" (5★).
- **Streaks as motivation.** "I am at a 1731 day streak" (4★, 4 votes); another reports a 500-day
  streak and that a phone migration "just worked" from Google Drive (5★, 79 votes).
- **Correlations, when they land.** "I also like seeing the correlations between moods and
  activities" (5★); another says it helped show "what was making me happy and what wasn't" (5★).
- **Clinical usefulness.** One user keeps it "to show my physicians" (5★, 43 votes). Another uses it
  to "identify triggers for depression, mania, and anxiety" (5★, 61 votes).
- **Free tier is genuinely usable.** "Full usability without paying" (5★, 49 votes).

---

## 6. What users complain about — our openings

Same source unless marked.

| Theme | Evidence |
| --- | --- |
| **Subscription instead of a one-time purchase** | The single most up-voted review on the listing, 351 votes: "make premium a one time payment. Subscription adds up" (4★). Another: "they no longer offer the ability to buy the premium outright" (2★, 12 votes). Another would pay "$20-70" for a lifetime licence "in an instant" (4★, 47 votes). |
| **Paywall surprise and in-app ads** | "I feel lied to" about a trial that ends (1★, 4 votes). "I used it for 30 seconds and had about 6 obtrusive pop up ads" (1★, 2 votes). A paying user is annoyed at in-app promotion of an unrelated product (3★). Compare the listing's own "Contains ads" badge against the description's "No ads, no tracking" ([listing](https://play.google.com/store/apps/details?id=net.daylio)). |
| **Entries locked behind Premium to read back** | "to access all your entries in a reasonable format you need to pay for premium" (1★, 29 votes) — this is the PDF export gate. |
| **The five-mood scale is too coarse** | "It feels limiting to have to select one of five moods for an entry" (3★, 15 votes), noting the rest of the app is customisable. Custom moods are Premium and still nest under the five ([Create and manage moods](https://daylio.net/faq/docs/daylio-faq/tutorials/create-and-manage-moods/)). |
| **Charts do not answer the actual question** | "You can only see a graph of one activity at a time, which is pretty useless" — the reviewer wants two factors compared (3★, 2 votes). Another paying user: "I'm disappointed that the analysis remains up to me" (3★, 2 votes). A third: "they made the graphs much worse earlier this year" (3★, 2 votes). One asks plainly: "can we get the ability to compare data points against each other?" (5★). |
| **No hourly / intra-day view** | "the lack of an hourly view" is the one thing stopping a 5★ reviewer from paying (5★, 201 votes). |
| **Day boundary is not configurable** | A 2 a.m. entry lands on the wrong day: "I want it to still count towards the previous day" (5★, 235 votes). |
| **Data loss without a backup** | "my phone randomly dies... EVERYTHING was gone" (2★, 2 votes). Daylio's own page confirms the outcome: without a cloud or system backup "your data will probably be lost" ([Missing entries](https://daylio.net/faq/docs/daylio-faq/issues/missing-entries/)). |
| **Lost entries / broken streaks** | "I know I logged it, why's it not being saved?" (3★, 3 votes). Another was "stuck on 109 Days" with days reported missing (1★, 28 votes). |
| **No web or desktop, no sync** | "They refuse to provide a web/windows 10 app" (3★, 7 votes). Confirmed by Daylio ([Writing entries on computer](https://daylio.net/faq/docs/daylio-faq/tutorials/writing-entries-on-computer/), [Multiple devices](https://daylio.net/faq/can-i-use-daylio-on-multiple-devices/)). |
| **It is a tracker, not a journal** | "Adding text is convoluted and i wouldn't consider it a journal at all" (3★, 4 votes). Another could not find where to write (2★, 3 votes). |
| **Reading back is tedious** | Wants to "swipe left/right to go through the days one day at a time" (5★, 146 votes). |
| **Accessibility and platform polish** | "please make your app edge to edge as required in Android 15" (1★, 15 votes). Daylio itself admits no universal font-size support ([Change font size and contrast](https://daylio.net/faq/docs/daylio-faq/tutorials/how-to-change-font-size-and-contrast/)). |
| **A text bug ate an entry** | A `<` in an entry made the app crash on open until the user found it (5★, 290 votes) — a reminder to test our own text handling. |

The clean summary: **Daylio's users are asking for a real journal, a finer mood scale, charts that
compare more than one thing, and honest pricing.** Those are exactly the four places our design
already points.

---

## 7. Daylio versus us

| Capability | Daylio | Mood Pattern Diary | Who is ahead |
| --- | --- | --- | --- |
| Time to log | Two taps ([daylio.net](https://daylio.net/)) | Type or speak an entry, pick feelings | **Daylio, clearly** |
| Mood vocabulary | 5 levels; custom moods nest under them and are Premium | ~31 words in 4 valence groups, up to 4 per entry, free | **Us** |
| Mood intensity | "Scales" sliders since Apr 2026 | Optional 1–5 per feeling (`feeling_intensity`) | Even |
| What gets correlated | Pre-defined activity icons the user must set up first | Topics extracted from free text by a local model, plus user aliases | **Us** |
| Where the mood comes from | User picks it | Local model suggests, user confirms or overrides; only confirmed counts | **Us** |
| Correlation output | 4 percentages + Low/Med/High confidence, no counts | Lift, base rate, present/absent 2×2, confounders, entry-level evidence trail | **Us on rigour** |
| Temporal comparison | Previous Day / Same Day / Next Day | None | **Daylio** |
| When am I worst | Occurrence-per-weekday bar chart | Weekday and time-of-day valence averages with a minimum-bucket rule | **Us on method, Daylio on presentation** |
| Retracting a claim | Not offered | Withdrawal notices with a typed reason | **Us** |
| **Charts** | Mood line, average bars, mood counts, Year in Pixels, weekday bars, ratio bars | **None** | **Daylio, by a mile** |
| Calendar | Colour-coded calendar and Year in Pixels | Month grid with feeling dots and an intensity bar | **Daylio** |
| Goals / streaks | Full system with levels and achievements | None | **Daylio** |
| Reminders | Custom text and times; unlimited is Premium | Four fixed daily alarms (`notifications/ReminderScheduler.kt`) | **Daylio** |
| Photos, voice memos | Both | Voice **input** transcribed locally and word-faithfully, then discarded | Different goals; ours is stronger for text |
| Widgets | Mood and goals widgets | None | **Daylio** |
| Lock | PIN, fingerprint, Face ID | None on device; backend has optional password auth | **Daylio** |
| Export | CSV + PDF (PDF Premium) | None shipped; `npm run backup` copies the SQLite file | **Daylio** |
| Search | Search and filter entries | None | **Daylio** |
| Sync across devices | Explicitly not supported | One backend serves web and Android from the same database | **Us** |
| Web client | None, by policy | Yes | **Us** |
| Offline | Fully offline | Requires the backend to be reachable | **Daylio** |
| Analytics on the user | Firebase Analytics + Crashlytics; Advertising ID on Android | None; nothing leaves the machine | **Us** |
| Price | Subscription; users report ~$20–25/yr | Self-hosted, free | **Us** |

---

## 8. Adjacent competitors, briefly

- **Bearable** — the closest thing to a rigorous version of Daylio. It requires "at least 3 days
  *with* a factor" and three without before it will report a correlation, and presents a rotatable
  comparison graph with metrics as bars or lines and factors as background gradients. Its
  "Factor Effect Reports" show **1–7 day impact windows**, which is a lagged-effect idea neither
  Daylio nor we have ([Bearable support](https://bearable.app/support/howto/how-to-find-correlations/)).
  *Idea worth stealing: the lag window, and the explicit minimum-days rule stated in the UI.*
- **Exist.io** — a correlation engine over 20+ connected services (Apple Health, Fitbit, Oura,
  RescueTime, Strava, weather, calendar), with weekly summary emails and phrasing like "Your weight
  is higher when you wake more during sleep". $6.99/month or $62.90/year
  ([exist.io](https://exist.io/)). *Idea worth stealing: pushing a periodic digest rather than
  waiting for the user to open an Insights tab.*
- **Moodistory** — a customisable **2- to 11-point** mood scale, Year in Pixels with drill-down from
  year to month to day, and all data on-device with PDF generated locally
  ([moodistory.com](https://moodistory.com/)). *Idea worth stealing: the drill-down. A year grid
  where a cell opens the month, and a month cell opens the day.*
- **How We Feel** — free, nonprofit, built with Yale's Center for Emotional Intelligence. Its point
  is helping people "find the right word to describe how they feel", with HealthKit sleep/exercise
  data used to spot patterns. Data stays on device unless the user opts into research sharing
  ([App Store](https://apps.apple.com/us/app/how-we-feel/id1562706384)). *Closest to our feeling
  vocabulary; worth watching for how they present a large emotion word set.*
- **Pixels** — a single-developer app built around Year in Pixels plus notes, reminders, a
  customisable palette, and reports. 4.6 stars, 1M+ downloads
  ([Google Play](https://play.google.com/store/apps/details?id=ar.teovogel.yip)). *Proof that the
  year grid alone carries an app.*

---

## 9. Recommendations

### 9.1 Charts and visualisation — the priority list

**Stack decision first.** Do not add MPAndroidChart: it is a View library and would need
`AndroidView` interop inside an all-Compose app. The real choice is hand-drawn Compose `Canvas`
versus [Vico](https://github.com/patrykandpatrick/vico), which is Compose-native.

**Recommendation: hand-draw in Compose `Canvas`, at least for charts 1–4.** Reasons: our charts are
small and highly opinionated (suppressed thin buckets, "not enough data" states, valence colours from
`journalColors`); `ui/WhenPanel.kt` already hand-draws its track and looks right; a chart library
would fight the journal aesthetic and add a dependency for four simple shapes. Reach for Vico only if
we later want zoomable, scrollable, multi-year axes. On web, use inline `<svg>` — `web/` currently has
zero runtime dependencies beyond React and the router, and that is worth keeping.

**Shared prerequisite for charts 1, 2, 4 and 6: a day-score and a series endpoint.**

- Add `GET /insights/series?from=&to=&granularity=day|week|month` in
  `backend/src/insights/insights.controller.ts`, backed by a new `series.service.ts`.
  `EntriesRepository.findInDateRange` already exists, so this is an endpoint plus an aggregation.
- Define the day score explicitly in `backend/src/insights/constants.ts`. We already have
  `VALENCE_SCORE` at +1/0/−1 — deliberately three points, per its own comment. A day score should be
  the **mean valence of confirmed feelings that day**, on −1…+1, and each day must carry its entry
  count so thin days can be drawn faintly rather than confidently. Do **not** silently fold
  `feeling_intensity` into it: intensity is optional, most days will not have it, and mixing an
  optional 1–5 into a −1…+1 mean makes the line dishonest. If we want an intensity-weighted line
  later, ship it as a **separate, opt-in series** that only draws over days that were rated.
- Return the same `constants` block the insights endpoint does, so the clients keep reading
  thresholds rather than hardcoding them (Principle VII).

| # | Chart | What it is | Why | Effort | Data needed | Where it lives |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | **Mood over time line** | One point per day on a −1…+1 axis, zero line drawn, dot size or opacity by entry count, gaps left as gaps. Period switcher: 30 days / 90 days / year. | The single most-expected chart in the category ([daylio.net](https://daylio.net/)); we have nothing. Also answers the "graphs got worse" and "analysis remains up to me" complaints by being legible ([Play reviews](https://play.google.com/store/apps/details?id=net.daylio)). | **M** | Series endpoint + day score | New `ui/charts/MoodTrendChart.kt`, placed at the top of `ui/InsightsScreen.kt`; `web/src/components/MoodTrendChart.tsx` in `web/src/screens/InsightsScreen.tsx` |
| 2 | **Year in Pixels grid** | 12 columns × 31 rows (or 53 weeks × 7 days) of small squares, coloured by day score, empty days drawn as an outline. Tap a cell to open that day. | Daylio's most-shared feature and a whole competing app's entire premise ([Pixels](https://play.google.com/store/apps/details?id=ar.teovogel.yip)). It is also the cheapest way to make a year of writing feel like an achievement. | **S–M** | Series endpoint at `granularity=day` for a year | New `ui/charts/YearGrid.kt`, reachable from `ui/MonthlyCalendarScreen.kt` via a year/month toggle; `web/src/components/YearGrid.tsx` |
| 3 | **Feeling mix bar** | A single horizontal stacked bar per period, segments = feelings in backend order, coloured by valence, with the count list underneath (which we already draw). | Zero new data. `TotalsPanel` in `ui/MonthlyCalendarScreen.kt` already has `totalsByFeeling`; it just renders a list of rows. This is a two-hour change with a real visual payoff. | **S** | None | `ui/MonthlyCalendarScreen.kt` `TotalsPanel`; `web/src/screens/MonthlyCalendarScreen.tsx` |
| 4 | **Pattern strength chart on the card** | Two horizontal bars on each `PatternCard`: `presentCount/presentTotal` against `absentCount/absentTotal`, with the lift printed between them. | Our biggest edge over Daylio is that we hold the real numbers where they only show Low/Med/High ([Activity and Mood Statistics](https://daylio.net/faq/docs/daylio-faq/about/activity-and-mood-statistics/)). Right now we print those numbers as prose. Two bars make the argument instantly. | **S** | None — `Pattern` already carries all four counts and `lift` | `android/.../ui/PatternCard.kt`; `web/src/components/PatternCard.tsx` |
| 5 | **WhenPanel as a proper chart** | Keep the −1…+1 marker track, add a shared axis with tick labels and a light zero rule, and draw insufficient buckets as a hollow marker rather than a text apology. | The analysis is already better than Daylio's weekday bars; only the drawing is behind. | **S** | None | `android/.../ui/WhenPanel.kt`; `web/src/components/WhenPanel.tsx` |
| 6 | **Time-of-day heat strip** | A 24-cell (or 3-bucket) strip coloured by mean valence, from `created_at`. | Directly answers Daylio's most up-voted unmet request, "the lack of an hourly view" (5★, 201 votes, [Play](https://play.google.com/store/apps/details?id=net.daylio)). We already store `created_at` on every entry. | **S–M** | Extend `when.service.ts` with hourly buckets; reuse `MIN_BUCKET_ENTRIES` | `backend/src/insights/when.service.ts` + `ui/WhenPanel.kt` |
| 7 | **Topic frequency sparkline** | A small 12-week bar sparkline on each row of the Topics screen. | Makes "is this topic growing or fading" answerable at a glance, and gives the Topics screen a reason to be visited. | **M** | Series endpoint with a `topic_id` filter | `android/.../ui/TopicsScreen.kt`; `web/src/screens/TopicsScreen.tsx` |

**Accessibility is not optional here.** Every chart above must carry a `contentDescription` that
states the numbers, the way `DayCell` in `ui/MonthlyCalendarScreen.kt` already does. Daylio has an
admitted gap here ([Change font size and contrast](https://daylio.net/faq/docs/daylio-faq/tutorials/how-to-change-font-size-and-contrast/));
matching their charts while beating their accessibility is a cheap, real differentiator.

### 9.2 Quick wins outside charts

| # | What | Why | Effort | Where |
| --- | --- | --- | --- | --- |
| Q1 | **Search and filter entries** — `GET /entries?q=&from=&to=&feeling=&topic=` | We have no search at all; `GET /entries` takes a single `date`. Daylio users rate search highly ("search and filter entries by activities is especially useful", 5★ 15 votes, [Play](https://play.google.com/store/apps/details?id=net.daylio)). | **M** | `backend/src/entries/entries.controller.ts` + repository; new `ui/SearchScreen.kt` |
| Q2 | **Swipe between days** on the day view | The 146-vote request on Daylio: swipe "one day at a time" ([Play](https://play.google.com/store/apps/details?id=net.daylio)). We already have `DayEntriesScreen.kt`. | **S** | `android/.../ui/DayEntriesScreen.kt` |
| Q3 | **Configurable day boundary** | 235 up-votes on Daylio's version of this: a 2 a.m. entry should belong to the previous day ([Play](https://play.google.com/store/apps/details?id=net.daylio)). `entry_date` is assigned server-side, so this is one setting read where the date is computed — cheap now, painful after a year of data. | **S** | `backend/src/db/codecs.ts` (`todayLocal`), `diary_meta` table, `SettingsScreen` |
| Q4 | **Plain-text export (Markdown + JSON)** — roadmap item I7 | Daylio gates readable export behind Premium and the top 1★ complaint is exactly that: "to access all your entries in a reasonable format you need to pay" (29 votes, [Play](https://play.google.com/store/apps/details?id=net.daylio)). Free, complete export is a principled differentiator, not a feature. | **S** | New `backend/src/entries/export.controller.ts`; `SettingsScreen` |
| Q5 | **"On This Day"** | Daylio shipped it in Jul 2026 and made it a headline release note ([App Store version history](https://apps.apple.com/us/app/daylio-journal-mood-tracker/id1194023242)). For a long-form diary it is worth more than for a tag tracker. | **S** | `GET /entries` range + a card on `ui/TodayScreen.kt` |
| Q6 | **Configurable reminders** | We hardcode four alarms at 9/12/18/21. Daylio's own docs claim reminder users are far more consistent ([Setting up goals](https://daylio.net/faq/docs/daylio-faq/tutorials/setting-up-goals/)). | **S** | `android/.../notifications/ReminderScheduler.kt`, `ui/SettingsScreen.kt`, `data/SettingsStore.kt` |

### 9.3 Bigger bets

| # | What | Why | Effort | Notes |
| --- | --- | --- | --- | --- |
| B1 | **Lagged patterns — "the day after"** | Daylio's Previous/Same/Next Day comparison is the one analytical idea they have that we lack, and Bearable goes further with 1–7 day windows ([Bearable](https://bearable.app/support/howto/how-to-find-correlations/)). Our engine already builds a 2×2 table per topic; a lag-1 variant reuses it. | **L** | `backend/src/insights/patterns.service.ts` + `analysis.ts`; needs a new `kind` alongside `forward`/`inverse` in `domain/Pattern.kt`. Watch the multiple-comparisons problem: more lags means more spurious patterns, so `MIN_LIFT` may need to rise. |
| B2 | **Weekly digest** | Exist.io pushes a weekly summary rather than waiting for a visit ([exist.io](https://exist.io/)). Our Insights tab only pays off if opened. A local notification with one sentence and one sparkline changes that. | **M** | `notifications/`, plus a digest endpoint. Wording must stay deterministic, like every other pattern sentence. |
| B3 | **PIN / biometric lock on the Android client** | Daylio sells this and users value it. We keep a diary on a phone with no lock at all. | **M** | New `ui/LockScreen.kt` + `androidx.biometric`; a real gap, not a copy. |
| B4 | **Daylio CSV import** — roadmap item I8 | Every switcher arrives with years of Daylio data. Daylio's CSV export is free and documented ([daylio.net](https://daylio.net/)), so the migration path is open. This is the cheapest source of a non-empty diary, which is what makes our pattern engine work at all. | **M** | Already specified in `specs/research/roadmap-detailed-spec.md` §I8; depends on I7. Get a real export first — the exact column set is **[unverified]**. |
| B5 | **Offline capture on Android** | The single biggest structural gap: Daylio works everywhere, we need the backend reachable. This conflicts with the current "no offline sync" constraint in `README.md`, so it is a constitution-level decision, not a feature. | **L** | Raise as a spec question before any code. |

### 9.4 Not worth copying

- **Goals, levels and achievements.** A large system that pulls the product toward habit tracking.
  Daylio's own users complain about mood and habits being welded together (3★, [Play](https://play.google.com/store/apps/details?id=net.daylio)).
  Our streaks, if we ever want them, should be about writing, not about tasks.
- **The 2000+ icon library and emoji packs.** This is Daylio's paywall, and it exists because their
  entry model needs tags. We extract topics from text; an icon grid would re-introduce the setup
  burden we deliberately removed (`specs/research/diff-existing-4-free-text-topics.md`).
- **Low/Medium/High confidence labels.** They hide the numbers. We already show the counts, and that
  is the better answer to the same problem.
- **Photos in entries.** Reviewers want them, but they carry storage, backup, format and crash
  problems — Daylio's own PDF export warns about exactly this
  ([PDF export](https://daylio.net/faq/docs/daylio-faq/tutorials/pdf-export/)). Not until the core
  is finished.
- **A five-point mood scale.** Their users say it is limiting (3★, 15 votes,
  [Play](https://play.google.com/store/apps/details?id=net.daylio)). Our vocabulary is the better
  design; the only thing to borrow is the **colour ramp** so a day can be drawn as one cell.

---

## 10. Confidence and gaps

**High confidence** — the feature list, the premium split, the chart inventory, the privacy and
backup model, the no-sync and no-web positions, and the store metrics. All come from pages Daylio or
the stores own, read on 2026-08-28.

**Medium confidence** — the review themes. The Google Play listing exposes reviews sorted by
helpfulness and recency; I read roughly 580 unique English reviews from it. That is a real sample but
it is Google's ordering, not a random one, and helpful-vote counts favour older reviews. Treat the
themes as strong signals, not as measured proportions.

**Could not verify:**

- **Reddit.** r/Daylio, r/moodtracking, r/bipolar and r/quantifiedself were all unreachable from this
  environment — reddit.com is blocked to both the fetch tool and the browser. Every user quotation
  here comes from an app-store listing instead. If Reddit evidence is needed, it must be gathered by
  hand.
- **Which Premium price maps to which term.** Both stores list prices without terms.
- **Widgets as an official feature.** Confirmed only by user reviews, not by Daylio's own pages.
- **Google Fit / Health Connect.** Apple Health is documented; no Android health integration is.
- **Exact free-tier numeric limits** (how many goals, moods, reminders, Important Days a free user
  gets). Daylio's premium page says "Unlimited" for each without naming the free ceiling.
- **The Daylio CSV column layout.** Needed before B4 can be specified. Get a real export file.
- **Whether the free tier includes any correlation view at all**, or only period charts. "Advanced
  Stats" is premium, but the boundary is not drawn anywhere Daylio publishes.

---

## 11. Review addendum (2026-08-28): monetization and the recommendation surface

**What this is**: a second-pass review of this document against two product constraints that the
research corpus (this file, `competitive-landscape.md`, `differentiator-opportunities.md`,
`improvement-opportunities.md`, `master-implementation-roadmap.md`) has so far ignored:

1. **The app must be monetizable.** Every existing doc — including §7's closing row, "Self-hosted,
   free — Us" — treats free self-hosting as the price position. That row describes today's
   deployment, not a business. Nothing in the repo says what a customer would pay for.
2. **The product definition is: a diary whose added value is inferred correlations between entries,
   shown to the user, with recommendations.** The correlation half is deeply specified. The
   **recommendation** half is named in the definition and designed almost nowhere.

The recommendations in §9 stand. This section adds what they miss.

### 11.1 What the category paywalls — the monetization evidence

Every paying competitor in this space charges for the same thing: **insight depth, not capture.**

| Product | Price | Free tier | Paid tier | Source |
| --- | --- | --- | --- | --- |
| **Daylio** | subscription, users report ~$20–25/yr (§4) | All capture, basic charts, monthly/yearly reports | "Advanced Stats" — the per-activity correlation deep dive (§3.2), PDF export, unlimited moods | [Premium features](https://daylio.net/faq/docs/daylio-faq/about/daylio-premium-features/) |
| **Bearable** | $6.99/mo or $34.99/yr | Unlimited tracking of everything; trends and comparison graph **for the past 30 days**; a **limited number of Goals and Experiments** | "The Impacts tab (to view correlation reports)", "Correlations grid", "the option to view 60, 90, and 365 days of data in your reports", **unlimited custom Experiments** | [Free vs Premium](https://bearable.app/support/common-questions/bearable-free-vs-premium-features/) |
| **Rosebud** | Premium listed at $9.99/mo in Jan 2026 (secondary; rosebud.app itself listed $12.99/mo in 2026-08 — exact current price **[unverified]**) | Basic journaling | Advanced voice transcription, personality insights, **long-term memory, weekly reports** | [rosebud.app](https://www.rosebud.app/), [SaaSworthy](https://www.saasworthy.com/product/rosebud-app) (secondary) |
| **Mindsera** | $14.99/mo or $129/yr | — | Emotion analysis, recurring-topic detection, chat with journal | [App Store](https://apps.apple.com/us/app/mindsera-daily-ai-journaling/id6742319153) |
| **Exist.io** | $6.99/mo or $62.90/yr, no free tier | — | The whole product is the correlation engine | [exist.io](https://exist.io/) |

Three readings of this table:

- **The market has already taught users that correlation analysis is the paid layer.** Bearable's
  free/premium boundary is almost exactly our feature list: correlation reports, cross-factor
  comparison, history depth, and experiments are all premium. Our core competence *is* the
  monetizable layer of this category — we do not have to invent a paywall, only avoid breaking our
  own principles with it.
- **History depth is the standard knob.** Bearable gives 30 days free and sells 60/90/365. This
  maps cleanly onto our pattern-recency work (roadmap I3): current-window patterns free,
  full-history patterns, trajectories and lifecycles paid.
- **Experiments are commercially validated.** `differentiator-opportunities.md` §D proposed n-of-1
  experiments as a Tier-2 novelty. Bearable actually ships experiments and paywalls "unlimited
  custom Experiments" — proof that users pay for testing their own patterns. That idea should be
  promoted from "strategically interesting" to a monetization anchor.

Category benchmarks (secondary, RevenueCat's dataset of 75k+ subscription apps): Health & Fitness
subscription apps sell ~68% annual plans; higher-priced apps convert *better* than low-priced ones
(2.7% vs 1.5% D35 download-to-paid) and reach ~7× the year-one LTV per subscriber
([RevenueCat State of Subscription Apps](https://www.revenuecat.com/state-of-subscription-apps),
[Airbridge 2026 benchmarks](https://www.airbridge.io/en/blog/subscription-app-pricing-by-category-2026-benchmark),
both secondary). Practical consequence: an annual plan priced near Bearable/Daylio (~$25–35/yr) is a
defensible default; racing to the bottom is not supported by the data.

### 11.2 The paywall rules our own research dictates

Section 6 of this document is a list of what happens when a diary paywalls the wrong thing. Turned
around, it is a design spec:

1. **Never paywall writing, reading back, or export.** Daylio's top 1★ complaint cluster is
   entries locked behind Premium to read back (29 votes) and the "Contains ads" surprise. Q4
   (free plain-text export) stays free forever — it is the trust story that justifies the price of
   everything else.
2. **Paywall the derived layer, not the diary.** Free: entries, feelings, calendar, monthly
   summary, and patterns over the current window (e.g. last 30 days, matching Bearable's free
   boundary). Paid: full-history patterns, trajectory and lifecycle, lagged patterns (B1),
   confounder splits, experiments, the weekly digest (B2), the therapy report, Year in Review.
   The free tier must genuinely work — "Full usability without paying" is a top *praise* of Daylio
   (§5), and the funnel into paid is a user seeing a real pattern and wanting its history.
3. **Offer a one-time/lifetime purchase.** The single most up-voted review on Daylio's entire
   listing (351 votes) asks for exactly this, and another user offers "$20-70" for it (§6).
   Subscription-fatigue is the loudest sentiment in the category; being the product that sells a
   lifetime licence is a marketing asset competitors structurally resist.
4. **Hosting model — decided 2026-08-28 by the owner.** Customers will **not** self-host. One
   central backend, operated by the owner (local machine during development, cloud later), and
   **the clients are the paid product**. Consequences this decision creates:
   - **The backend must become multi-tenant.** Today it is single-user with password auth
     (`specs/005-public-auth`). Serving paying customers from one cloud backend needs accounts,
     per-user data isolation, and per-user pattern computation — a constitution-level change that
     precedes any monetization work.
   - **Enforcement cannot live only in the client.** If the API is open, a paid-client paywall is
     decorative. The backend must tie entitlements to accounts even though the *purchase* happens
     in the client (Play Billing / App Store), which means a receipt-validation path server-side.
   - **The privacy positioning must be rewritten, not dropped.** "Inference on hardware the user
     owns" (`diff-existing-3`) becomes false for customers. The honest replacement claim: *no
     third-party AI vendor ever sees your diary — inference runs on our own servers, not OpenAI's*
     — which still beats Rosebud (names OpenAI/Anthropic/Groq as processors) and Mindsera, but is
     a weaker claim than today's and the differentiator docs must be revised to match.
   - **Recurring server cost (storage + GPU inference) argues against a pure one-time app
     purchase.** A lifetime licence (§11.2 rule 3) stays valuable as an offer, but its price must
     cover indefinite inference cost, or the lifetime tier must cap the expensive operations.
   - **Client pricing must be coherent across web and Android.** If the web client stays free
     while the Android app is paid, the paid app competes with its own free sibling; the paywall
     boundary should be by *feature tier* (free vs premium insights, §11.2 rule 2) rather than by
     *platform*.

### 11.3 The recommendation surface — the missing half of the product definition

The stated product is *diary → correlations → recommendations*. Across the whole research corpus,
"recommendation" appears only implicitly (inverse patterns, "worth changing" direction labels).
These are the strong features that turn the pattern engine into a recommendation engine, in order:

| # | Feature | What it is | Why it is strong | Builds on |
| --- | --- | --- | --- | --- |
| R1 | **"Try more of this" cards** | Inverse patterns (roadmap I1) reframed as first-class recommendations: "On days without exercise, low mood is 3× more likely — evidence: 9 entries." Same counts, same evidence trail, phrased as an action. | The only recommendations in this category grounded in the user's own counted data. Daylio's paying users complain "the analysis remains up to me" (§6) — this is the direct answer. | I1 (needs A3 lift) |
| R2 | **Recommendation = claim + action + evidence, never generic advice** | A hard product rule: every recommendation must cite the user's own entries. [How We Feel](https://apps.apple.com/us/app/how-we-feel/id1562706384) ships a strategy library (Change Your Thinking / Move Your Body / Be Mindful / Reach Out) — good *presentation* model, wrong *content* model for us: their strategies are generic content; ours must be derived. A small curated strategy layer mapped to feelings could exist as optional paid content, but it must never replace the derived layer. | Keeps recommendations inside the "prove what it claims" thesis. An LLM-advice surface would put us in a losing fight with Rosebud/Mindsera (see §9.4 logic). | Nothing new |
| R3 | **Experiments — "test this recommendation"** | Promote n-of-1 experiments (differentiator doc §D) from Tier 2 to the paid tier's flagship: a strong pattern offers "test it — one week, and we compare the two periods with the same 2×2 arithmetic." | Bearable proves people pay for this (§11.1). And it is the only honest way to move a recommendation from correlation toward causation — which is the whole promise of the product definition. | A3, I3; large but self-contained |
| R4 | **Weekly digest as the delivery vehicle** | B2, upgraded: the digest is not a summary, it is where recommendations arrive — one pattern, one recommendation, one experiment result per week. | Rosebud's weekly report is the retention engine of a ~$10/mo product (§11.1). An Insights tab waits to be opened; a digest shows up. Deterministic wording, as B2 already requires. | B2 |

### 11.4 New strong features not in §9 or the sibling docs

| # | Feature | What it is | Why | Effort |
| --- | --- | --- | --- | --- |
| N1 | **Passive context factors** | Derive zero-capture-burden factors per entry from data we already hold: weekday/weekend, month/season, and (optionally, from a configured location) daylight length and weather. Feed them into the same 2×2 engine as topics: "anxious entries are 2.4× more likely on Sundays" or "low mood tracks short daylight — 14 of 18 December entries." | New correlation dimensions at zero cost to the two-tap flow. [Exist.io](https://exist.io/) correlates weather and calendar data in the cloud; no diary-space product does it from data the user owns. Distinct from the rejected wearables idea (§9.4 of `differentiator-opportunities.md`): no integrations, no devices — everything is computable from `entry_date` plus one optional lat/long. Weather needs an external API call, which touches the local-only principle: make it opt-in, fetch forecast-free historical data only, and label it. Daylio does not do weather **[absence, unverified]**; Moodistory captures only location ([moodistory.com](https://moodistory.com/)). | **M** — weekday/season is S and should ship with A3; weather is the M half |
| N2 | **Year in Review** | An annual generated report: pixels grid, top patterns of the year, biggest trajectory improvement, feeling-vocabulary growth. Exportable as an image. | Daylio ships "a wrapped at the end of the year" ([Choosing Therapy review](https://www.choosingtherapy.com/daylio-app-review/), secondary) and [Day One runs a Year in Review challenge](https://dayoneapp.com/journaling-challenge/year-in-review/) — it is the category's proven retention-and-sharing moment. Cheap on top of the §9.1 series endpoint and chart 2. For us it is also the once-a-year sales moment for the paid tier: the report *is* full-history insight. | **S–M** on top of §9.1 |
| N3 | **Writing streaks (diary streaks, not goal streaks)** | A single number: consecutive days with at least one entry, shown quietly on Today. No levels, no achievements — §9.4's rejection of Daylio's goal system stands. | Streaks are Daylio's most-praised retention mechanic ("1731 day streak", §5) and more entries is what makes our engine work at all. The scope guard: a streak about *writing* is a diary feature; a streak about *tasks* is not. | **S** |

### 11.5 Scope check — what survives "diary only + correlations + recommendations"

Everything in §9.1 (charts), §9.2 (Q1–Q6) and §9.3 survives the scope: charts visualise the
correlations, Q1–Q6 are diary UX, B1–B5 feed or protect the engine. The §9.4 rejections not only
stand but harden under monetization pressure: goals/gamification and an AI chat companion are the
two *easy* monetization routes in this category, and both would dissolve the one position we can
defend — a diary that proves its recommendations. If a proposed paid feature cannot cite the user's
own entries as evidence, it does not belong in this product, free or paid.

**Priority, combining §9 with this addendum**: (1) the §9.1 chart prerequisites and charts 1–4 —
the free tier must look like a product before anything is worth paying for; (2) R1 + N1's cheap
half (weekday/season factors) shipped with A3/I1 — the first real recommendations; (3) B2/R4
digest; (4) experiments R3 + history-depth entitlements as the paid tier's launch features;
(5) N2 Year in Review timed for December.

**Open items this addendum adds**: current Rosebud pricing **[unverified]**; whether Daylio
correlates any passive context (weather/weekday) in Advanced Stats **[unverified — §3.2's
inventory suggests weekday occurrence only]**; RevenueCat/Airbridge figures are vendor-published
aggregates, not audited data.

### 11.6 The core problem, and the first-30-days plan (added 2026-08-28)

**The customer-facing core problem**: people cannot connect what happens in their lives to how
they feel, and no existing tool gives them a trustworthy answer without making them do the
analysis themselves. The evidence is on both sides of the market: tracker users log for years and
still complain "the analysis remains up to me" and that charts "don't answer the actual question"
(§6); AI-journal users get answers but the answers are unverifiable LLM prose whose own vendors
warn about hallucination (`competitive-landscape.md` §2). The engine — lift, confirmed feelings,
evidence trail, withdrawal — is already the right machine for this problem.

**The company-facing core problem**: **time-to-first-trusted-pattern.** The product's value only
exists after enough entries accumulate; a ≥3-occurrence threshold with base-rate checks means
weeks of writing before the first pattern, and that empty period is where a diary-correlation app
dies. Daylio survives its empty period with two-tap logging and streaks; we ask for more effort
per entry, so ours is more expensive. **Metric**: median days (and entries) from first use to the
first surfaced pattern with lift — instrument it from day one, and treat SC-003 ("a meaningful
pattern within two weeks") as the SLA the product is built around.

The fix is a ladder — something honest at every rung before real patterns exist:

| Rung | When | What | Status |
| --- | --- | --- | --- |
| 1 | Day 0 | **Daylio/Bearable import in onboarding** (I8) — a switcher arrives with a warm engine; the biggest single lever on the metric. Plus **backdating** a few recent days at first use ("how was yesterday?"), which Daylio users demonstrably do (§2). | I8 specced; backdating new |
| 2 | Week 1 | **Passive context factors** (§11.4 N1, cheap half) — weekday/weekend/time-of-day observations exist from entry one. **Insight progress surface** — after saving, show the counting in flight: "topics tracked: 7 · closest to a pattern: *work* — 2 of 3 confirmed occurrences." Honest (shows counts, not conclusions), motivating (converts silence into anticipation), and shown after writing, like the echo, so it cannot bias the entry. | **New feature — no existing doc covers it** |
| 3 | Week 1+ | **Charts 2–3** (§9.1) so the diary is rewarding while patterns cook; **writing streak** (§11.4 N3). | Specced above |
| 4 | Week 2–4 | **First-pattern notification** — when the first pattern crosses the threshold, notify; do not leave the aha moment in an unvisited tab. It arrives with receipts (A1 + A3), because the first impression must be "I can check this." **Guided-question topic yield** (diff-existing-5 / SC-008) measured and tuned — every guided entry that yields no usable topic is a wasted day on the metric. | Notification **new**; rest specced |
| 5 | Month 2+ | Recommendations (§11.3 R1), digest (R4), experiments (R3) — the paid tier, sold only after the user has seen free proof on their own data. | §11.3 |

Every feature in the backlog should answer to one of the two core problems — *"tell me what
affects how I feel, and prove it"* or *"keep them writing until the proof exists"* — and anything
that answers neither is scope creep, however clever.

### 11.7 Mixed-valence entries — the pairing problem (added 2026-08-28)

**The problem (owner-identified, engine-correctness tier, same rank as A3/A4)**: topics and
feelings both attach to the *entry*, and the pattern engine counts co-occurrence at entry
granularity. An entry with a negative part (missed sport session → disappointed) and a positive
part (talked to parents → warm) therefore feeds **four** counts into the 2×2 tables — two of them
wrong (missed-sport×warm, parents×disappointed). Over months, mixed entries systematically dilute
true patterns and manufacture false ones, and the contamination propagates into every downstream
surface: the echo, trajectories, and any recommendation built on a poisoned pair.

**The fix — extend suggest→confirm to the pairing, never let the LLM decide silently:**

1. **Extraction**: the LLM proposes topic↔feeling *pairs* instead of two flat lists (this is
   aspect-based sentiment analysis, well within a small local model's ability on short diary
   text, especially once topic normalization A4 constrains the topic side).
2. **Confirmation**: the pairing is shown for confirmation only when it is ambiguous — i.e. only
   for mixed-valence entries. Single-feeling and single-valence entries have nothing to pair, so
   most entries see zero new friction. For mixed ones: grouped chips, one tap accepts, tap or
   drag re-pairs.
3. **Storage**: a topic↔feeling link carrying the same `suggested / confirmed / overridden`
   source field that feelings already carry.
4. **Engine rule**: only confirmed pairs count as pair-evidence. A mixed-valence entry whose
   pairing was never confirmed is excluded from cross-valence pairs (or labelled ambiguous) —
   less evidence, but clean evidence, the same trade the product already makes everywhere.

**Why the LLM must not own this**: the whole thesis is that only user-confirmed data is evidence
(`CONFIRMED_FEELING_SOURCES`). An LLM silently deciding which feeling belongs to which topic is
exactly the unaudited AI judgment the architecture excludes, hidden one level deeper; one
mis-paired hallucination would corrupt counts that *look* rigorous.

**Competitive note**: no product in the landscape does sub-entry attribution at all, let alone
user-confirmed attribution — Daylio/Bearable operate on whole days or entries of tags, and the AI
journals produce entry-level narrative. Confirmed pairing is another unoccupied differentiator,
and it sharpens the recommendation engine's input: "talking to your parents co-occurs with
feeling warm" becomes a claim about the pairing, not about the day.

**Sequencing**: fix before the pattern surface widens — with A3/A4 in roadmap Phase 2, so no new
number is printed on top of contaminated pairs.

---

## Sources

### Primary — Daylio

- [daylio.net](https://daylio.net/) — home page, feature list, claims
- [Activity and Mood Statistics](https://daylio.net/faq/docs/daylio-faq/about/activity-and-mood-statistics/) — the full chart inventory
- [Daylio Premium Features](https://daylio.net/faq/docs/daylio-faq/about/daylio-premium-features/) — the free/premium split
- [Create and manage moods](https://daylio.net/faq/docs/daylio-faq/tutorials/create-and-manage-moods/)
- [Add note to entry](https://daylio.net/faq/docs/daylio-faq/tutorials/add-note-to-entry/)
- [Adding and managing photos](https://daylio.net/faq/docs/daylio-faq/tutorials/adding-and-managing-photos/)
- [Setting up goals](https://daylio.net/faq/docs/daylio-faq/tutorials/setting-up-goals/)
- [PDF export](https://daylio.net/faq/docs/daylio-faq/tutorials/pdf-export/)
- [Backup options](https://daylio.net/faq/docs/daylio-faq/backup/backup-options/)
- [Missing entries](https://daylio.net/faq/docs/daylio-faq/issues/missing-entries/)
- [Can I use Daylio on multiple devices?](https://daylio.net/faq/can-i-use-daylio-on-multiple-devices/)
- [Writing entries on computer](https://daylio.net/faq/docs/daylio-faq/tutorials/writing-entries-on-computer/)
- [Apple Health troubleshooting](https://daylio.net/faq/docs/daylio-faq/issues/apple-health-troubleshooting/)
- [Change font size and contrast](https://daylio.net/faq/docs/daylio-faq/tutorials/how-to-change-font-size-and-contrast/)
- [Privacy policy](https://daylio.net/faq/privacy-policy/)
- [How to track moods](https://daylio.net/how-to-track-moods/)
- [Knowledge Base index](https://daylio.net/faq/)

### Primary — store listings (description, metrics, release notes, reviews)

- [Google Play: net.daylio](https://play.google.com/store/apps/details?id=net.daylio)
- [App Store: Daylio Journal – Mood Tracker (id1194023242)](https://apps.apple.com/us/app/daylio-journal-mood-tracker/id1194023242)

### Primary — adjacent products

- [Bearable: how to find correlations](https://bearable.app/support/howto/how-to-find-correlations/)
- [Bearable: free vs premium features](https://bearable.app/support/common-questions/bearable-free-vs-premium-features/) — §11 paywall evidence
- [Bearable: why subscribe to premium](https://bearable.app/why-subscribe-to-bearable-premium/)
- [exist.io](https://exist.io/)
- [moodistory.com](https://moodistory.com/)
- [rosebud.app](https://www.rosebud.app/)
- [Day One: Year in Review challenge](https://dayoneapp.com/journaling-challenge/year-in-review/)
- [App Store: How We Feel](https://apps.apple.com/us/app/how-we-feel/id1562706384)
- [Google Play: Pixels (ar.teovogel.yip)](https://play.google.com/store/apps/details?id=ar.teovogel.yip)

### Secondary — corroboration only

- [Wikipedia: Daylio](https://en.wikipedia.org/wiki/Daylio) — used only for the average-daily-mood
  bar chart, the three-photos-per-entry limit, and the Year in Pixels attribution to Camille of
  Passion Carnets.
- [RevenueCat: State of Subscription Apps](https://www.revenuecat.com/state-of-subscription-apps) —
  §11 category benchmarks (vendor-published aggregate)
- [Airbridge: subscription app pricing by category, 2026](https://www.airbridge.io/en/blog/subscription-app-pricing-by-category-2026-benchmark) —
  §11 pricing benchmarks
- [SaaSworthy: Rosebud](https://www.saasworthy.com/product/rosebud-app) — §11 Rosebud price point
  (Jan 2026)
- [Choosing Therapy: Daylio review](https://www.choosingtherapy.com/daylio-app-review/) — §11
  year-end "wrapped" mention only

### Internal

- `README.md`, `android/README.md`
- `backend/src/db/schema.ts`, `backend/src/insights/` (`constants.ts`, `patterns.service.ts`, `when.service.ts`, `echo.service.ts`), `backend/src/monthly-summary/monthly-summary.service.ts`, `backend/src/entries/entries.controller.ts`
- `android/app/src/main/kotlin/com/moodpatterndiary/app/ui/`, `.../domain/`, `android/app/build.gradle.kts`
- `web/src/screens/`, `web/package.json`
- `specs/research/competitive-landscape.md`, `specs/research/diff-existing-4-free-text-topics.md`, `specs/research/master-implementation-roadmap.md`, `specs/research/roadmap-detailed-spec.md`
