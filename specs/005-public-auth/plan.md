# Implementation Plan: Single-user public authentication

## Constitution check

Feature 005 accompanies constitution 1.2.0. It remains single-user and self-hosted, stores no diary
content with a third party, keeps clients thin, and adds no friction after the bounded login step.
Public access is allowed only at the authenticated tunnel hostname.

## Design

- Add strict environment parsing for auth settings and a standalone password-hash command.
- Add a small framework-neutral auth module using Node's `crypto.scrypt`, an in-memory session map,
  generic credential failures, and a fixed-window failed-login limiter.
- Register login/logout routes and protection middleware before Nest routes and static assets.
- Return HTML redirects for `/app`, JSON 401 for APIs, and validate return paths to avoid redirects
  outside `/app`.
- Add a native form logout control to the React navigation.
- Run unit/contract suites, then launch a disposable authenticated server and run Playwright.

## Operational boundary

Session loss on restart is intentional and safe. Hostname scoping exists solely for LAN Android
compatibility. Cloudflare Tunnel must be the only public route to the origin; Cloudflare Access is
recommended as defense in depth. The deployed route is `diary.kongming.org` to the loopback origin
at `http://127.0.0.1:8766`.
