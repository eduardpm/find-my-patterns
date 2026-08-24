# Existing Differentiator Plan: Fully Local Inference on a User-Owned Backend

**Date:** 2026-08-24
**Part of:** `specs/research/differentiator-opportunities.md` — Existing Differentiator #3
**Other existing diff plans:** `diff-existing-1-auditable-patterns.md`, `diff-existing-2-confirmed-feelings.md`, `diff-existing-4-free-text-topics.md`, `diff-existing-5-guided-questions.md`
**New diff plans:** `diff-1-base-rate-patterns.md`, `diff-2-temporal-precedence.md`, `diff-3-emotional-trajectory.md`

---

## What it is today

Mood Pattern Diary runs its AI entirely on the user's own hardware. The feeling suggestion model is `qwen3:4b` through Ollama. Topic extraction runs through the same model. Voice transcription runs through `whisper.cpp` locally. Audio files are deleted immediately after transcription. The SQLite database sits in `data/diary.db` with owner-only permissions. No cloud AI vendor is named anywhere in the system because there isn't one.

The competitive review confirmed that this combination — self-hosted backend server + local AI + multiple thin clients (web and Android) — sits in an empty cell. Memex supports local Ollama but is a phone app with no server. Journiv and Nightlio are self-hosted but have zero AI. Moodiary has local NLP but no server. The only commercial product with fully on-device AI, Verity, is iOS-only, closed-source, and a capture tool with no pattern engine.

This differentiator is structurally uncopyable by the commercial competitors. Rosebud names OpenAI, Anthropic, and Groq in its privacy policy. Mindsera is a cloud SaaS. Daylio has no AI at all. None of them can pivot to "run on the user's machine" without rebuilding their entire infrastructure and business model. This is the moat.

But the moat is currently invisible. The README mentions it in deployment docs; the app itself never states it. A user could use MPD for months without realizing their diary text never left their machine.

---

## The business idea

**"Your diary, your machine, your rules" — make the privacy position the first thing every user learns, not the last.**

The local inference story is not a deployment detail. It's the product's constitutional guarantee. Every other AI journal asks the user to trust a company. MPD is the only one that doesn't need to be trusted — because there's no company server to trust. The model runs on hardware the user owns. The database is a file they can back up, inspect, and delete.

This needs to be stated prominently and proven, not inferred from documentation. The product should make the user *feel* that their data is local, not just tell them.

---

## The logic

### 1. The privacy position needs a one-line statement

Every screen in the app — web and Android — should carry a small, persistent indicator: "All data local · No cloud." This is not a settings toggle or a legal notice. It's a badge, like a SSL lock icon, that never disappears. The user should see it every time they open the app.

### 2. The user should be able to prove it to themselves

The strongest privacy claim is one the user can verify. Two features make this possible:

