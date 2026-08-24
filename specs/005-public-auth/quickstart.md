# Quickstart validation: Public authentication

1. Build the web and backend, generate a scrypt hash, and start a disposable database with
   `AUTH_ENABLED=true`, `AUTH_SECURE_COOKIE=false`, and no hostname scope.
2. Open `/app/today` in a new browser context and confirm it redirects to `/login`.
3. Confirm an incorrect password shows a generic error, then sign in with the configured email and
   password and confirm the requested app page opens.
4. Create, confirm, and edit an entry; open Calendar and Insights; repeat at a mobile viewport.
5. Sign out and confirm revisiting `/app/today` returns to login and `/insights` returns JSON 401.
6. Repeat contract checks with `AUTH_PUBLIC_HOSTNAME`: the public Host is protected, a LAN-IP Host
   is unchanged, and an authenticated cross-origin write receives 403.

Validated on 2026-08-14 by the automated contract suite and Playwright Chromium journey. The test
used a temporary copy of the golden fixture, not the live diary, and the copy was removed afterward.
