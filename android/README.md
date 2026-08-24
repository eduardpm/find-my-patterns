# Mood Pattern Diary — Android app

Native Android client for the Mood Pattern Diary backend (see `../backend`). Built with Kotlin,
Jetpack Compose and Material 3, per `specs/002-mood-pattern-diary-mobile/plan.md`. Talks to the
backend over plain HTTP on your home LAN — there's no cloud service and no login screen (see
FR-018/FR-019 in the spec).

> **Update**: this project now builds successfully — `./gradlew assembleDebug` produces a working
> debug APK, `testDebugUnitTest` passes (12/12), and `ktlintCheck` is clean, verified with a locally
> installed JDK 17 + Gradle 8.9 + Android SDK 35 (no emulator/device was available to actually run
> it, so UI behavior is still unverified beyond code review). See "A note on how this was built and
> verified" at the bottom for exact versions and what got fixed.

## Prerequisites

- **Android Studio** (Ladybug/2024.2 or newer recommended) — the easiest way to get a matching
  JDK, Android SDK, and emulator all in one install. Standalone `sdkmanager`/`gradle` also work if
  you'd rather not install the IDE.
- **JDK 17** (Android Studio bundles one; if you're building from the command line, make sure
  `JAVA_HOME` points at a JDK 17 install — this project targets Java 17 bytecode).
- **Android SDK** with:
  - Platform `android-35` (compileSdk/targetSdk)
  - A device or emulator running **Android 8.0 (API 26)** or newer (minSdk 26)
- A phone (or emulator) on the **same network** as the machine running the backend, since the app
  only talks to the backend over the LAN (no offline mode, per FR-020).

## Opening the project

1. Open Android Studio → **Open** → select the `android/` directory (this directory, the one
   containing `settings.gradle.kts`).
2. Android Studio will offer to generate the Gradle wrapper JAR/scripts (`gradlew`, `gradlew.bat`,
   `gradle/wrapper/gradle-wrapper.jar`) automatically on first sync, since only
   `gradle/wrapper/gradle-wrapper.properties` (pinning Gradle 8.9) is checked in — see the note at
   the bottom. Let it sync; it will download Gradle 8.9, AGP 8.7.2 and the Kotlin 2.1.0 toolchain.
3. If you'd rather do it from the command line first: install Gradle 8.9+ locally, `cd android`,
   then run `gradle wrapper` once to generate `gradlew`. After that, use `./gradlew` for everything
   below.

## Running the backend first

This app has nothing to talk to until the backend (`../backend`) is running and reachable from
your phone:

```sh
cd ../backend
# see backend/README.md for the full setup; roughly:
npm install && npm run build && npm start
```

Start the backend with `HOST=0.0.0.0`; its secure default is `127.0.0.1`, which is intentionally not
reachable from another device. Only use the broader binding on a trusted LAN or VPN, never through a
public port-forward.
Note the machine's local IP address (e.g. `192.168.1.42`, from `ip addr` / `ifconfig` / your OS's
network settings) — you'll need it in the next step.

## Pairing the app with your backend (Settings screen)

There's no auto-discovery (see `research.md` §6) — you tell the app where the backend lives once:

1. Launch the app and open the **Settings** tab (bottom navigation bar).
2. Enter the backend machine's LAN IP address (e.g. `192.168.1.42`) and port (`8000` by default,
   the backend's default).
3. Tap **Save**. The app immediately starts using that address for every request — no restart
   needed (`NetworkModule` rewrites request URLs live via an OkHttp interceptor, see
   `data/NetworkModule.kt`).
4. If the address is wrong, unreachable, or the backend isn't running, every screen shows a
   Snackbar like "Can't reach the diary server…" instead of crashing or silently failing (FR-020)
   — double check the IP/port and that your phone is on the same Wi-Fi.

## Building / running

From Android Studio: press **Run** (▶) with a device/emulator selected — this is the easiest path
and doesn't require touching the command line.

From the command line, once `./gradlew` exists (see "Opening the project" above):

```sh
./gradlew installDebug     # build + install the debug APK on a connected device/emulator
./gradlew assembleDebug    # just build the APK, at app/build/outputs/apk/debug/
./gradlew testDebugUnitTest  # run the JUnit5 unit tests (ReminderSchedulerTest)
```

The debug build installs alongside any release build under the applicationId suffix `.debug`
(`com.moodpatterndiary.app.debug`), so you can have both on a device at once.

### Notification permission & exact alarms

On first launch the app requests the `POST_NOTIFICATIONS` runtime permission (Android 13+) and
arms the four daily reminder alarms (9:00, 12:00, 18:00, 21:00 — FR-013). On Android 12+, if the
device requires the user to separately grant "Alarms & reminders" access for exact alarms, the app
falls back to an inexact alarm rather than crashing (see `notifications/ReminderScheduler.kt`) —
for best results grant that permission too (Settings → Apps → Mood Pattern Diary → Alarms &
reminders).

