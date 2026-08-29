# Code review — Mood Pattern Diary

**Date**: 2026-08-27 · **Scope**: whole codebase (backend, web, Android, specs, deploy) at `main` (`3833d51`) plus the uncommitted working tree · **Reviewed against**: `.specify/memory/constitution.md` v1.2.0 and `specs/00{1..5}`

Findings below are split into **security risks** and **spec deviations**. Everything marked *verified* was reproduced against a running instance using a throwaway copy of `backend/tests/fixtures/golden.db` — no real diary data was read, and the repo was left exactly as found.

---

## Summary

| # | Finding | Severity |
|---|---|---|
| S1 | Authentication is scoped by the `Host` header and fails **open** on any unrecognised host | High |
| S2 | Trailing-dot hostname (`diary.example.com.`) evades the exact-match host check | Medium |
| S3 | Login throttle is one global counter — an attacker can lock the owner out indefinitely | Medium |
| S4 | `/topics` serves diary-derived content without `Cache-Control: no-store` | Medium |
| S5 | Transcription spawns unbounded concurrent `ffmpeg` + `whisper` processes | Medium |
| S6 | `.gitignore` gap: `data/*.db-*` does not match `data/*.db.*` | Low |
| S7 | `X-Powered-By: Express` disclosed on every response | Low |
| S8 | Real deployment hostname committed to three tracked files | Low |
| S9 | CSRF defence falls back to SameSite alone when `Origin` is absent | Info |
| S10 | systemd unit runs Node from an IDE's ephemeral cache directory | Low |
| D1 | Principle VII: `MAX_FEELINGS_PER_ENTRY` hardcoded in backend **and** both clients | Medium |
| D2 | `003` FR-016 ("MUST NOT be exposed to the public internet") never reconciled with `005` | Medium |
| D3 | Fixture README's defect tally (17/5) contradicts the fixture itself (13/9) | Low |

---

## Security risks

### S1 — Auth is scoped by the `Host` header, and an unrecognised host fails open · High

`AuthManager.protects()` ([backend/src/auth/auth.ts:40](backend/src/auth/auth.ts:40)) returns `false` — meaning *no authentication* — for any request whose `Host` does not exactly equal `AUTH_PUBLIC_HOSTNAME`, and `requireSession` then calls `next()` unconditionally ([auth.ts:50](backend/src/auth/auth.ts:50)).

Verified against a live instance with `AUTH_ENABLED=true`, `AUTH_PUBLIC_HOSTNAME=diary.example.com`:

```
Host: diary.example.com   GET /entries    -> 401     GET /app/today -> 303 (login)
Host: localhost           GET /entries    -> 200 {"entries":[...]}   GET /app/today -> 200
Host: evil.attacker.tld   GET /entries    -> 200
```

One request header is the entire difference between "diary locked" and "diary served". This is the LAN-bypass the spec asks for, so the behaviour is intended — but the *default direction* is wrong: an unknown host disables protection instead of enabling it, which is the opposite of the constitution's own "fail closed when enabled with incomplete configuration" (Product Constraints) and of the same file's fail-closed startup check in `loadAuthConfig()`.

What keeps this from being critical today: the documented tunnel deployment binds `HOST=127.0.0.1` ([README.md:73](README.md:73)), so only a local process can present a spoofed `Host`. `X-Forwarded-Host` is **not** trusted (Express `trust proxy` is off — verified: spoofing it still returned 401), which is correct and worth keeping.

What makes it load-bearing anyway: the same README endorses `HOST=0.0.0.0` for LAN Android access in the *same paragraph* as the authenticated tunnel. In that configuration every device on the LAN reads and writes the entire diary with no credential at all, and any second ingress route to the origin — a stray `cloudflared` rule, a container port publish, an SSRF in anything else on the host — silently removes authentication rather than tripping over it.

**Suggested fix**: invert the default. Treat every request as protected, and bypass only for an explicit allowlist (loopback, or a configured LAN CIDR checked against `req.socket.remoteAddress`, which the client cannot forge). Alternatively, give the tunnel its own loopback port and treat that socket as always-protected.

### S2 — Trailing-dot hostname evades the host match · Medium

