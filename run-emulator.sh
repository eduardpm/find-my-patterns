#!/usr/bin/env bash
#
# Boot the Android emulator, build the app, install it, and launch it.
#
# One entry point for the whole loop, so the day-to-day case is `./run-emulator.sh` and nothing
# else. Safe to re-run: a booted emulator is reused rather than started twice, and the build is
# incremental. See ANDROID-EMULATOR-SETUP.md for the one-time SDK install this depends on.
#
# Usage:
#   ./run-emulator.sh                 boot (with a window), build, install, launch
#   ./run-emulator.sh --headless      no emulator window -- for screenshots and CI
#   ./run-emulator.sh --no-build      skip the build; just boot and launch what is installed
#   ./run-emulator.sh --backend       also start the backend if nothing is on its port
#   ./run-emulator.sh --stop          shut the emulator down
#
set -euo pipefail

readonly AVD_NAME="mood_diary"
readonly PACKAGE="com.palkomate.find_my_patterns"
# The debug build carries applicationIdSuffix ".debug", so the package and the activity class have
# different prefixes. The `.MainActivity` shorthand resolves against the package and fails here.
readonly ACTIVITY="com.palkomate.find_my_patterns.MainActivity"
readonly BACKEND_PORT=8000

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}"
export ANDROID_HOME="${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"

HEADLESS=false
BUILD=true
START_BACKEND=false
STOP_ONLY=false

for arg in "$@"; do
  case "$arg" in
    --headless) HEADLESS=true ;;
    --no-build) BUILD=false ;;
    --backend)  START_BACKEND=true ;;
    --stop)     STOP_ONLY=true ;;
    -h|--help)  sed -n '3,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg (try --help)" >&2; exit 2 ;;
  esac
done

