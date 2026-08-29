---
name: fork-app
description: Start a new app from this bootstrap base — copy the tree, rename the Dart package and the platform identifiers, reset AppConfig, clear the placeholder screens. Use when forking bootstrap, starting a new app from the base, or renaming a fork that still carries the base's identity.
---

# Fork the base into a new app

Every app in the portfolio starts as a copy of this repo. The work is a rename
sweep and a reset — no feature code moves. A fork that still answers to
`bootstrap` anywhere will collide with the base on a device that has both
installed, so the sweep in step 7 is the real completion criterion.

## 1. Settle the identity first

Ask the user for anything not already given, and do not guess:

| Value | Example | Used by |
|---|---|---|
| package name (snake_case) | `travel_ez` | `pubspec.yaml`, every Dart import |
| display name | `Travel EZ` | launcher label, splash, About |
| bundle id | `com.palkomate.travel_ez` | Android, iOS, macOS |
| target directory | `~/projects/travel-ez` | the copy |
| sign-in required? | yes / no | `AppConfig.requireAuth` |

## 2. Copy the tree

```bash
rsync -a --exclude build --exclude .dart_tool --exclude .git --exclude coverage \
  ~/projects/bootstrap/ ~/projects/<target>/
cd ~/projects/<target> && git init && flutter pub get
```

Build output and the base's git history stay behind. `CONSTITUTION.md` and
`CLAUDE.md` come along unchanged — the constitution is copied verbatim, never
edited per fork.

## 3. Rename the Dart package

`pubspec.yaml` `name:`, and every `package:bootstrap/…` import across `lib/` and
`test/`:

```bash
grep -rl 'package:bootstrap/' lib test | xargs sed -i '' 's/package:bootstrap\//package:<new_name>\//g'
sed -i '' 's/^name: bootstrap$/name: <new_name>/' pubspec.yaml
```

Also set `description:` and reset `version:` to `1.0.0+1`. Delete the stale
`bootstrap.iml`.

## 4. Rename the platform identifiers

Each of these carries the old name:

- `android/app/build.gradle.kts` — `namespace` and `applicationId`
- `android/app/src/main/AndroidManifest.xml` — `android:label`
- `ios/Runner.xcodeproj/project.pbxproj` — every `PRODUCT_BUNDLE_IDENTIFIER`
- `ios/Runner/Info.plist` — display name
- `macos/Runner/Configs/AppInfo.xcconfig` — `PRODUCT_NAME`, bundle id
- `web/index.html`, `web/manifest.json` — title, name, description
- `linux/runner/my_application.cc`, `windows/runner/Runner.rc` — window title

## 5. Reset `lib/core/config/app_config.dart`

- `appName` — the display name.
- `appVersion` — `1.0.0`, matching `pubspec.yaml`. A test fails if they drift.
- `storagePrefix` — the new package name. This is what keeps a fork from
  reading the base's stored settings on a device holding both.
- `requireAuth` — as answered in step 1.
- `healthPath`, `sessionPath` — only if this app's backend differs from the
  shared contract.

## 6. Clear the placeholders

`lib/features/home/`, `history/`, and `insights/` are `PlaceholderView` screens
that exist to be replaced. Keep the four-tab shell until the app has a reason
not to; rename tabs in `lib/features/shell/app_shell.dart`.

Leave `core/`, `auth/`, `settings/`, and `shell/` alone — that is the base the
fork exists to inherit.

Rewrite `README.md` for the new app: what it does, its backend contract, its
screens. Keep the pointer to `CONSTITUTION.md`.

## 7. Sweep, then verify

```bash
grep -ril bootstrap --exclude-dir=build --exclude-dir=.dart_tool --exclude-dir=.git .
```

Done when this returns nothing, or only lines that name the base on purpose (a
README sentence saying which base the app was forked from). Anything else is a
missed rename.

Then run the `verify` skill. The fork is finished when its gate is green on the
copy: format clean, analyze silent, every inherited test passing, coverage at or
above 95%.
