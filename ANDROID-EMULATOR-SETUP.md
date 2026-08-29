# Android Emulator on Apple Silicon

How to run the Android client (`android/`) on this Mac via the Android Emulator — command-line only, no Android Studio, scriptable for an AI agent, no sudo anywhere.

## Why the emulator

The app is native Kotlin/Jetpack Compose. It cannot run on macOS. On Apple Silicon the Android Emulator runs **ARM64 (`arm64-v8a`) system images** directly through Hypervisor.framework — fast, no Rosetta or HAXM needed.

## Prerequisites (already done on this machine)

- Homebrew at `/opt/homebrew`
- JDK 17: `brew install openjdk@17`
- Android cmdline-tools: `brew install --cask android-commandlinetools`
- SDK licenses accepted: `yes | sdkmanager --licenses`

Only the command-line tools themselves are installed by that cask. `platform-tools`,
`emulator`, the platform, and the system image all still come from step 1 below — none of
the one-time setup is skippable on a fresh machine.

## Environment (put in shell or `~/.zshrc`)

```sh
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
```

## One-time setup (the long part — ~3 GB of downloads)

### 1. Install SDK packages

```sh
sdkmanager "platform-tools" \
          "platforms;android-35" \
          "build-tools;35.0.0" \
          "emulator" \
          "system-images;android-35;google_apis;arm64-v8a"
```

Downloads ~2 GB. The `arm64-v8a` image is the Apple Silicon native one — do NOT use `x86_64`.

### 2. Create an AVD

```sh
echo no | avdmanager create avd \
  -n mood_diary \
  -k "system-images;android-35;google_apis;arm64-v8a" \
  -d pixel_7 \
  --force
```

`avdmanager` creates the AVD with `hw.keyboard=no`, which makes the emulator ignore the Mac's
physical keyboard -- you can click the on-screen keys but not type. Turn it on before first boot:

```sh
printf 'hw.keyboard=yes\n' >> ~/.android/avd/mood_diary.avd/config.ini
```

`avdmanager` prints `Error: Could not load devices from .../devices.xml` here. It is harmless —
the system image ships no `devices.xml` and the tool falls back to the bundled profile. Confirm
with `avdmanager list avd`; the AVD should show `Device: pixel_7 (Google)`.

### 3. First Gradle build pulls another ~1 GB

```sh
cd android && ./gradlew assembleDebug
```

Downloads Gradle 8.9, AGP 8.7.2, Kotlin 2.1.0, Compose BOM, Retrofit, OkHttp, etc.

If Gradle can't find the SDK, create `android/local.properties`:
```
sdk.dir=/opt/homebrew/share/android-commandlinetools
```

## Daily workflow

### 4. Start the backend (already running)

```sh
cd backend && npm start    # 127.0.0.1:8000
```

### 5. Boot the emulator

```sh
$ANDROID_HOME/emulator/emulator -avd mood_diary \
  -no-window -no-audio -no-boot-anim -no-snapshot &
```

First boot: 2–5 minutes (creates userdata partition). Subsequent boots: ~30s.

Wait for boot:

```sh
adb wait-for-device
until [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = "1" ]; do sleep 3; done
```

### 6. Build, install, and launch

```sh
cd android && ./gradlew installDebug
adb shell am start -n com.moodpatterndiary.app.debug/com.moodpatterndiary.app.MainActivity
```

The debug build carries `applicationIdSuffix = ".debug"`, so the package is
`com.moodpatterndiary.app.debug` while the activity class stays `com.moodpatterndiary.app.MainActivity`.
The `.MainActivity` shorthand resolves against the package and fails here.

### 7. Configure the backend address

Open the Settings tab in the app → host: `10.0.2.2` → port: `8000` → Save.

**Why `10.0.2.2`:** The emulator's virtual NAT maps it to the host's `127.0.0.1`. The backend stays on its secure default bind — no `HOST=0.0.0.0` needed. Cleartext HTTP is already enabled in the app manifest.

**If you enable backend auth:** with `AUTH_ENABLED=true` the backend guards every non-public
route behind a `diary_session` cookie, and the Android client has no login flow — every
request comes back `401`. Leave auth off (the default) when testing against the emulator.

## Verification (all agent-checkable)

```sh
adb devices                                         # emulator-5554 listed
adb shell getprop sys.boot_completed                # 1
adb shell pm list packages | grep moodpatterndiary  # com.moodpatterndiary.app.debug
adb logcat -d -s AndroidRuntime:E | tail -20        # no FATAL EXCEPTION
adb logcat -d | grep -i "mood" | tail -20           # app has logged something
adb exec-out screencap -p > /tmp/diary.png           # visual check
```

Functional check: the Today tab should render entries from the backend, and no "Can't reach the diary server" snackbar should appear.

Full build verification:

```sh
cd android && ./gradlew testDebugUnitTest ktlintCheck
```

## First run: verified 2026-08-24

The app has now actually run on the emulator. Every item the README listed as unverified was
exercised on a `pixel_7` AVD (`system-images;android-35;google_apis;arm64-v8a`, headless):

- **Compose rendering** — all four tabs render. No crashes; `adb logcat -s AndroidRuntime:E` stayed empty.
- **Navigation** — Today → New entry → Cancel, and all four bottom-nav destinations, navigate cleanly.
- **Real network calls** — five endpoints returned `200 OK` over `10.0.2.2:8000`, and the responses
  deserialized into the UI (the guiding question on the New entry screen is server-supplied):

  ```
  GET /feelings                        200 (465 B)
  GET /entries?date=2026-08-24         200 (14 B)
  GET /guiding-questions               200 (1193 B)
  GET /monthly-summary?month=2026-08   200 (1195 B)
  GET /insights                        200 (40 B)
  ```

- **Permissions** — the `POST_NOTIFICATIONS` dialog appears on first launch, as expected, and
  granting it is a normal tap.
- **Build health** — `./gradlew testDebugUnitTest ktlintCheck` passes (12 unit tests).

Still unverified: **writing** an entry (the POST path) and **notification delivery** — the reminder
alarm firing, and boot re-arming via `RECEIVE_BOOT_COMPLETED`. Everything checked above is read-only.

If the app crashes on launch, start with `adb logcat -s AndroidRuntime:E` and work backward from the stack trace.

## Cleanup

```sh
adb emu kill                      # stop emulator
adb kill-server                    # done
```

## Numbers

| Item | Size |
|------|------|
| SDK packages download | ~2 GB |
| Gradle + dependencies first download | ~1 GB |
| Emulator RAM usage | ~2 GB |
| AVD userdata image on disk | ~6 GB |
| First emulator cold boot | 2–5 min |
| Subsequent emulator boot (no snapshot) | ~30s |