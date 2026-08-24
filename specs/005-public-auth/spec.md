# Feature Specification: Single-user public authentication

**Date**: 2026-08-14

## Purpose

Allow the owner to use the web diary through a Cloudflare Tunnel without exposing diary pages or
API data to unauthenticated internet users. This remains a one-user system, not an account system.

## Requirements

- When `AUTH_ENABLED=true`, the configured public hostname MUST require authentication for `/app`
  and all diary API endpoints; `/login`, login/logout handlers, and `/health` remain reachable.
- Incomplete enabled configuration MUST stop startup rather than silently disable protection.
- Credentials MUST be supplied through environment variables; the repository and database MUST
  never store a plaintext password.
- Password verification MUST use scrypt with a per-hash random salt and timing-safe comparison.
- A successful login MUST issue a random, opaque, HttpOnly, SameSite=Strict session cookie. It MUST
  be Secure by default and expire after a bounded lifetime.
- Failed logins MUST return a generic message and be throttled in-process. Login responses and all
  diary API responses MUST be non-cacheable.
- Logout MUST revoke the server-side session and expire the cookie.
- Browser navigation to a protected page MUST redirect to login and safely return after success;
  unauthenticated API calls MUST return a JSON 401.
- Direct LAN clients MAY bypass authentication only when `AUTH_PUBLIC_HOSTNAME` scopes protection
  to the tunnel hostname. Documentation MUST warn that this requires an outbound-only tunnel and
  must never accompany direct public origin exposure.
- The web shell MUST expose a clear logout control.

## Success criteria

- Automated tests cover hashing, configuration failure, redirects/401s, successful and failed
  login, cookie attributes, hostname scoping, throttling, and logout revocation.
- A Playwright browser journey signs in, exercises create/edit/calendar/insights, signs out, and
  confirms the diary is inaccessible afterward.

## Out of scope

Registration, password reset email, multiple users, social login, persistent cross-restart
sessions, and authorization roles.