`protects()` compares `req.hostname.toLowerCase()` to the configured name by exact equality. The fully-qualified form of a hostname carries a trailing dot, is accepted by browsers and HTTP clients, and resolves to the same origin — but does not compare equal. Verified:

```
Host: diary.example.com     -> 401  (protected)
Host: DIARY.EXAMPLE.COM     -> 401  (protected — case handled correctly)
Host: diary.example.com:443 -> 401  (protected — port stripped correctly)
Host: diary.example.com.    -> 422  (reached the application: NOT protected)
```

**Suggested fix**: strip a single trailing `.` from both sides before comparing, in `protects()` and in `loadAuthConfig()`.

### S3 — One global failure counter lets anyone lock the owner out · Medium

`failedAt` is a single process-wide array with no per-IP dimension ([auth.ts:17](backend/src/auth/auth.ts:17)), the throttle is checked *before* credentials are verified ([auth.ts:81](backend/src/auth/auth.ts:81)), and only a *successful* login clears it ([auth.ts:97](backend/src/auth/auth.ts:97)). So the owner cannot clear a lockout that the lockout itself prevents them from clearing. Verified:

```
8 × wrong password                      -> 401 each
then owner's CORRECT password           -> 429  Retry-After: 900
                                           "Too many attempts. Try again in 15 minutes."
```

Because the window slides, one wrong guess every ~112 seconds keeps the owner permanently locked out of their own diary for the cost of a trickle of requests.

The spec asks for in-process throttling and it is present, so this is about the shape rather than the presence. **Suggested fix**: key the counter by `req.ip`, and/or verify credentials first so a correct password is never rejected by the throttle — the scrypt cost already bounds guess rate.

### S4 — `/topics` is cacheable diary content · Medium

`NO_STORE_PREFIXES` ([backend/src/main.ts:14](backend/src/main.ts:14)) lists `/entries`, `/insights`, `/monthly-summary`, `/guiding-questions`, `/transcriptions`, `/guided-entry-drafts` — but not `/topics`. Verified:

```
/entries           Cache-Control: no-store
/insights          Cache-Control: no-store
/monthly-summary   Cache-Control: no-store
/guiding-questions Cache-Control: no-store
/topics            (no Cache-Control header)
```

`/topics` is not metadata. It returns topic names extracted from the user's own writing, including free-text topics they typed, with per-topic entry counts:

```json
{"topics":[{"name":"coca cola","entry_count":3}, {"name":"walking","entry_count":1}]}
```

That lands in the browser's on-disk cache and survives the tab closing. It contradicts `specs/005-public-auth/spec.md` ("all diary API responses MUST be non-cacheable") and the intent of FR-025. `/feelings` is also uncovered, but that one is the static vocabulary, so it is correctly out of scope.

**Suggested fix**: add `'/topics'` to `NO_STORE_PREFIXES`.

### S5 — Unbounded transcription concurrency · Medium

`TranscriptionJobsService.start()` ([backend/src/transcription/transcription-jobs.service.ts:33](backend/src/transcription/transcription-jobs.service.ts:33)) calls `transcribe()` immediately on every request. There is no queue, no concurrency cap, and no per-caller limit. Each job spawns `ffmpeg` (30 s timeout) and then `whisper-cli` with up to 8 threads and a timeout that defaults to 120 s and is configurable to 600 s, against a body of up to 25 MB ([main.ts:46](backend/src/main.ts:46)).

*N* simultaneous POSTs to `/transcriptions` therefore claim *N* × 8 threads. On the `HOST=0.0.0.0` deployment from S1 that is unauthenticated CPU exhaustion from any device on the network; through the tunnel it is authenticated but still trivially self-inflicted.

**Suggested fix**: serialise transcription behind a single-slot queue (the work is inherently CPU-bound and single-user), and reject or queue rather than spawn when one is already running.

### S6 — `.gitignore` does not cover the snapshot convention already in use · Low

The ignore rules are `data/*.db` and `data/*.db-*`. The second matches SQLite sidecars (`diary.db-wal`, `diary.db-shm`) but **not** `diary.db.pre-004-schema`, which is the naming actually used in `data/` today:

```
data/diary.db                     IGNORED
data/diary.db.pre-004-schema      NOT IGNORED
```