## Project layout

```
android/
├── settings.gradle.kts, build.gradle.kts, gradle.properties   # Gradle project config
└── app/
    ├── build.gradle.kts            # dependencies: Compose/Material3, Retrofit+OkHttp, DataStore, WorkManager
    └── src/
        ├── main/
        │   ├── AndroidManifest.xml
        │   ├── kotlin/com/moodpatterndiary/app/
        │   │   ├── MainActivity.kt, MoodPatternDiaryApp.kt
        │   │   ├── ui/            # Compose screens (Today, EntryComposer, GuidedQuestionFlow,
        │   │   │                  # EntryDetail, Insights, MonthlyCalendar, Settings) + theme
        │   │   ├── data/          # Retrofit API interfaces, repositories, NetworkModule, SettingsStore
        │   │   ├── domain/        # plain Kotlin models mirroring the backend's data-model.md
        │   │   └── notifications/ # AlarmManager-based reminder scheduling/receiving/posting
        │   └── res/
        └── test/                  # ReminderSchedulerTest (JUnit5, pure logic, no device needed)
```

## A note on how this was built and verified

This app was originally written end-to-end by an AI coding agent in a sandbox with no JDK, no
Android SDK, no `adb`, no emulator, and no Gradle installed, so none of it had ever been compiled.
It was then set up and built in that same sandbox (no root/sudo required — everything installed to
the user's home directory):

- **Temurin JDK 17.0.20** downloaded from Adoptium, extracted to `~/tools/jdk-17.0.20+8`.
- **Gradle 8.9** (matching `gradle-wrapper.properties`) downloaded from `services.gradle.org`,
  extracted to `~/tools/gradle-8.9`, then used to run `gradle wrapper --gradle-version 8.9` inside
  `android/` to (re)generate `gradlew`, `gradlew.bat`, and `gradle/wrapper/gradle-wrapper.jar`
  (those three are still gitignored, same as any Gradle project — regenerate them the same way, or
  let Android Studio do it, if you're starting from a fresh clone).
- **Android SDK** command-line tools (`commandlinetools-linux-11076708_latest.zip`), used to install
  `platform-tools`, `platforms;android-35`, and `build-tools;35.0.0` into `~/Android/Sdk` and to
  accept all SDK licenses. `android/local.properties` (gitignored, machine-specific) points at it.

With that in place, `./gradlew clean assembleDebug testDebugUnitTest ktlintCheck` runs clean.
Six real bugs turned up during the first build and were fixed (all were subtle Compose/Kotlin API
mistakes that only a real compiler catches — this is exactly the kind of thing that's worth
actually building for, not just reviewing by eye):

- `rememberSaveable` was imported from `androidx.compose.runtime` instead of its real package,
  `androidx.compose.runtime.saveable` (`EntryComposer.kt`, `GuidedQuestionFlow.kt`) — this cascaded
  into several unrelated-looking type-inference errors in the same files once fixed.
- `AppNavHost.kt` used a `by` delegate on a Compose `State` without importing
  `androidx.compose.runtime.getValue` (a very easy one to miss since the delegate syntax otherwise
  looks correct).
- `EntryDetailScreen.kt` used the `.dp` unit extension without importing
  `androidx.compose.ui.unit.dp`.
- `ApiResult.kt` tried to read Retrofit's `HttpException.code` as a Kotlin property (`$code` in a
  string template); it's a Java method (`code()`), not a getter-style property, so it needs to be
  called explicitly: `${code()}`.
- ktlint's default function-naming rule doesn't know that `@Composable` functions are
  conventionally PascalCase (e.g. `TodayScreen()`) — added the documented `.editorconfig` override
  (`ktlint_function_naming_ignore_when_annotated_with = Composable`) rather than renaming correct,
  idiomatic Compose code.

What's still **not** verified: no emulator or physical device was available, so nothing has
actually run on Android — UI rendering, navigation feel, real network calls against the backend,
and notification behavior are all unverified beyond static compilation and the one pure-logic unit
test suites (`ReminderSchedulerTest` and `ConflictMappingTest`, 12/12 passing). A few non-blocking deprecation warnings remain
(older `Icons.Filled.*` variants that have `AutoMirrored` replacements, and `LocalLifecycleOwner`
having moved packages) — harmless, but worth cleaning up next time you touch those files.

The launcher icon is a simple hand-drawn vector adaptive icon (`res/drawable/ic_launcher_*.xml`,
`res/mipmap-anydpi-v26/`) rather than a designed asset — swap it for real artwork whenever
convenient.