say()  { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m!  \033[0m %s\n' "$1" >&2; }
die()  { printf '\033[1;31mx  \033[0m %s\n' "$1" >&2; exit 1; }

if [[ "$STOP_ONLY" == true ]]; then
  if adb devices | grep -q emulator; then
    adb emu kill >/dev/null 2>&1 || true
    say "Emulator stopped."
  else
    say "No emulator running."
  fi
  exit 0
fi

# ---- Preconditions -------------------------------------------------------------------------
# Checked up front with actionable messages, because the failure that actually happens on a fresh
# machine is a missing SDK package, and Gradle's version of that error is not a helpful one.

[[ -d "$JAVA_HOME" ]] || die "JDK 17 not found at $JAVA_HOME. Install it: brew install openjdk@17"
[[ -d "$ANDROID_HOME" ]] || die "Android SDK not found at $ANDROID_HOME. See ANDROID-EMULATOR-SETUP.md"
command -v adb >/dev/null || die "adb not on PATH. Install platform-tools -- see ANDROID-EMULATOR-SETUP.md"
command -v emulator >/dev/null || die "emulator not on PATH. Install it -- see ANDROID-EMULATOR-SETUP.md"

if ! emulator -list-avds | grep -qx "$AVD_NAME"; then
  die "AVD '$AVD_NAME' does not exist. Create it:
  avdmanager create avd -n $AVD_NAME -k 'system-images;android-35;google_apis;arm64-v8a' -d pixel_7
  printf 'hw.keyboard=yes\\n' >> ~/.android/avd/$AVD_NAME.avd/config.ini"
fi

# ---- Backend -------------------------------------------------------------------------------

if [[ "$START_BACKEND" == true ]]; then
  if lsof -nP -iTCP:"$BACKEND_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    say "Backend already listening on :$BACKEND_PORT."
  elif [[ ! -f "$REPO_ROOT/backend/dist/main.js" ]]; then
    warn "Backend is not built (backend/dist/main.js missing). Run: cd backend && npm ci && npm run build"
  else
    say "Starting backend on 127.0.0.1:$BACKEND_PORT ..."
    # `exec` inside the subshell replaces its stdio *before* npm is spawned, so the backend cannot
    # inherit this script's stdout. Backgrounding alone is not enough -- the child keeps the
    # inherited pipe open, and `./run-emulator.sh | tail` then hangs until the backend exits.
    (
      exec </dev/null >/tmp/mood-diary-backend.log 2>&1
      cd "$REPO_ROOT/backend" && exec npm start
    ) &
    disown 2>/dev/null || true
    sleep 3
    if lsof -nP -iTCP:"$BACKEND_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
      say "Backend up. Logs: /tmp/mood-diary-backend.log"
    else
      warn "Backend did not come up. Check /tmp/mood-diary-backend.log"
    fi
  fi

  # The API only queues analysis jobs; this second process is what actually runs the model. Without
  # it, topics and patterns are never computed and an edited entry never gets a new feeling
  # proposed -- the queue just grows. It needs Ollama reachable on its configured URL.
  if pgrep -f 'inference/worker' >/dev/null 2>&1; then
    say "Inference worker already running."
  elif [[ ! -f "$REPO_ROOT/backend/dist/inference/worker.js" ]]; then
    warn "Inference worker is not built. Run: cd backend && npm run build"
  else
    say "Starting inference worker ..."
    (
      exec </dev/null >/tmp/mood-diary-worker.log 2>&1
      cd "$REPO_ROOT/backend" && exec npm run start:worker
    ) &
    disown 2>/dev/null || true
    sleep 2
    if pgrep -f 'inference/worker' >/dev/null 2>&1; then
      say "Worker up. Logs: /tmp/mood-diary-worker.log"
    else
      warn "Worker did not start. Check /tmp/mood-diary-worker.log"
    fi
  fi
fi

# ---- Emulator ------------------------------------------------------------------------------

if adb devices | grep -q "emulator-.*device$"; then
  say "Emulator already running -- reusing it."
else
  say "Booting $AVD_NAME$([[ "$HEADLESS" == true ]] && echo ' (headless)')..."
  # Audio is deliberately left ON: the composer records spoken answers and sends them to the
  # backend for transcription, and `-no-audio` silently removes the emulator's microphone, so
  # recording fails in a way that looks like an app bug.
  emulator_args=(-avd "$AVD_NAME" -no-boot-anim -no-snapshot)
  [[ "$HEADLESS" == true ]] && emulator_args+=(-no-window)
  ( nohup emulator "${emulator_args[@]}" </dev/null >/tmp/mood-diary-emulator.log 2>&1 & disown ) 2>/dev/null

  say "Waiting for boot (first boot can take 2-5 minutes)..."
  adb wait-for-device
  # getprop is empty, not 0, until quite late in boot -- so compare against "1" rather than testing
  # for falsiness, or the loop exits while the launcher is still starting.
  until [[ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; do
    sleep 3
  done
  say "Booted."
fi

# ---- Build, install, launch ----------------------------------------------------------------

if [[ "$BUILD" == true ]]; then
  say "Building and installing..."
  ( cd "$REPO_ROOT/mobile" && flutter install --debug )
else
  adb shell pm list packages | grep -q "$PACKAGE" \
    || die "$PACKAGE is not installed and --no-build was given. Re-run without --no-build."
fi

say "Launching..."
adb shell am start -n "$PACKAGE/$ACTIVITY" >/dev/null

sleep 3
if crash=$(adb logcat -d -s AndroidRuntime:E | tail -20) && [[ -n "$crash" ]]; then
  warn "AndroidRuntime errors in the log:"
  printf '%s\n' "$crash" >&2
fi

if ! lsof -nP -iTCP:"$BACKEND_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  warn "Nothing is listening on :$BACKEND_PORT -- the app will show a connection error."
  warn "Start it with: ./run-emulator.sh --backend   (or: cd backend && npm start)"
fi

say "Running. In the app, Settings should be host 10.0.2.2, port $BACKEND_PORT."
say "Screenshot:  adb exec-out screencap -p > shot.png"
say "Stop:        ./run-emulator.sh --stop"