To be accurate about the live risk: that specific file currently holds **0 entries** — it is an empty schema snapshot, so nothing private is exposed right now. The problem is the latent one. The repo has established a `diary.db.<label>` convention for pre-migration snapshots, and the next such snapshot taken from a populated diary would be staged by a plain `git add -A`, against Principle IV.

**Suggested fix**: add `data/*.db.*` to `.gitignore`.

### S7 — `X-Powered-By: Express` · Low

Present on every response, including the public login page. One line removes it: `app.disable('x-powered-by')` alongside the other header work in `createApp`.

### S8 — Deployment hostname committed · Low

`diary.kongming.org` appears in [README.md:71](README.md:71), [README.md:77](README.md:77), `backend/README.md:78`, and `specs/005-public-auth/plan.md:24`. If this repository is ever pushed public, that names the exact internet-reachable endpoint of a personal diary and pairs it with a full description of its auth model. Substituting `diary.example.com` in the docs costs nothing.

### S9 — CSRF falls back to SameSite when `Origin` is absent · Info

The origin check only runs when the header is present ([auth.ts:53](backend/src/auth/auth.ts:53)). Verified:

```
POST /entries  Origin: https://evil.tld   -> 403  (correctly rejected)
POST /entries  (no Origin header)         -> 201  (allowed)
```

`SameSite=Strict` covers this for real browsers, so it is not currently exploitable — worth recording as a known assumption rather than fixing.

### S10 — systemd unit runs Node from an IDE cache directory · Low

`deploy/mood-pattern-diary.service` sets both `ExecStart` and the head of `PATH` to `/home/epalk/.windsurf-server/bin/c855b1fa42fce019aedb4b06e6faa69d65ac7fd3/node`. That path is an IDE's remote-server payload, keyed by a commit hash: it is garbage-collected on IDE update, so the service breaks on a schedule nobody controls, and the diary process's interpreter becomes whatever that auto-updating channel ships. The rest of the unit is genuinely good hardening (`ProtectSystem=strict`, `ProtectHome=read-only`, `NoNewPrivileges`, `UMask=0077`, restricted address families) — this one line undercuts it. Point it at a system Node.

---

## Spec deviations

### D1 — Principle VII: the feelings-per-entry cap lives in all three clients · Medium

The constitution requires every rule to be "defined and computed in the backend only and served to clients", and that "a client MUST NOT hardcode, duplicate, or independently recompute any of them". `engineConstants()` ([backend/src/insights/constants.ts](backend/src/insights/constants.ts)) does exactly that for ten values — including `min_intensity` and `max_intensity`.

`MAX_FEELINGS_PER_ENTRY` is not among them. It is hardcoded three times:

- `backend/src/db/feeling-vocabulary.ts:152` — `export const MAX_FEELINGS_PER_ENTRY = 4`
- `web/src/components/FeelingChips.tsx:43` — `max = 4` (literal default)
- `android/.../domain/Feeling.kt:141` — `const val MAX_FEELINGS_PER_ENTRY: Int = 4`

This is a rule, not presentation: it decides how many feelings a user may attach, and `/feelings` does not serve it. Raising the cap to 5 changes behaviour in one place and leaves both clients silently enforcing 4.

Worth noting because it affects the record rather than just the code: the constitution's own Sync Impact Report declares `PRINCIPLE_VII_RECONCILIATION` **closed**, on the grounds that the Android feeling enum is gone and the vocabulary now comes from `GET /feelings`. That part is true and verified. The reconciliation is nonetheless partial — this constant survived it.

**Suggested fix**: add `max_feelings_per_entry` to `EngineConstants` (or to the `/feelings` payload) and have both clients read it.

### D2 — Two live specs state opposite requirements about public exposure · Medium

`specs/003-web-client/spec.md` still reads, as a hard requirement:

> **FR-016**: The web client … MUST NOT be exposed to the public internet

and its Assumptions still say "**No in-app authentication**, consistent with the Android app's existing decision … This is revisited only if the web app is ever exposed beyond the home network — which FR-016 forbids for v1."

Constitution v1.2.0 and `specs/005-public-auth/` then did exactly that, and the deployment described in `README.md` is live. Neither `003`'s FR-016 nor its Assumptions were amended, and `005`'s spec does not record that it supersedes them.

