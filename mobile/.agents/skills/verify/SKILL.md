---
name: verify
description: Run this project's verification gate — format, analyze, tests, coverage, and the platform build — then report it. Use before calling any code task done, when asked to verify or double-check a change, or when a gate step fails and you need the fix path.
---

# Verify

The gate from Article 1 of `CONSTITUTION.md` in the repo root, which is the
authority if this file and the constitution ever disagree. Article numbers below
refer to it.

Run the steps in order from the repo root. Stop at the first failure and fix it
before moving on — a later step run on a broken earlier one proves nothing.

## 1. Format

```bash
dart format --set-exit-if-changed .
```

Green when the exit code is 0. If it is not, run `dart format .` and keep the
reformat as part of the change.

## 2. Analyze

```bash
flutter analyze
```

Green when it prints `No issues found!`. Info-level diagnostics count. Fix the
code; adding an `// ignore:` comment to pass this step is not a fix. If a lint
rule itself is wrong, raise it with the user instead of silencing it.

## 3. Tests and coverage

```bash
flutter test --coverage
```

Green when every test passes. A red test stops the gate: Article 2 says
understand the failure before touching the test.

```bash
awk -F: '/^LF:/{lf+=$2} /^LH:/{lh+=$2} END{printf "%.1f%%\n", 100*lh/lf}' coverage/lcov.info
```

Green at 95% or above (Article 4). Below it, find the gap:

```bash
awk -F: '/^SF:/{f=$2} /^LF:/{lf=$2} /^LH:/{printf "%5.1f%%  %s\n", 100*$2/lf, f}' coverage/lcov.info | sort -n | head
```

Close it with tests for untested behaviour — error paths, edge cases, state
transitions. Not with tests that exist to execute a line, and not with tests for
styling or layout (Article 3).

`lcov` and `genhtml` are not installed on this machine; the awk lines above are
the coverage report.

## 4. Platform build, when the change reaches the platform

Steps 2 and 3 prove the Dart compiles. They do not prove the app builds. If the
change touched `pubspec.yaml`, a plugin, or anything under `android/`, `ios/`,
`macos/`, `linux/`, `windows/`, or `web/`, build the affected target:

```bash
flutter build apk --debug
```

Otherwise skip this step and say you skipped it.

## 5. Run it, when a user can see the change

Article 5: behaviour tests do not verify what something looks like. Reuse the
dev server that is already running (Article 6), hot reload, then screenshot,
exercise the thing you changed, and check light and dark theme.

## 6. Report

Article 12, in this shape:

```
Gate: format clean · analyze 0 issues · tests N/N · coverage NN.N% · build <target|skipped>
Wrong assumptions: <test, what was assumed, what is true> — or "none"
Unfinished: <what is left and why> — or "nothing"
```

Report the numbers you actually saw. A gate you did not run is not a gate.
