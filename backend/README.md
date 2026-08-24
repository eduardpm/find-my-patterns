# Mood Pattern Diary — Backend

NestJS + TypeScript service backing the Android app and the browser client. It owns the diary and
pattern engine, serves the built web client at `/app`, and exchanges durable SQLite jobs with a
separate local Ollama worker.

Specs: `specs/002-mood-pattern-diary-mobile/`, `specs/003-web-client/`,
`specs/004-nestjs-backend-migration/`, and `specs/005-public-auth/`.

## Setup

Requires Node 20 or newer (Node 22 LTS recommended).

```sh
cd backend
npm install
npm run build
npm run init-db     # first time only — creates ../data/diary.db
```

`init-db` refuses to touch a diary that already exists, so it is safe to re-run by mistake.

## Run

```sh
npm start              # API/web process
npm run start:worker   # separate inference process
```

Defaults: the diary at `../data/diary.db`, port `8000`, bound to `127.0.0.1`, and the built web client
from `../web/dist` served at `/app`.

| Variable                        | Default                            | Notes                                                             |
| ------------------------------- | ---------------------------------- | ----------------------------------------------------------------- |
| `DATABASE_PATH`                 | `../data/diary.db`                 | `DATABASE_URL` (`sqlite:///…`) is also accepted                   |
| `PORT` / `HOST`                 | `8000` / `127.0.0.1`               | Set `HOST=0.0.0.0` explicitly for trusted LAN phone access        |
| `OLLAMA_URL`                    | `http://127.0.0.1:11434`           | Read only by the worker; the API process never connects to Ollama |
| `OLLAMA_MODEL`                  | `qwen3:4b`                         | Must already be pulled locally                                    |
| `INFERENCE_WAIT_MS`             | `20000`                            | API wait before returning a saved entry without an AI suggestion  |
| `TRANSCRIPT_FORMATTING_WAIT_MS` | `90000`                            | Background wait budget for a cold local formatting model          |
| `WEB_DIST_PATH`                 | `../web/dist`                      | Missing is fine — the API still serves                            |
| `WHISPER_COMMAND`               | `../tools/whisper/bin/whisper-cli` | Local whisper.cpp executable used for audio answers               |
| `WHISPER_MODEL_PATH`            | `../models/ggml-base.bin`          | Local GGML speech model; recording is unavailable if absent       |
| `WHISPER_LANGUAGE`              | `auto`                             | Detection, or a language code such as `en` or `nl`                |
| `TRANSCRIPTION_TIMEOUT_MS`      | `120000`                           | Maximum whisper.cpp runtime per recording (1000–600000)           |

### Authentication variables

| Variable               | Default | Notes                                                              |
| ---------------------- | ------- | ------------------------------------------------------------------ |
| `AUTH_ENABLED`         | `false` | Set exactly `true` to require the configured login                 |
| `AUTH_EMAIL`           | unset   | Required when enabled; comparison is case-insensitive              |
| `AUTH_PASSWORD_HASH`   | unset   | Required scrypt hash from `npm run auth:hash-password`             |
| `AUTH_PUBLIC_HOSTNAME` | unset   | Exact tunnel hostname; unset protects every host                   |
| `AUTH_SECURE_COOKIE`   | enabled | Keep `true` in production; use `false` only for local HTTP testing |
| `AUTH_SESSION_HOURS`   | `12`    | Between 0 and 168; sessions also end whenever the backend restarts |

Enabled authentication fails startup if the email or hash is missing. Generate the hash by loading
the password into a temporary environment variable without adding it to shell history:

```sh
read -rsp 'Diary password: ' DIARY_AUTH_PASSWORD; echo
export DIARY_AUTH_PASSWORD
npm run build && npm run auth:hash-password
unset DIARY_AUTH_PASSWORD
```

The server **opens a diary, never creates one**. That is why `init-db` is a separate command: a
server that invents a missing file makes "wrong path" and "your diary is gone" look identical. If the
file's structure cannot be fully interpreted the backend refuses to start and says why, without
writing anything.

> **Never expose the origin port directly.** Public access is supported only through an outbound
> Cloudflare Tunnel with authentication enabled for its hostname. Prefer a Cloudflare Access policy
> as an independent outer layer. Hostname scoping intentionally lets direct LAN Android traffic
> bypass login, so port-forwarding the origin would invalidate the security boundary.

The current public deployment uses `AUTH_PUBLIC_HOSTNAME=diary.kongming.org`, `PORT=8766`, and a
Cloudflare route to `http://127.0.0.1:8766`. Keep `HOST=127.0.0.1` unless direct LAN Android access
is required; in that case use `HOST=0.0.0.0` but still never port-forward port 8766.

## Backup and recovery

Create a transactionally consistent snapshot (safe even while the backend is running):

```sh
npm run build
npm run backup -- /secure/off-device/path/diary-2026-08-14.db
```

The command refuses to overwrite a backup and makes it owner-readable only on POSIX systems. To
restore, stop the backend, preserve the current diary, copy the selected backup into place, set mode
`0600`, restart, and check `/health` plus the Today, Calendar, and Insights screens.

## Tests

```sh
npm test     # 145 tests
npm run lint
```

See [`tests/TESTING.md`](./tests/TESTING.md) for what each suite covers. Every test asserts something
a spec asks for.

## Design notes

**No ORM.** Hand-written SQL through `better-sqlite3`. Every mainstream Node ORM's default posture is
to own the schema — synchronize, migrate, push — and the cost of getting that opt-out wrong is not an
error, it is silent alteration of the one file with no upstream copy. The connection refuses DDL
outright, and lint blocks it in `src/`.

**One codec module.** Nothing writes a datetime, date, JSON column or boolean except through
`src/db/codecs.ts`. Existing diaries already contain a specific byte format, and Node's defaults
differ from it in ways that fail silently.

**Deterministic core, local model at one edge.** Pattern counts, thresholds, wording and averages are
ordinary tested code. On entry creation the API inserts an `entry_analysis` job and waits briefly;
only the worker can call Ollama. The worker asks `qwen3:4b` for schema-constrained feeling and topic
output, validates it, persists it, and requests `keep_alive: 0` in both the generation and a final
unload call. The long-running worker itself does not keep the model loaded while idle.

If Ollama or the worker is unavailable, writing still succeeds. The entry remains without a
suggested feeling so the user can choose one manually; a failed model response is never treated as
fact.

## Layout

```
src/
├── main.ts, app.module.ts, config.ts
├── db/           codecs · database · compatibility · seed
├── entries/      repository · service · controller
├── topics/       deterministic keyword extraction
├── inference/    SQLite queue boundary + Ollama worker
├── insights/     deterministic pattern detection + narration
├── monthly-summary/
└── common/       error envelope · stale-entry 409 · validation
```