- **Data export (already partially built).** The backup command in the README creates a portable SQLite copy. The app should surface this: "Your diary lives in a file on your machine. Download it, inspect it, delete it — it's yours."
- **Network transparency.** The Android app already routes all requests through an OkHttp interceptor that the user configured (the Settings screen's host/port). The Settings screen should additionally show a connectivity log: "Last request: Today at 14:32 to 10.0.2.2:8000. No external requests made." This proves the app only talks to the user's own machine.

### 3. The limitations should be stated honestly

A local 4B model is not GPT-4. Topic extraction is less precise, feeling suggestions are less nuanced, and the model cannot hold long conversations about journal entries. The product should say this directly: "Your diary uses a small local AI model (qwen3:4b through Ollama). It's private but not as smart as cloud AI. You can upgrade to a larger model if your hardware supports it."

This turns a weakness into integrity. The user knows what they're trading off — privacy for capability — and they chose privacy. Rosebud and Mindsera can't make this offer because they can't show you the model.

### 4. The upgrade path should be documented

Some users have powerful hardware and want better AI. The product should document exactly which models work (any Ollama-compatible model the user installs) and how to switch: "Change `OLLAMA_MODEL` in your `.env` to `llama3.1:8b` or `mistral:7b` and restart the worker." This is not a feature to build — it's a sentence to write in the README and the Settings screen. But it communicates that the user controls the AI, not the other way around.

### 5. Voice transcription deserves its own trust story

The README describes the audio transcription pipeline in detail: ffmpeg → whisper.cpp → text, audio deleted, transcript reconstructed from Whisper's tokens to prevent model-added words. This is a genuinely stronger guarantee than Verity's (which is enforced by a closed model's prompt discipline, not by code). But it's buried in README prose.

The app should show a short explanation when the user records: "Your voice is transcribed on this machine. The audio is deleted immediately. Only the text is saved." Done. Two sentences. The user records with confidence.

---

## The value

### It's the only claim competitors cannot copy

Rosebud could add a confirmation step. Mindsera could add an occurrence threshold. Bearable could add free-text mining. But none of them can become "runs on the user's machine" without abandoning their cloud infrastructure, their vendor contracts with OpenAI/Anthropic/Groq, and their subscription revenue model. This differentiator is a function of architecture, not feature set.

### It's the precondition for every other differentiator

"Patterns you can audit" only works because the data and the computation are local. If the pattern engine ran in the cloud, the user couldn't verify the trail — they'd have to trust the vendor's logs. "Confirmed feelings" only works because the AI suggestion is private — if the suggestion went through a cloud model, the entry text would have to leave the machine first. The local inference story is the foundation the other differentiators stand on.

### It resonates with a growing privacy-conscious audience

The self-hosted community (r/selfhosted has 500k+ subscribers, Journiv has 1.2k GitHub stars) is actively looking for privacy-first alternatives to cloud SaaS. MPD is uniquely positioned as the only self-hosted diary with AI. Nightlio and Journiv have the self-hosted part but no AI; Memex has the AI but no server. MPD has both.

---

## How to make it stronger

1. **Privacy badge on every screen.** A small, persistent "Local · No Cloud" indicator in the app chrome. Web and Android. Never disappears.

2. **Network transparency panel in Settings.** Show every request the app has made, their destinations, and their timestamps. "All 47 requests today went to 192.168.1.42:8000. None went anywhere else." Proof, not promise.

3. **One-click data export.** A button in Settings that downloads the diary as a `.db` file (with a warning that it's plain-text and should be stored on encrypted media). The backup script already exists. Surface it in the UI.

4. **Model transparency.** Show which model is running, where it's installed, and how to change it. "Using qwen3:4b through Ollama at localhost:11434." If the worker is down, show "AI unavailable — your entries are saved, and you can select a feeling manually." The README already says this; the app should too.

5. **Trust story for voice.** The two-sentence explanation shown when recording: audio deleted after transcription, text saved, model cannot add words. Visible once, dismissible, stored in Settings for reference.

---

## How to leverage it better

### In the README and marketing

Lead with the one-line statement: "Mood Pattern Diary is a private diary that finds patterns in your writing — entirely on your machine, with no cloud, no account, and no AI vendor." Not "self-hosted journal with pattern detection." The privacy position is the headline; the features are the body.

### Against specific competitors

- "Rosebud processes your entries through OpenAI, Anthropic, and Groq. We process them through a model running on your machine, and the text never leaves it."
- "Mindsera is a cloud SaaS at $14.99/month. We're free, open-source, and run on hardware you own."
- "Daylio keeps data on your phone. We keep it on a server you control, with AI that runs there too — no cloud anywhere in the chain."

### In the product itself

The onboarding should state the privacy position before anything else. First screen: "Your diary stays on your machine. The AI runs locally. No cloud. No account. No vendor." Then the guided entry flow begins. The user should know what they're getting into before they write a single word.

---

## What this differentiator does NOT do

- It does not make the AI as good as cloud models. The trade-off is real and should be stated honestly. The mitigation is model upgradeability — the user can install a larger model.
- It does not make the app easier to set up. Self-hosting requires technical comfort (Docker, port configuration, Ollama installation). The README and deployment docs need to minimize friction, but the audience self-selects for people who can handle it.
- It is not "offline." The Android app needs LAN connectivity to reach the backend. The server needs connectivity to run Ollama. This is local-network, not offline.