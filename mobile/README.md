# Find My Patterns

The smartphone client for the self-hosted mood pattern diary. One Flutter
codebase, replacing the Kotlin/Compose Android app this repository used to
carry.

[CONSTITUTION.md](CONSTITUTION.md) is binding — read it before writing code. It
defines the verification gate, test-first development, the coverage floor, the
REST rules and the architecture. This file only describes what is here.

## Getting started

```bash
./scripts/run          # build and launch on the connected device
./scripts/check        # format, fix, analyse, test, coverage
```

Both take `--help`. `./scripts/run --devices` lists what is available;
`./scripts/check --ci` verifies without rewriting anything, which is the mode
CI uses.

There is no build-time server address. Launch the app, open **Settings →
Server**, and enter the host and port. From the Android emulator, the machine
running the backend is `10.0.2.2`, not `localhost`. The form validates before it
saves and can probe `/health` first, so a typo is refused with a reason instead
of becoming a silent default.

## What it does

Four tabs, and three screens that open above them.

| | |
|---|---|
| **Today** | One day's entries under the backend's roll-up of that day. Swipe or step between days; today is the last page. |
| **Insights** | The patterns the backend found, the evidence behind each, what was withdrawn and why, and when things happen. |
| **Calendar** | A month at a glance, and a day's entries when you tap one. |
| **Settings** | Server address, appearance, topics and aliases. |
| *Compose* | The guided flow or freeform, then confirm the feelings, then what the diary already knew. |
| *Entry detail* | Read an entry as written; edit it deliberately; resolve a conflict by hand. |

Four fixed daily reminders (09:00, 12:00, 18:00, 21:00) open the composer when
tapped, from a cold start or while running.

## Layout

```
lib/
├── main.dart                        # error handlers, cookie jar, retry policy, runApp
├── app.dart                         # router, theming, splash, reminder wiring
├── core/                            # never imports from features/
│   ├── audio/                       # recording a spoken answer, behind a fake-able plugin
│   ├── auth/                        # loading | signedOut | signedIn (off for this app)
│   ├── config/app_config.dart       # every backend path lives here
│   ├── diary/                       # the domain: models, wire decoding, one API per resource
│   ├── network/                     # typed client, sealed ApiError, retry policy
│   ├── notifications/               # the four daily reminders
│   ├── settings/                    # backend address, theme mode, chosen paper
│   ├── theme/                       # three journal palettes, the type scale, metrics
│   └── widgets/                     # journal primitives, feeling picker, intensity dials
└── features/                        # a feature never imports another feature
    ├── shell/  today/  compose/  entry/  calendar/  insights/  settings/  topics/
```

## Talking to the backend

Reads take a decoder and give back a model; the client never returns `dynamic`:

```dart
final entries = await ref.read(entriesApiProvider).listByDate(date);
```

Failures arrive as a sealed `ApiError`, so the compiler catches an unhandled
case, and `apiRetryPolicy` decides which are worth retrying — a dropped
connection or a 5xx, twice, inside a second. A missing server address, an
expired session and a 4xx surface at once, because asking again cannot change
them.

Edits carry the version they were based on. A rejected one comes back as
`EntryOutOfDate` carrying the entry as actually stored, and the conflict screen
shows both versions and lets the user choose. Nothing is merged automatically:
that would produce text they never wrote.

## Toolchain on this machine

- Flutter via Homebrew; Android SDK at
  `/opt/homebrew/share/android-commandlinetools`, JDK 17 at
  `/opt/homebrew/opt/openjdk@17`.
- **Android builds and runs.**
- **iOS and macOS do not build here** — only the Command Line Tools are
  installed. The iOS `NSAllowsLocalNetworking` and microphone entries and the
  macOS audio-input entitlement are in place but have never been compiled.
- Web needs Chrome, which is not installed.
