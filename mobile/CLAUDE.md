# find_my_patterns

The Flutter client for the self-hosted mood pattern diary. Forked from the
portfolio's shared `bootstrap` base and expanded to replace the Kotlin/Compose
Android app that used to live in this repository's `android/` directory.

Layout and boot flow: [README.md](README.md).

## Read this first

**[CONSTITUTION.md](CONSTITUTION.md) is binding.** Read it before writing code,
and again before calling a task done. It sets the verification gate, test-first
development, the coverage floor, what not to test, how UI changes are proven,
REST rules, the dev server's lifecycle, and what every finished task and
session must report.

The short version, which never excuses skipping the file: test first, verify
everything, and a task is done only when the gate is green.

## The one rule this app adds

**The backend owns the logic; this client renders it.** Every threshold, count,
rate, narrative and suggestion arrives in the payload and is displayed as
received — never re-counted, re-rated or reworded here. The window length and
the intensity scale come from `EngineConstants` in the insights response, so a
screen that hardcoded "30 days" or a 1–5 dial would go quietly wrong the day the
backend changed it. The web client shows the same numbers from the same payload,
and that is the only way the two can be guaranteed to agree about one diary.
