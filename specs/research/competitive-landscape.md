# Competitive Landscape: Mood Pattern Diary

**Researched**: 2026-08-24
**Scope**: market research, not a feature. Feature-scoped Phase 0 notes live at
`specs/<NNN-feature>/research.md`; this document is not tied to one feature, so it sits in a
sibling `specs/research/` directory instead.
**Evidence rule**: every claim below links to the product's own website, help centre, app-store
listing, or repository. Secondary write-ups were used only to discover candidate names. Anything
that could not be confirmed against a first-party page is labelled **[unverified]**.

---

## Executive summary — does this already exist?

**Partly. No single shipping product does what this app does, but almost every individual piece of
it ships somewhere already, and two of the five candidate differentiators are already occupied.**

- **Topic → feeling correlation with an occurrence threshold**: exists, and is mature. Both
  [Daylio](https://daylio.net/faq/activity-and-mood-statistics/) and
  [Bearable](https://bearable.app/support/howto/how-to-find-correlations/) compute it, Bearable with
  an explicit minimum of three days with and three days without a factor. Neither derives the topic
  from free text — the user must pre-define the trackable item. That gap is real.
- **Free text mined into topics automatically**: exists in cloud AI journals.
  [Mindsera](https://help.mindsera.com/deep-analysis) does "recurring topics detection" and emotion
  analysis; [Rosebud](https://help.rosebud.app/ai-analysis/auto-tagging) auto-tags moods,
  relationships and life themes from every entry. Neither documents a threshold, and Mindsera's own
  help page presents topics and emotions as **separate** analyses rather than as paired
  co-occurrences.
- **Fully local inference on a backend the user owns**: rare but not unique.
  [Memex](https://github.com/memex-lab/memex) is an open-source local-first AI journal that can run
  against a local Ollama model, and it does auto-tagging, entity extraction and insight cards.
- **Word-faithful voice transcription**: **already claimed by a shipping product.**
  [Verity: AI Voice Journal](https://apps.apple.com/ph/app/verity-ai-voice-journal/id6792884283)
  runs transcription and AI entirely on-device and states its cleanup "never adds anything you
  didn't say", keeping the verbatim transcript underneath. This differentiator is occupied.
- **Guided questions as pattern-detection input**: guided prompts are everywhere
  ([Stoic](https://www.getstoic.com/), [Rosebud](https://www.rosebud.app/),
  [Day One](https://apps.apple.com/us/app/day-one-journal/id1044867788),
  [Mindsera](https://apps.apple.com/us/app/mindsera-daily-ai-journaling/id6742319153)), but every
  one of them is documented as a *reflection* device. No product found frames its question set as
  engineered input to a correlation engine.

**The unoccupied combination** is: free-text topic extraction (no pre-defined tracker fields)
→ paired with a *user-confirmed* feeling → counted deterministically against a threshold →
withdrawn when evidence changes → computed entirely on hardware the user owns. Section 8 tests each
part.

---

## 1. Mainstream mood trackers and mood↔factor correlation apps

### Daylio

Entry model is deliberately non-textual: "You can create a daily entry in two taps – pick mood and
activities. We crunch data and display it in stats, charts, and correlations"
([daylio.net](https://daylio.net/)). Notes exist as a separate free-text field added "directly below
the activities and goals"
([help](https://daylio.net/faq/docs/daylio-faq/tutorials/add-note-to-entry/)).

Its correlation feature is "Influence on Mood", which the help centre calls its crown-jewel
statistic. It compares mood on entries **with** an activity against entries **without** it, and also
across previous day / same day / next day, and rates each result Low / Medium / High confidence:
"Useful source data need many activity occurrences in different combinations. But we also need
entries without this activity to make a comparison"
([help](https://daylio.net/faq/activity-and-mood-statistics/)).

The same help page describes only activity tags as the input. It does not describe any analysis of
note text — the absence is consistent across the statistics documentation, but Daylio never states
"notes are excluded" in so many words, so treat the exclusion as strongly implied rather than
declared. **[partly unverified]**

Data stays on device: "Your data is stored only locally on your phone" and "We don't send your data
to our servers, so we don't have access to your entries"
([help](https://daylio.net/faq/docs/daylio-faq/about/how-secure-is-my-data/)). Optional backup goes
to the user's own Google Drive or iCloud. Platforms: iOS and Android
([daylio.net](https://daylio.net/)). Not open source, not self-hostable. No AI processing is
advertised anywhere on the site.

### Bearable

The closest competitor on *method*. Its purpose is stated as "Understand how your habits,
treatments, & lifestyle choices improve & worsen your health"
([bearable.app](https://bearable.app/)). "Factor is a term that we use to group together habits,
events, and actions that happen in your life" — the examples given are drinking coffee, going to
work, meditating, arguing with a partner
([help](https://bearable.app/support/tips/what-are-factors/)).

The workflow is explicitly user-configured: first "Make a decision about what aspect of health your
want to learn more about", then "determine the things that might be impacting your chosen metric"
([help](https://bearable.app/support/howto/how-to-use-bearable-to-discover-whats-improving-and-worsening-your-health/)).
Correlations require "at least 3 days _with_ a factor" and "3 at least days _without_ the same
factor" plus scores on those days, and Bearable "will take timing into account"
([help](https://bearable.app/support/howto/how-to-find-correlations/)).

Bearable is unusually honest about the weakness of the method, which matters for the counter-case in
Section 10. Its own troubleshooting page says correlations can mislead through reverse relationships
("pain medications might be taken on days when you have more pain"), confounding variables ("a third
variable that influences both the supposed cause and the supposed effect"), and outliers; and it
recommends "at least 7 days with, and 7 days without, a single Factor"
([help](https://bearable.app/support/troubleshooting/my-correlations-are-wrong-dont-make-sense/)).

Journaling exists as a tracked field ("Reflections and thoughts"), but no first-party page describes
free-text notes being fed into the correlation engine. **[unverified — no page found either way]**

Pricing: "Most of Bearable's features can be used for **free**", premium $6.99/month or $34.99/year
([pricing](https://bearable.app/pricing/)). iOS and Android. Cloud-backed, closed source.

### How We Feel

Free, non-profit, built with Yale's Center for Emotional Intelligence. Emotion check-ins with
HealthKit data "in order to spot patterns over time", and "all of your data is kept on your device
unless you opt-in to send an anonymized version of your check-ins to be used in research"
([App Store](https://apps.apple.com/us/app/how-we-feel/id1562706384)). No paid tier, no AI
processing of entries advertised, no topic extraction.

### Apple Health "State of Mind" and the Journal app

State of Mind logging is structured, not textual. The user logs "momentary emotions and daily moods",
picking between "How you feel right now" and "How you've felt overall today", then drags a valence
slider, then optionally taps "words that describe how you're feeling" and "words that describe
what's having the biggest impact on you"
([Apple Support](https://support.apple.com/guide/iphone/log-your-state-of-mind-iph6a6decb13/ios)).
Apple states the user can "learn how your state of mind may correlate with lifestyle factors like
exercise, sleep, time in daylight, and mindful minutes" — and Apple's product page describes
"Interactive charts provide insights into your state of mind, how it changes over time, and what
factors may influence it"
([apple.com/ios/health](https://www.apple.com/ios/health/)).

Crucially, the "biggest impact" list is a fixed vocabulary the user taps, not free text — so this is
the same pre-defined-tracker model as Daylio, shipped by the OS vendor and free.

The Journal app's suggestions are on-device: "Journaling Suggestions uses on-device processing to
intelligently group moments and events" and journal entries are end-to-end encrypted in iCloud with
2FA and a passcode
([Apple Legal](https://www.apple.com/legal/privacy/data/en/journaling-suggestions/),
[Apple Support](https://support.apple.com/guide/iphone/protect-your-journal-entries-iph9c59b1557/ios)).
Journal is a capture surface with State of Mind logging attached — no topic→feeling correlation of
its own.

### Moodnotes

CBT-framed mood tracking: "Track your mood and identify what triggers it", "Learn about 'traps' in
your thinking and how to avoid them", with statistics and mood insights behind a premium tier
([App Store](https://apps.apple.com/us/app/moodnotes-mood-tracker/id1019230398)). Notes are a
premium add-on to a mood entry rather than the primary content. The App Store privacy panel lists
data collected for "Developer's Advertising or Marketing" and used to track the user across apps —
a materially weaker privacy posture than Daylio or How We Feel.

### eMoods

Clinically oriented tracking for "Bipolar I and II disorders, Depression, PTSD, and Anxiety
Disorders", with "sleep, symptoms, and medications" logged "with just a few taps" and the promise
"See patterns in how different symptoms relate to one another"
([emoodtracker.com](https://emoodtracker.com/)). Free-text exists as "timestamped notes if things
are changing throughout the day". Runs on phone and desktop web, cloud account with SSL. Structured
fields, not text mining.

### Welltory and Gyroscope

Both are lifestyle-data correlation engines rather than diaries. Welltory works from 100+ biomarkers
and HRV, comparing data "against your personal baseline, not generic research norms", with no
free-text journaling described ([welltory.com](https://welltory.com/)). Gyroscope's mood tracker is a
30-second structured assessment and its pitch is "correlations to other parts of your life, and get
proactive suggestions from your Mind Coach" ([gyrosco.pe](https://gyrosco.pe/features/mind/)). Its
own feature page does not state where processing happens. **[unverified — hosting model]**

---

## 2. Journaling apps with AI reflection or auto-tagging

### Mindsera — closest on the "mine free text for topics" axis

Advertised as doing emotion analysis on "professor Plutchik's emotions model", plus "Recurring topics
detection, and personalized suggestions for improvement", "Chat with your journal", voice journaling
with auto-transcription, and handwritten journal scanning
([App Store](https://apps.apple.com/us/app/mindsera-daily-ai-journaling/id6742319153)).

The important detail for this project is *how* those two analyses relate. Mindsera's own help page
describes them as two separate panels: emotional analysis "Shows the emotions present in your journal
and how often they appear, based on Plutchik's emotions framework", and recurring topics "Highlights
themes that appear frequently across your journal over time"
([help.mindsera.com](https://help.mindsera.com/deep-analysis)). No documented pairing of a specific
topic with a specific emotion, no occurrence threshold, no stated statistical method. The user is
left to connect the two panels.

Pricing: Genius $14.99/month or $129.00/year. The App Store privacy panel lists contact info, user
content, location, identifiers, usage data and sensitive info as linked to the user, alongside the
developer's claim "Data never used to train or improve AI models"
([App Store](https://apps.apple.com/us/app/mindsera-daily-ai-journaling/id6742319153)). Cloud SaaS,
closed source. The main site returned HTTP 403 to automated fetching, so all Mindsera facts here come
from its App Store listing and its help centre. **[main marketing site unverified]**

### Rosebud

Free-text journal with an AI layer: "Process your emotions, spot patterns and uncover new insights",
"Uncover your patterns" via weekly reports, voice journaling, and guided prompts
([rosebud.app](https://www.rosebud.app/)). Auto-tagging runs on every entry and "can track your mood,
relationships, and life themes over time", but those tags "aren't currently searchable, yet"
([help](https://help.rosebud.app/ai-analysis/auto-tagging)). Insights are LLM narrative, not counted
evidence — and Rosebud says so, warning about "AI hallucinations" and admitting "Rosebud doesn't have
a great sense of time, which can sometimes lead to inaccuracies when referencing dates"
([help](https://help.rosebud.app/getting-started/rosebud's-limitations)).

Data lives on Google Firestore, and entries are processed by "OpenAI, Anthropic, and Groq" under
Zero Data Retention agreements
([privacy policy](https://help.rosebud.app/about-us/privacy-policy)). Pricing: free tier, Bloom at
$12.99/month or $107.99/year ([rosebud.app](https://www.rosebud.app/)).

### Day One

The incumbent general-purpose journal. "End-to-end encryption, which is a fancy way of saying your
entries are 100% private", daily prompts, customisable templates, cross-platform Apple apps; Silver
$8.99/month or $49.99/year, Gold $74.99
([App Store](https://apps.apple.com/us/app/day-one-journal/id1044867788)). Gold adds "Daily Chat,
entry summaries, smart title suggestions". Day One's AI guides state that Daily Chat sends messages
and accumulated memories to an AI provider, that content is not used to train models, and that some
features (Go Deeper Prompts, Title Suggestions, Entry Highlights) can run on-device via Apple
Intelligence ([dayoneapp.com AI guides](https://dayoneapp.com/guides/ai-features/ai-features/),
[Daily Chat](https://dayoneapp.com/guides/ai-features/daily-chat/)). Those pages return HTTP 403 to
automated fetching; the wording above was read from the pages' own text as surfaced in search rather
than from a direct fetch. **[partly unverified]** No mood tracking or topic→feeling correlation is
advertised.

### Stoic

"Monitor your progress and find out what shapes your mood over time", expert-curated guided prompts,
meditation and breathing, "Personalize your journals with AI", on iOS, iPadOS, macOS, watchOS,
Android and web. Claims "The journals are securely stored on your devices, and safely backed to
ensure they're never lost" ([getstoic.com](https://www.getstoic.com/)). Prompts are reflection
devices; no documented correlation engine.

### Reflectly

Describes itself as "a journal utilizing artificial intelligence to help you structure and reflect
upon your daily thoughts and problems", iOS and Android
([reflectlyapp.com](https://reflectlyapp.com/)). The landing page carries no feature, pricing, or
data-handling detail, so nothing further can be verified first-party. **[unverified]**

### Dabble Me

Email-driven journaling with prompts and "Blasts from the Past". PRO is "$4 /month or $40/year" and
adds an "Optional AI connector for ChatGPT and Claude" where the user must "approve access, and
nothing runs until you connect". Privacy claim: entries "can't be shared, posted, fed into AI models,
or made public in any way" ([dabble.me](https://dabble.me/)). No mood model, no correlation, hosted
service.

### Jour

No live first-party site was found during this research. Treat as discontinued or renamed.
**[unverified]**

---

## 3. Correlation / n-of-1 self-experiment tools

### Exist.io

The most statistically explicit of the commercial tools. "By combining manual tracking with automatic
syncing from other services, we can help you understand and optimise your behaviour", with 20+
integrations, built-in mood tracking, and custom data points entered "as a quantity, time period,
scale from 1–9, percentage, or time of day" ([exist.io](https://exist.io/)). Pricing "$6.99 / month
USD or $62.90 / year".

Correlations are attribute-to-attribute: they describe when "the values of one attribute increase or
decrease, the values of another attribute usually increase or decrease as well", reported with a
strength and a five-star confidence rating, with the caveat "Correlations can't determine the cause
of the relationship" ([knowledge base](https://kb.exist.io/article/37-what-are-correlations)). Exist
also exposes correlations through a documented API
([developer.exist.io](https://developer.exist.io/reference/correlations/)).

The input is numeric attributes and tags — the knowledge-base article makes no claim about analysing
free text. **[partly unverified — absence rather than denial]** Cloud service, closed source.

### Zenobase

Still reachable at [zenobase.com](https://zenobase.com/), but the homepage returned only a title to
automated fetching, so no feature, pricing, or status claim can be sourced first-party here.
**[unverified]**

### Obsidian / Logseq plugin workflows

The self-assembled route. [obsidian-mood-tracker](https://github.com/dartungar/obsidian-mood-tracker)
(MIT, 125 stars) stores entries "in your vault, in plain JSON", supports customisable mood ratings
and emotion labels, notes on entries, embeddable stats blocks, and writing entries into daily notes.
It computes averages and most-frequent moods — not topic→feeling correlation. Anything beyond that is
hand-built with Dataview queries by the user.

---

## 4. Open-source and self-hostable options

| Project | What it is | Correlation? | Local AI? |
|---|---|---|---|
| [Memex](https://github.com/memex-lab/memex) (GPL-3.0, 690★) | "open-source, local-first AI journal for iOS and Android"; capture fragments as text, photos, voice; multi-agent AI builds timeline cards | Insight cards with trend/bar/radar charts and narrative summaries; auto-tagging, entity extraction, cross-reference linking. No documented threshold or topic↔feeling pairing | Yes — Ollama is listed as a supported provider ("OpenAI-compatible (local)"), alongside 15 cloud providers. Default path is bring-your-own cloud key |
| [Journiv](https://github.com/journiv/journiv-app) (1.2k★, beta) | "self-hosted private journal … mood tracking, prompt-based journaling, media uploads, analytics" | "Writing Patterns", "Mood Trends", "Journal Analytics" — visualise "your emotional journey over time with interactive charts" ([docs](https://www.journiv.com/docs)). No mood↔topic correlation documented | No AI features documented |
| [Nightlio](https://github.com/shirsakm/nightlio) (AGPL-3.0, 242★) | Explicit Daylio clone: "Privacy-first mood tracker and daily journal, designed for effortless self-hosting" | "Log your daily mood on a simple 5-point scale and use customizable tags … to discover what influences your state of mind"; calendar, average mood, streaks. Tags are user-defined | No |
| [Moodiary](https://github.com/ZhuJHua/moodiary) (AGPL-3.0, 1.9k★) | Cross-platform Flutter diary with markdown/rich text, media, LAN sync and WebDAV backup | Sentiment analysis via an "Intelligent assistant"; no correlation engine documented | Yes — advertises "Local Natural Language Processing (NLP): A more secure intelligent assistant", plus optional third-party models |
| [MoodSnap](https://github.com/drpeterrohde/MoodSnap) (GPL-3.0, iOS) | Mood diary by an academic with bipolar disorder | "Statistical tools for correlating activities, symptoms and mood levels", plus a volatility metric | No; on-device, no AI |
| [samihsoylu/journal](https://github.com/samihsoylu/journal) (GPL-3.0) | "privacy first, self-hosted digital log book" with AES-256 encryption and entry templates | None | No |
| [Tempo](https://github.com/agateblue/tempo) (AGPL-3.0, archived 2024) | Offline-first PWA diary and mood tracker; "The data entered in Tempo never leaves your device" | Mood over time; no correlation engine | No |
| [Pixy](https://github.com/mrzmyr/pixy-mood-tracker-app) (MIT) | One-pixel-a-day mood tracker | Minimal | No. **Unmaintained** — "This project is no longer actively maintained" |

Smaller local-LLM journals also exist but are early-stage single-developer projects:
[Gemi](https://github.com/perpetual-s/Gemi) (macOS, local Gemma via Ollama),
[cbt-assistant](https://github.com/KazKozDev/cbt-assistant) (local CBT journal with mood and sleep
tracking on Ollama), [momento](https://github.com/Pita/momento) ("For private self hosting w/
ollama"). None has meaningful traction; all are cited to show the idea is being attempted, not that
it is solved.

---

## 5. Voice-first and local-AI journaling

This is where a candidate differentiator is already taken.

**[Verity: AI Voice Journal](https://apps.apple.com/ph/app/verity-ai-voice-journal/id6792884283)**
states: "Transcription and AI run entirely on your iPhone. There is no server, no account, no ads, no
analytics." Its cleanup step "tidies filler and false starts into calm prose, and never adds anything
you didn't say", with the verbatim transcript kept as the record beneath it. Audio handling matches
this project's too — "Audio is deleted the moment it becomes text". It also does mood tracking and
theme tagging to "watch patterns surface over weeks". Requires iOS 26+; entry-shaping is best on
iPhone 15 Pro or later with Apple Intelligence, and other iPhones preserve "exact spoken words". Free
core with a Verity Plus subscription.

Verity's guarantee is a *claim about intent* enforced by a closed on-device model. This project's
guarantee is structural — the transcript is reconstructed from Whisper's own token sequence, so a
model-added word cannot survive (README, "Local audio transcription"). That is a stronger promise,
but it is a difference of degree that a user cannot see from the outside, and Verity got to the
positioning first.

Elsewhere, voice input is common but the transcript is not treated as sacred:
[Rosebud](https://www.rosebud.app/) offers voice journaling,
[Mindsera](https://apps.apple.com/us/app/mindsera-daily-ai-journaling/id6742319153) offers "voice
journaling with auto-transcription", and [Daylio](https://daylio.net/) lets users "record voice
memos" without transcribing them into analysable text.

---

## 6. Comparison table

Legend: **Yes** = documented on a first-party page; **No** = no such feature documented;
**?** = could not be verified either way.

| Product | Free-text topic mining | Topic→feeling correlation | Threshold / evidence rule | User confirms the feeling | Data location | AI processing | Platforms | Price | OSS / self-host |
|---|---|---|---|---|---|---|---|---|---|
| **Mood Pattern Diary** (this) | Yes | Yes, counted | Yes, ≥3, withdrawn on edit/delete | Yes (suggest → confirm/override) | User's own machine, SQLite | Local only (Ollama + whisper.cpp) | Web + Android | Self-hosted | Yes |
| [Daylio](https://daylio.net/) | No — pre-defined activity icons | Yes ("Influence on Mood") | Confidence Low/Med/High, no stated minimum | Manual mood pick | On device + own cloud backup | None advertised | iOS, Android | Free + premium | No |
| [Bearable](https://bearable.app/) | No — user-defined Factors | Yes | ≥3 days with / ≥3 without; 7+7 recommended | Manual scores | Cloud | None advertised | iOS, Android | Free + $6.99/mo | No |
| [Apple State of Mind](https://support.apple.com/guide/iphone/log-your-state-of-mind-iph6a6decb13/ios) | No — fixed word lists | Associations with lifestyle factors | Not documented | Manual slider + labels | Device, E2E in iCloud | On-device (Journaling Suggestions) | iOS, iPadOS, watchOS | Free | No |
| [How We Feel](https://apps.apple.com/us/app/how-we-feel/id1562706384) | No | HealthKit trends only | No | Manual | On device | None advertised | iOS | Free | No |
| [Moodnotes](https://apps.apple.com/us/app/moodnotes-mood-tracker/id1019230398) | No | Stats + insights (premium) | Not documented | Manual + face scan | Cloud/iCloud | None advertised | iOS | Freemium | No |
| [eMoods](https://emoodtracker.com/) | No | Symptom relationships | Not documented | Manual | Cloud account | None advertised | Phone + web | Free tier | No |
| [Exist.io](https://exist.io/) | No — attributes and tags | Yes, statistical, 5-star confidence | 3 weeks of data per attribute | Manual mood entry | Cloud | None advertised | iOS, Android, web | $6.99/mo | No |
| [Welltory](https://welltory.com/) | No | Yes, biomarker-driven | Personal baseline | n/a | Cloud | Undisclosed | Mobile | Freemium | No |
| [Gyroscope](https://gyrosco.pe/features/mind/) | No | Yes | Not documented | 30-second assessment | ? | "Mind Coach" | iOS | Paid | No |
| [Mindsera](https://help.mindsera.com/deep-analysis) | **Yes** | **No** — topics and emotions shown separately | No | No — AI infers | Cloud | Cloud | iOS, Android, web | $14.99/mo | No |
| [Rosebud](https://www.rosebud.app/) | **Yes** (auto-tagging) | Narrative only, LLM-generated | No | No | Google Firestore | OpenAI / Anthropic / Groq | iOS, Android, web | Free + $12.99/mo | No |
| [Day One](https://apps.apple.com/us/app/day-one-journal/id1044867788) | No | No | n/a | n/a | Cloud, E2E encrypted | Cloud + some Apple Intelligence | Apple, Android, web | $8.99–$74.99 | No |
| [Stoic](https://www.getstoic.com/) | No | "what shapes your mood" (undocumented) | No | Manual | On device + backup | Cloud AI | Apple, Android, web | Free | No |
| [Verity](https://apps.apple.com/ph/app/verity-ai-voice-journal/id6792884283) | Theme tagging | Patterns over weeks (undocumented) | No | Mood log | On device | **Fully on-device** | iOS 26+ | Freemium | No |
| [Memex](https://github.com/memex-lab/memex) | **Yes** (auto-tag, entity extraction) | Insight cards, no counted pairing | No | No | On device | **Ollama supported**, cloud default | iOS, Android | Free (GPL-3.0) | Yes (app, not a server) |
| [Journiv](https://github.com/journiv/journiv-app) | No | No | n/a | Manual mood | **Own server** | None | Web (Docker) | Free | Yes |
| [Nightlio](https://github.com/shirsakm/nightlio) | No — custom tags | Tag/mood views | No | Manual 5-point | **Own server**, SQLite | None | Web (Docker) | Free | Yes |
| [MoodSnap](https://github.com/drpeterrohde/MoodSnap) | No | **Yes, statistical** | Not documented | Manual | On device | None | iOS | Free | Yes |
| [Moodiary](https://github.com/ZhuJHua/moodiary) | Sentiment analysis | No | n/a | Manual | On device + WebDAV | **Local NLP** + optional cloud | Android, iOS, desktop | Free | Yes |

---

## 7. The nearest competitors

### 1. Bearable — nearest on the pattern engine

**Overlaps**: the whole premise of "find out what makes you feel worse or better", a real
occurrence-based rule (≥3 with, ≥3 without), timing awareness, cross-platform mobile clients, an
honest treatment of correlation-vs-causation.

**Does not overlap**: the user must decide in advance what to track — the workflow literally begins
with "Make a decision about what aspect of health your want to learn more about"
([help](https://bearable.app/support/howto/how-to-use-bearable-to-discover-whats-improving-and-worsening-your-health/)).
Free text is a field, not a signal source. No AI at all, local or cloud. Cloud-hosted, closed source,
no self-hosting. No guided question flow, no voice transcription.

### 2. Daylio — nearest on the everyday product

**Overlaps**: activity↔mood influence statistics with a confidence rating, monthly/calendar views,
multiple entries per day, on-device data with no vendor server, reminders, a two-tap capture flow
that sets the bar Principle VI is aiming at.

**Does not overlap**: activities are icons the user picks; notes are a parked text field, not
analysed. No AI. No self-hosted backend. No voice transcription. No guided questions.

### 3. Mindsera — nearest on free-text topic extraction

**Overlaps**: the only mainstream product found that pulls recurring topics *and* emotions out of raw
writing, plus voice journaling with transcription, guided frameworks, and a "chat with your journal"
retrieval layer.

**Does not overlap**: its own help page keeps topics and emotions in separate panels — no documented
pairing, no threshold, no withdrawal rule ([help](https://help.mindsera.com/deep-analysis)). The
feeling is inferred, never confirmed by the user. Everything runs in the cloud at $14.99/month, with
an App Store privacy panel listing user content, location and sensitive info as linked to the user.

### 4. Memex — nearest on architecture

**Overlaps**: open-source, local-first, SQLite on the user's device, auto-tagging and entity
extraction from fragments including voice, insight cards with charts, explicit Ollama support, and
markdown export with "Zero vendor lock-in" ([README](https://github.com/memex-lab/memex)).

**Does not overlap**: it is a phone app with local storage, not a self-hosted backend with thin
clients — there is no server the user runs, so no second client sharing one truth. Insights are
agent-generated narrative, with no counted evidence rule and no withdrawal on edit. Its practical
default is a cloud provider key; local Ollama is one row in a 16-provider table. No confirmed-feeling
step, no monthly feeling calendar, no reminder schedule.

### 5. Verity — nearest on voice

**Overlaps**: fully on-device transcription and AI, immediate audio deletion, a stated no-added-words
guarantee, mood logging and theme tagging.

**Does not overlap**: iOS 26+ only, closed source, no server, no guided questions, no counted
topic→feeling patterns, no calendar view. It is a capture tool, not a pattern engine.

---

## 8. Testing the candidate differentiators

### (a) Free text mined for topics, versus pre-defined trackable items — **holds, with a caveat**

**Verified.** Daylio's statistics documentation describes activity tags as the unit of analysis
([help](https://daylio.net/faq/activity-and-mood-statistics/)). Bearable's own how-to starts by
telling the user to decide what to track
([help](https://bearable.app/support/howto/how-to-use-bearable-to-discover-whats-improving-and-worsening-your-health/)).
Exist.io's inputs are numeric attributes and tags ([exist.io](https://exist.io/)). Apple's "biggest
impact" list is a fixed word set
([Apple Support](https://support.apple.com/guide/iphone/log-your-state-of-mind-iph6a6decb13/ios)).
Nightlio uses "customizable tags" ([README](https://github.com/shirsakm/nightlio)). The Daylio/
Bearable model is confirmed exactly as suspected.

**Caveat**: extraction from free text is *not* unoccupied — Mindsera and Rosebud both do it, and
Memex does it locally. What none of them does is *pair* the extracted topic with a feeling and count
the pairing. The differentiator is not "we read your text", it is "we read your text and then count".

### (b) Fully local inference on a self-hosted backend — **holds, narrowly**

**Verified.** Every commercial free-text analyser sends entries to a cloud model: Rosebud names
"OpenAI, Anthropic, and Groq" ([privacy policy](https://help.rosebud.app/about-us/privacy-policy));
Mindsera is a cloud SaaS. On the open-source side, Memex supports Ollama, and Moodiary advertises
"Local Natural Language Processing (NLP)" ([README](https://github.com/ZhuJHua/moodiary)) — so
"local AI journal" as a category exists.

What does not exist in anything found: local inference **plus a backend the user runs** that owns the
data and every calculation, with multiple thin clients over it. Journiv and Nightlio are self-hosted
but have no AI; Memex and Moodiary have local AI but no server. This project sits in the empty cell.

### (c) Word-faithful voice transcription — **already occupied**

**Do not build the positioning on this.**
[Verity](https://apps.apple.com/ph/app/verity-ai-voice-journal/id6792884283) ships the same promise
in plainer language — on-device only, "never adds anything you didn't say", verbatim transcript
retained, audio deleted at transcription. This project's reconstruction-from-Whisper-tokens approach
is genuinely stronger, because the guarantee is enforced by code rather than by prompt discipline —
but that is an engineering argument, not a market position, and the claim is no longer novel.

### (d) Guided questions as pattern-detection input — **holds, but is hard to prove to anyone**

**Verified as unoccupied in framing.** Every guided-prompt product found describes prompts as
reflection aids: Stoic's are "curated by experts" for depth
([getstoic.com](https://www.getstoic.com/)); Rosebud's are "thought provoking questions"
([rosebud.app](https://www.rosebud.app/)); Mindsera ships "50+ guided frameworks including CBT and
anxiety templates" ([App Store](https://apps.apple.com/us/app/mindsera-daily-ai-journaling/id6742319153));
Day One offers templates and daily prompts. None frames its question set as designed to yield
extractable topics, which is exactly what this project's FR-006 demands.

The honest weakness: this is invisible from the outside. A user cannot tell a
pattern-engineered question from a reflection prompt until months of data have accumulated. It
strengthens the product; it will not sell it on its own.

### (e) Conservative thresholds and withdrawal of patterns — **partly held, and the withdrawal half is genuinely novel**

**Threshold**: occupied. Bearable states its minimum plainly
([help](https://bearable.app/support/howto/how-to-find-correlations/)); Exist.io needs three weeks of
data per attribute ([kb](https://kb.exist.io/article/37-what-are-correlations)); Daylio rates
confidence Low/Medium/High ([help](https://daylio.net/faq/activity-and-mood-statistics/)). A ≥3
threshold is table stakes, not a differentiator.

**Withdrawal**: unoccupied. No first-party documentation was found for any product describing what
happens to a surfaced insight when its supporting entries are edited or deleted. In the LLM
journals this is structurally impossible — a weekly report is a generated artefact, not a live
recomputation. Rosebud even warns about hallucinations and date confusion
([help](https://help.rosebud.app/getting-started/rosebud's-limitations)). This project recomputes
from the database and withdraws unsupported claims, which is a real and defensible correctness
property.

**Confirmed feeling**: also unoccupied, and undersold above. Every AI journal infers the mood and
shows it; every tracker asks the user to pick it. Nothing found does *suggest → confirm or override*,
and nothing found treats only user-acted feelings as evidence
(`CONFIRMED_FEELING_SOURCES = ['confirmed', 'overridden']` in
`backend/src/insights/patterns.service.ts`). That is the cleanest unclaimed idea in the whole set.

---

## 9. Recommendation: what the differentiator should be

**Ranked, with what each would need.**

### 1. "Patterns you can audit" — counted evidence from free text, with confirmed feelings and withdrawal

The strongest position, because it is the only one that stacks three unoccupied properties into a
single sentence a user understands: *you just write; the app finds the recurring things; a pattern
only appears after three confirmed occurrences; and it disappears the moment the evidence does.*

It beats the trackers (they need you to name the thing first) and it beats the AI journals (their
insights are prose you cannot check). Both halves are already built and constitutionally protected by
Principle III.

**Needs**: every pattern must show its supporting entries, tappable, with the count. The Insights view
should state the rule in the UI ("3 of 3 entries mentioning takeaway"), and should visibly say when a
pattern was withdrawn and why. Right now the count exists in `PatternOut.occurrence_count` but the
evidence trail is not a product feature. Make it one.

### 2. "No cloud, no account, your machine" — local inference on a backend you own

Second because the audience is smaller but the differentiation is absolute, and because it is the
only claim in this list that competitors cannot copy without rebuilding their business. Rosebud's
own privacy policy names three AI vendors; this app names none.

**Needs**: nothing new — but it must be stated in one line at the top of the README and the app, not
inferred from the deployment docs. The Cloudflare Tunnel path is currently described as a security
configuration; it should be framed as *how you get your private diary on your phone without giving it
to anyone*.

### 3. Guided questions engineered for extraction

Real, invisible, and best positioned as *support* for #1 rather than as the headline. "The questions
are designed so the app can find your patterns" is a good second sentence, not a first one.

**Needs**: FR-006's research work should be written up so the design rationale exists in the repo,
and the question set should be measured against SC-008 (90% of guided entries yield a usable topic).
That number, if it holds, is the proof this claim needs.

### 4. Word-faithful voice — demote to a trust feature, not a differentiator

Keep it, document it, do not lead with it. Verity owns the phrasing already. Where it still earns its
place is as reinforcement of #2: *your voice never leaves the machine, and the model cannot put words
in your mouth.*

### Do not compete on

- **Capture speed and polish.** Daylio's two-tap entry is a decade of refinement and it is free.
  Principle VI keeps this app honest, but "nicer to write in than Daylio" is not a position.
- **Breadth of tracked data.** Welltory's 100+ biomarkers and Exist.io's 20+ integrations are
  category-defining and irrelevant to a single-user diary.
- **Conversational AI companionship.** Rosebud, Mindsera, Day One Gold and Memex all do this with far
  larger models than `qwen3:4b`. A local 4B model will lose that comparison every time.

---

## 10. Risks and the counter-case

**Bearable's correlation feature is better than a summary suggests, and its docs are more honest than
this project's.** It names reverse causation, confounders and outliers by name, and tells users to
"sense check your correlations"
([help](https://bearable.app/support/troubleshooting/my-correlations-are-wrong-dont-make-sense/)).
This project's threshold — three co-occurrences of a topic and a feeling, with no comparison against
entries *without* that topic — is **weaker evidence than Bearable's**, which requires both sides of
the comparison. A topic appearing in three "tired" entries proves nothing if the user is tired in
most entries. This is the single biggest correctness gap found in the whole review, and it is
directly at odds with the "patterns you can audit" position in §9.1. Consider a base-rate check
before shipping that claim.

**Free-text topic extraction is the hard part, and a 4B local model is the weak link.** Mindsera and
Rosebud do this with frontier models and still produce fuzzy output; Rosebud's own docs warn about
hallucination. Topic extraction quality determines whether patterns are meaningful, and it is the one
place where "local only" costs real capability. Mitigation: normalisation and a curated topic
vocabulary in deterministic code, so the model proposes and the backend decides.

**Threshold of 3 will surface noise.** Bearable recommends 7 with and 7 without
([help](https://bearable.app/support/howto/how-to-find-correlations/)); Exist.io wants three weeks
per attribute ([kb](https://kb.exist.io/article/37-what-are-correlations)). SC-003 promises a
meaningful pattern after two weeks — those two targets pull in opposite directions.

**Apple is a free, pre-installed competitor for the casual case.** State of Mind plus Journal covers
logging, on-device suggestions, E2E encryption and lifestyle-factor associations at zero cost
([apple.com/ios/health](https://www.apple.com/ios/health/)). This does not threaten a self-hosted
Android-and-web app, but it does mean the "just track my mood privately" market is gone.

**The self-hosted audience is small and already served on the tracker side.** Nightlio and Journiv
exist, are actively maintained, and ship with Docker. This project's edge over them is the pattern
engine and local inference — not self-hosting itself.

---

## Open questions and unverified items

- Whether Bearable analyses free-text "Reflections" in correlations — no first-party page found
  stating either position.
- Whether Daylio explicitly excludes note text from statistics — implied throughout the statistics
  documentation, never stated.
- Day One's AI internals — [dayoneapp.com](https://dayoneapp.com/guides/ai-features/ai-features/)
  returns HTTP 403 to automated fetching; wording was read from search-surfaced page text.
- Mindsera's main marketing site — [mindsera.com](https://mindsera.com/) returns HTTP 403; facts here
  come from its App Store listing and help centre only.
- Zenobase's current features, pricing and status — [zenobase.com](https://zenobase.com/) returned no
  fetchable content.
- Jour — no live first-party site found.
- Gyroscope's hosting and processing model — not stated on
  [its own feature page](https://gyrosco.pe/features/mind/).
- Reflectly's features, pricing and data handling — [reflectlyapp.com](https://reflectlyapp.com/)
  carries no detail.
