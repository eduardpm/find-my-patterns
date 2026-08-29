# Constitution

Binding rules for this repository and for every app forked from it.

This file outranks habit, precedent, and any older document in the repo. It does
not outrank an explicit instruction from the user in the current conversation —
but such an exception applies to that task only, and must be stated out loud
when the task is reported.

Copy this file into every fork. Amend it in the base, then carry the change
forward.

---

## Article 1 — Done means verified

A task is done when it is verified, not when the code is written. Claiming "done"
without the evidence below is the one failure this constitution exists to
prevent.

The gate, run from the repo root, in this order:

```bash
dart format --set-exit-if-changed .
flutter analyze
flutter test --coverage
```

All three must pass: no reformatting, **zero** analyzer issues (info counts),
every test green. Then read the coverage number (Article 4).

`analyze` plus `test` prove the Dart compiles. If the task touched
`pubspec.yaml`, a plugin, or anything under `android/`, `ios/`, `macos/`,
`linux/`, `windows/`, or `web/`, also run a real build for that target — for
example `flutter build apk --debug`.

Non-code tasks are verified too. State what you checked and how.

Never report a green gate you did not run. If a step fails and you cannot fix
it, say so with the output, and say which parts of the task are unfinished.

## Article 2 — Test first

Every code change follows red → green → refactor.

1. Write the test. Run it. Watch it fail, for the reason you expect.
2. Write the smallest implementation that makes it pass.
3. Refactor with the test still green.

A test that passes before the implementation exists is testing nothing. A test
you never saw fail is not evidence.

**When a test fails unexpectedly, stop.** Do not edit the test until you
understand the failure. Three outcomes:

- The implementation is wrong → fix the implementation.
- The test's assumption about the desired behaviour was wrong → fix the test,
  and record it for Article 12.
- The right behaviour is genuinely unclear → ask the user before choosing.

Bug fixes start with a test that reproduces the bug.

## Article 3 — What we test, and what we don't

Test behaviour and logic: state transitions, parsing and validation, error
paths, persistence round-trips, what the user can do and what they see happen.

Do not write tests for styling or layout. No assertions on colours, padding,
font sizes, widget nesting, or pixel positions. They break on every visual
tweak and prove nothing. Visual correctness is verified by looking at it
(Article 5).

Testing a widget's *behaviour* is not styling: that a button is disabled until
the form is valid, that an error banner appears after a failed request, that a
tab switch shows the other screen. Assert through semantics and visible text,
not through the widget tree's shape.

Tests are deterministic and offline. No real network, no real clock, no
`sleep`. Use the fakes in `test/support/` and extend them rather than reaching
for a mocking framework.

## Article 4 — Coverage

Line coverage over `lib/` stays at **95% or above**. Read it with:

```bash
awk -F: '/^LF:/{lf+=$2} /^LH:/{lh+=$2} END{printf "%.1f%%\n", 100*lh/lf}' coverage/lcov.info
```

If a change drops the number below 95%, the task is not done.

Coverage is a floor, not a target. Do not write tests whose only purpose is to
execute a line — untested error paths are the gap worth closing, and a file of
plain constants is not.

## Article 5 — UI and UX changes are proven on a screen

Any change a user can see is verified twice: by behaviour tests, and by running
it.

Running it means an emulator, a simulator, or the browser — then look at the
result. Take a screenshot. Exercise the thing you changed: tap it, type into
it, make it fail. Check it in both light and dark theme, and in the smallest
window or screen the app supports.

"It compiles and the tests pass" is not verification of a UI change. Neither is
reading your own diff.

## Article 6 — The dev server stays up

Start it once, keep it alive.

- **Reuse what is running.** Before starting anything, check for a dev server
  already up and use it. Never start a second one.
- **Never stop a running server** — not to tidy up, not to free a port, not
  because the task is over. It stops when the user asks, or when a change
  genuinely cannot be picked up any other way.