The constitution's Amendment-reconciliation clause covers this ("not retroactively blocked but SHOULD be reconciled"), so no rule was broken — but the repo's durable record now contradicts itself on its single most security-relevant question, which is precisely the failure mode Principle I exists to prevent. A one-line supersession note in `003` FR-016 pointing at `005` closes it.

### D3 — Fixture README's tally contradicts the fixture · Low

`backend/tests/fixtures/README.md` states "`holds` (5)" and "`defect` (17)". The actual `insight-scenarios.json` contains **9 holds and 13 defects** — four scenarios have been fixed since the prose was written. Since the README's whole argument is that this file must be updated in the same change that fixes a defect, the drift undercuts the mechanism it documents.

### D4 — One task openly deferred · Info

`specs/002-mood-pattern-diary-mobile/tasks.md` T071 (structured logging) is unchecked and annotated *"not done — nice-to-have, deferred"*. Accurately recorded; noted only for completeness. All tasks in `003`, `004` and `005` are complete.

---

## Checked and found sound

Recording these so the review's negative space is legible, and so the same ground is not re-turned later.

- **Test and lint state**: 315 backend tests pass (29 files, 1 eval suite skipped), 68 web tests pass, `eslint` + `prettier` clean in both packages, `npm audit --omit=dev` reports **0 vulnerabilities** in both.
- **Auth mechanics, verified live**: `next=https://evil.tld/steal` is discarded in favour of `/app/today` (no open redirect); the session cookie is `HttpOnly; SameSite=Strict; Max-Age=43200; Path=/` and `Secure` by default; logout revokes server-side, after which the old token returns 401; a foreign `Origin` on an unsafe method returns 403; failed logins return a generic message; verification runs even when the email is wrong, so there is no user-enumeration timing gap.
- **Password handling**: scrypt with N=16384, r=8, p=1, a 16-byte per-hash random salt, `timingSafeEqual`, a 12-character minimum, and parameter pinning that rejects a downgraded hash. The hash-generation CLI reads the password from the environment rather than argv, keeping it out of `ps` and shell history.
- **SQL**: every statement is parameterised. The two `${…}` interpolations ([patterns.service.ts:262](backend/src/insights/patterns.service.ts:262), [entries.repository.ts:67](backend/src/entries/entries.repository.ts:67)) expand to `?` placeholder lists only — no user data reaches the SQL string. The `openDiary` guard blocking DDL and the `fileMustExist` rule are both good defensive choices.
- **Subprocess handling**: `ffmpeg` and `whisper-cli` are invoked via `execFile` with argument arrays and no shell, so the audio path carries no command-injection risk. Recordings are written `0o600` into a `mkdtemp` directory and removed in a `finally`.
- **Privacy architecture**: inference runs against local Ollama, never a cloud LLM; no CORS is enabled; `index.html` avoids external fonts and CDNs. The tracked `golden.db` fixture is synthetic ("Had a coca cola at 0 pm"), not real diary content. `.env` and `backend/dist/` are correctly ignored.
- **Web client requirements**: no `Notification`/`serviceWorker`/`requestPermission` anywhere (FR-020), no `WebSocket`/`EventSource` (FR-019), no diary content in URLs (FR-024), and the only `localStorage` use is the appearance preference, which the code itself calls out as deliberately narrow (FR-025). Backend-owned thresholds are read from `insights.constants` rather than reimplemented — D1 is the single exception.
- **A CSP concern I raised and then disproved**: `style-src 'self'` (no `'unsafe-inline'`) looked likely to break the three components using `style={{…}}`. Loading the built app behind the real header showed the swatches computing to actual colours (`rgb(124, 196, 127)`) with no console violations — React applies inline styles through the CSSOM, which CSP does not gate. No issue; noting it so it is not re-raised.

---

## Method and limits

Backend and web were built and run against a copy of the golden fixture on ports 8123/8124; the auth findings were reproduced with `AUTH_ENABLED=true` and a throwaway credential. Two temporary launch configurations were added and have been removed — `git status` is back to the 132 entries it showed at the start, and no file was modified.

Not covered: the Android client was read for cross-client rule duplication (D1) but not otherwise reviewed, no Gradle build or Android test run was attempted, and the Playwright journey in `web/e2e/smoke.mjs` was read rather than executed. The uncommitted working tree is large (132 changed paths); findings describe the tree as it stands on disk, not as `HEAD` would build it.
