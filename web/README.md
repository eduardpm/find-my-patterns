# Mood Pattern Diary — Web client

Browser client for the Mood Pattern Diary backend (see `../backend`). React 18 + TypeScript, built
with Vite, per `specs/003-web-client/plan.md`. It's a peer to the Android app, not a replacement:
both talk to the same self-hosted backend and show the same diary.

## Prerequisites

- **Node 20 LTS or newer** (developed against Node 22).
- The backend from `../backend`, running and reachable.

## Setup

```sh
cd web
npm install
npm run build     # emits dist/, which the backend serves at /app
```

## Running it

The built client is served by the backend itself — there's no second process and no second address
to remember:

```sh
cd ../backend
npm install && npm run build      # first time only
npm start
```

Then open **`http://<your-machine-lan-ip>:8000/app`** from any device on your home network.

Settings offers three papers to write on — warm paper, sage and dusk — each with a light and a dark
half, plus a light/dark/system switch. The choice is kept in that browser and is never sent to the
backend. The Android app offers the same three.

The backend binds safely to `127.0.0.1` by default. For a trusted home LAN or VPN, start it with
`HOST=0.0.0.0`; that makes it reachable from your phone or laptop, but it must never be port-forwarded
or placed on a public host because there is no login.

> If you haven't run `npm run build`, the backend logs a warning and serves the API only — it won't
> refuse to start. The Android app keeps working either way.

### Developing

```sh
npm run dev       # hot reload on :5173, proxies API calls to :8000
npm test          # Vitest
npm run test:e2e  # Playwright journey; backend must be running (E2E_BASE_URL may override it)
npm run lint      # eslint + prettier
npm run format    # rewrite with prettier
```

`npm run dev` still needs the backend running on port 8000 — the dev server proxies `/entries`,
`/feelings`, `/guiding-questions`, `/insights` and `/monthly-summary` to it.

## Why everything lives under `/app`

The API already owns `/entries` and `/insights` at the top level, and the browser app wants routes
with those same names. Serving the client under `/app` keeps them from colliding. The alternative —
moving the API to `/api` — would have broken the already-installed Android app, which FR-018
forbids. See `specs/003-web-client/research.md` §2.

## Things that are deliberate, not oversights

- **No offline support, no service worker, no installability.** Diary content must not be written
  anywhere that survives the tab (FR-025), and a service worker exists to cache exactly that. This
  also keeps the browser out of the reminder business — your phone stays the only thing that pings
  you at 9:00 (FR-020).
- **No login.** Access control is your computer's lock screen plus your home network, the same
  bargain the Android app makes. This only holds while the backend stays off the public internet.
- **No diary text is remembered locally.** No cookies, no draft recovery, and the only thing in
  local storage is which of the three papers you picked in Settings and whether you want light or
  dark. Close the tab mid-entry and the browser will ask you to confirm first — but if it crashes,
  that writing is gone. That's the accepted cost of not storing diary text on disk (FR-025).
- **URLs never contain diary text.** Addresses carry only which view you're on and an opaque entry
  id, because browser history syncs across devices.
- **Manual refresh, not live updates.** If you add an entry on your phone, hit Refresh here to see
  it. Acting on a stale view is safe: the backend rejects edits based on an out-of-date copy and the
  app shows you both versions rather than overwriting either.

## Layout

```
web/
├── index.html, vite.config.ts, tsconfig.json
├── src/
│   ├── main.tsx, App.tsx        # shell, nav, routes
│   ├── api/                     # fetch wrappers per endpoint + ApiResult/409 mapping
│   ├── domain/types.ts          # mirrors of the backend schemas
│   ├── screens/                 # Today, Composer, Guided flow, Detail, Conflict, Insights,
│   │                            #   Calendar, Topics, Settings
│   ├── components/              # FeelingChips, EntryCard, PatternCard, CalendarGrid, ErrorBanner
│   ├── hooks/                   # useUnsavedGuard (FR-026), useRefreshable (FR-019), useAppearance
│   ├── theme.ts                 # the three palettes' ids, labels and stored preference
│   └── styles/                  # the design tokens both clients share
└── tests/                       # Vitest + React Testing Library
```

Nothing in `src/` computes a count, an average, or a threshold. Every number on screen arrives from
the backend already worked out — that's what keeps this client and the Android one from ever
disagreeing (constitution Principle VII).
