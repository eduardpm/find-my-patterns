# Mood Pattern Diary

A private diary for noticing correlations between recurring topics and confirmed feelings. One
NestJS backend owns the SQLite diary and every factual calculation; the React web app and Android
app are presentation clients over that same data. The backend runs on infrastructure we operate —
see [Privacy](#privacy) below — but you can also run every part of it yourself from source; see
"Start locally".

## Privacy

- **Where your data lives**: on infrastructure we operate — not on a third-party AI vendor's
  platform, and not something you have to self-host. (Running the project yourself from source
  keeps your data on whatever machine you deploy it to — see "Start locally" below.)
- **What processes it**: open models we run ourselves — `qwen3` through Ollama for feeling and
  topic inference, `whisper.cpp` for voice transcription — on our own hardware.
- **What never happens**: no third-party AI vendor — not OpenAI, not Anthropic, not Groq — ever
  sees your diary content. There is no analytics tracking on diary content, and entries are never
  used to train a model.
- **Export**: a full, free copy of your data is a permanent commitment, not a feature we intend to
  paywall. Today that means the `npm run backup` command (see "Protect the diary" below), run by
  whoever operates your backend, produces a complete, portable copy of the diary; a self-serve
  export button for hosted customers is planned but not yet built.

## Start locally

Use Node 20 or newer.

```sh
cd web && npm ci && npm run build
cd ../backend && npm ci && npm run build
npm run init-db                      # first run only
npm start                            # terminal 1: API/web server
cd backend && npm run start:worker   # terminal 2: local inference worker
```

Open <http://127.0.0.1:8000/app>. The safe default listens only on this computer. To use the Android
app over a trusted home LAN or VPN, start with `HOST=0.0.0.0 npm start`. Authentication is off for
local-only use. Never port-forward this service; the authenticated Cloudflare Tunnel configuration
below is the only supported public deployment.

### Local audio transcription

Each guided question in the web app can be answered with the microphone. The backend converts the
browser recording with `ffmpeg`, transcribes it with the open-source `whisper.cpp` CLI, and returns
editable text. The audio is deleted immediately; the transcript is stored as the question's normal
`answer_text` and is what the existing local Ollama feeling/topic analysis reads. Before returning
it, the local Qwen model restores punctuation and layout. Its output is used only as a formatting
stencil: the backend reconstructs the result from Whisper's original words, so a model-added,
removed, or corrected word cannot enter the saved transcript.

Guided composition starts with a server-owned draft UUID. Every typed or recorded question is saved
independently and idempotently under that UUID and question key. Audio uploads return immediately
with a short-lived transcription job; the browser polls it while Whisper runs. Refreshing the page
reopens the same unfinished backend draft, and feelings analysis runs only when it is finalized.

Install `ffmpeg` and `whisper.cpp`, download a whisper.cpp GGML model, then set these values in the
service environment (paths are examples):

```sh
WHISPER_COMMAND=/usr/local/bin/whisper-cli
WHISPER_MODEL_PATH=/var/lib/mood-pattern-diary/ggml-base.bin
WHISPER_LANGUAGE=auto
```

`WHISPER_LANGUAGE` may be an explicit language such as `en` or `nl` for faster, more reliable
recognition. Microphone capture requires HTTPS when the web app is opened from another machine;
`localhost` is the browser exception.

## Public access through Cloudflare Tunnel

First generate a password hash without putting the password in shell history:

```sh
cd backend
read -rsp 'Diary password: ' DIARY_AUTH_PASSWORD; echo
export DIARY_AUTH_PASSWORD
npm run build
npm run auth:hash-password
unset DIARY_AUTH_PASSWORD
```

Put the printed hash and your email in the service environment, then start the loopback-only origin:

```sh
AUTH_ENABLED=true \
AUTH_EMAIL=you@example.com \
AUTH_PASSWORD_HASH='scrypt$…' \
AUTH_PUBLIC_HOSTNAME=diary.kongming.org \
HOST=127.0.0.1 \
PORT=8766 \
npm start
```

The configured Cloudflare route is `diary.kongming.org` → `http://127.0.0.1:8766`. Keep
`AUTH_SECURE_COOKIE=true` (the default) for the HTTPS public site. `AUTH_PUBLIC_HOSTNAME` protects
every page and API request made through that hostname. If direct LAN Android access is also needed,
bind with `HOST=0.0.0.0` and configure the Android client for port `8766`; requests made through the
LAN IP remain cookie-free. That split is safe only while the origin has no direct public route: do
not port-forward port 8766.

For defense in depth, put a deny-by-default Cloudflare Access application in front of the hostname
as well. The app login remains useful if an Access policy is accidentally loosened; Access adds an
independent identity check before traffic reaches the tunnel.

The persistent deployment uses the API and worker user services in `deploy/`. Their runtime values
live outside the repository in `~/.config/mood-pattern-diary/service.env` with owner-only
permissions. Restart both after changing that file.

## Verify

```sh
cd backend && npm test && npm run lint && npm run build
cd ../web && npm test && npm run lint && npm run build
E2E_BASE_URL=http://127.0.0.1:8000 npm run test:e2e  # with backend running
cd ../mobile && ./scripts/check && flutter build apk --debug
```

The smartphone app is Flutter (`mobile/`), replacing the earlier Kotlin/Compose Android client.
Its gate is `./scripts/check` — format, lint fixes, analysis, tests and the 95% coverage floor —
and building the APK additionally needs JDK 17 and the Android SDK. See the component READMEs,
`mobile/CONSTITUTION.md`, and `specs/` for detailed design decisions.

## Protect the diary

The live file is `data/diary.db`, excluded from source control and forced to owner-only permissions
on POSIX systems. Create a consistent backup—even while the service is running—with:

```sh
cd backend
npm run build
npm run backup -- /secure/off-device/path/diary-$(date +%F).db
```

Backups contain plain-text private writing. Store them on encrypted media. To restore, stop the
backend, preserve the current file under a different name, copy the chosen backup to
`data/diary.db`, set it to owner-only permissions (`chmod 600` on Linux/macOS), and start the backend.
Verify `/health`, Today, Calendar, and Insights before removing the preserved copy.

## Deliberate constraints

- Single user; one configured login rather than registration or accounts.
- Online over the local network only; no offline sync.
- No persistent browser drafts or service worker. Auth sessions are HttpOnly cookies and end on
  expiry, logout, or backend restart.
- Diary text is never sent to a third-party AI vendor. The API enqueues inference work in SQLite; a
  separate worker uses `qwen3:4b` through Ollama, running on the same infrastructure as the backend,
  for feeling suggestion and topic extraction. It requests immediate model unload after every entry.
  If the worker is unavailable, the entry is still saved and the user can select a feeling manually.
  Pattern thresholds and wording stay deterministic.
- Browser recordings are never sent to a third-party AI vendor either, and are not retained after
  transcription on that same infrastructure.
- Audio transcripts are saved before formatting starts. Formatting may change punctuation,
  capitalization, whitespace, paragraph breaks, and Markdown list markers, but not the word sequence.