- **Push changes with hot reload** (`r` in `flutter run`), hot restart (`R`)
  when state, `main`, or a provider graph changed. A full stop-and-start is the
  last resort, not the first move.
- **If it did go down, bring it back up before reporting the task done**, and
  say why it went down.

A task that involves a running app is unfinished while the app is not running.

## Article 7 — REST

The client speaks REST and never invents its own conventions.

- Paths name resources, not actions: `/api/session`, not `/api/get-session`.
- Verbs mean what they mean. `GET` never changes state. `PUT` and `DELETE` are
  idempotent. `POST` creates.
- Status codes are honest. Never return `200` with an error inside the body,
  and never treat a `4xx` as success.
- `4xx` is the caller's fault; `5xx` is the server's. Preserve the status in the
  typed error and let the UI decide what to say.
- Errors come back as structured bodies, not bare strings.
- One endpoint's shape does not depend on another endpoint's call order.

Every backend path lives in `AppConfig`. No URL is ever hardcoded at a call
site.

## Article 8 — Architecture

1. **The backend owns the logic; the client stays thin.** The client renders,
   validates input, and reports errors. It does not decide.
2. **The user points the app at their own server.** No hardcoded cloud URLs.
   Host and port are typed once in Settings.
3. **Sessions ride on HttpOnly cookies**, against the one session
   resource in `AppConfig` — `POST` to sign in, `GET` to check, `DELETE` to
   sign out.
4. **Settings survive restarts and never hold user data** — backend address and
   appearance only.
5. **Layering is one-directional.** `core/` never imports from `features/`. A
   feature never imports another feature; shared code moves to `core/`.
6. **Decisions made once per app are compile-time constants** in `AppConfig`.
   Anything the user can change lives in `AppSettings`.

## Article 9 — Data, secrets, and errors

No secrets, tokens, or real user data in the repo, in tests, or in logs. No
personal data in URLs or query strings.

Errors surface. Catch narrowly with an `on` clause, convert to the app's typed
error, and show the user something true. An empty `catch` is a bug.

## Article 10 — Dependencies

A new dependency needs a reason that the standard library and the existing
dependencies cannot meet. Say the reason when you add one. Keep
`pubspec.yaml` sorted and the lockfile committed.

## Article 11 — Scope

Do the task that was asked. Do not add features, refactor neighbouring code, or
"improve" things nobody asked about.

When you find a real problem outside the task, say so and leave it. If the task
as specified is wrong, say why in a sentence or two, then deliver it under a
stated assumption rather than silently doing something else.

Accessibility is in scope for every UI change, never a follow-up: every
interactive element has a label, touch targets stay at least 48dp, and nothing
depends on colour alone.

## Article 12 — Reporting

Every finished task reports:

1. **The gate.** Format, analyze, test, coverage — the actual numbers.
2. **Wrong assumptions.** Every test that failed because the *expected
   behaviour* was wrong, with what you assumed, what turned out to be true, and
   what you changed. Mechanical failures — a renamed symbol, a moved path, an
   updated fixture — are noise; leave them out.
3. **What is unfinished**, and why.

If no test failed on a wrong assumption, say so in one line.

## Article 13 — Propose the skill after the session

When a session ends, look back at what you did and ask which of it should never
have needed a prompt: a sequence you repeated across tasks, a checklist you
walked by hand, the same fix applied the same way more than once, a gate you
ran step by step.

Propose it as a skill. Name it, say what would trigger it, what it would do,
and which part of this session it would have replaced. One or two candidates,
not a catalogue. If nothing qualifies, say nothing.

Skills live in `.agents/skills/<name>/SKILL.md`; `.claude/skills` is a symlink
to that folder, so a skill written once is visible to every agent working here.
Write it with the `writing-for-agents` skill, and only after the user agrees.

## Amendments

Amend by editing this file in the base repo, in its own commit, with the reason
in the commit message. Forks inherit amendments by copying the file. A rule that
gets waived twice is either wrong or badly worded — fix the rule instead of
waiving it a third time.
