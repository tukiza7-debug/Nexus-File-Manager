# Release Process

How Nexus File Manager releases are cut, built and published. Everything here
is automated except tagging — no local build environment is required.

## Pipelines

| Workflow | File | Trigger | Produces |
|----------|------|---------|----------|
| **CI** | `.github/workflows/ci.yml` | every push to `main`, PRs, manual | `flutter analyze` + `flutter test` gate |
| **Build APK (All Types) + Auto Versioning** | `.github/workflows/build-apk.yml` | every push to `main`, `v*` tags, manual | Universal + per-ABI APKs and a Play-Store AAB; tags also create a release, `main` pushes update the rolling **latest** pre-release |
| **Release (desktop + iOS)** | `.github/workflows/release.yml` | `v*` tags, manual | Windows zip, Linux tar.gz, macOS app zip, iOS sideload zip — attached to the tag's release |

All three pin **Flutter 3.47.6 stable** so analysis, tests and builds behave
identically everywhere. (The APK workflow originally ran unpinned
`channel: stable`, which let a newer Flutter break AGP/Kotlin/theme APIs —
that is why version pins are mandatory now.)

## Cutting a release

```bash
# 1. Bump the version in pubspec.yaml (e.g. 1.0.0+1 -> 1.0.1+2)
# 2. Commit the bump, then tag and push:
git tag v1.0.1
git push origin main v1.0.1
```

Pushing the tag fires both build workflows. The APK workflow derives the
version name from the tag (`v1.0.1` → `1.0.1`) and the version code from the
GitHub run number, stamps both into the build, and creates the release with
`generate_release_notes: true`. The Release workflow attaches the desktop and
iOS artifacts to the same release.

Artifacts produced per tag:

| File | Platform | Contents |
|------|----------|----------|
| `NexusFileManager-universal-v*.apk` | Android 6.0+ | All ABIs in one installable APK |
| `NexusFileManager-arm64-v8a-v*.apk` | Most modern phones | Recommended per-device install |
| `NexusFileManager-armeabi-v7a-v*.apk` | Older 32-bit ARM devices | |
| `NexusFileManager-x86_64-v*.apk` | Emulators / x86 devices | |
| `NexusFileManager-v*.aab` | Google Play | Upload bundle |
| `nexus-file-manager-windows-x64.zip` | Windows 10+ x64 | Runner `Release/` folder — unzip and run `nexus_file_manager.exe` |
| `nexus-file-manager-linux-x64.tar.gz` | Linux x64 (GTK 3) | Build bundle — `./nexus_file_manager` |
| `nexus-file-manager-macos-arm64.zip` | macOS 12+ Apple Silicon | `.app` bundle (unsigned) |
| `nexus-file-manager-ios-unsigned.zip` | iOS 13+ | `Payload/Runner.app` for sideloading (unsigned) |

Continuous builds from `main` (no tag) overwrite the **Latest Build (Auto)**
pre-release tagged `latest` with fresh APKs — handy for testers who just want
the newest build.

## Signing status (important)

CI artifacts are built **without production signing credentials** — the repo
deliberately contains no secrets:

- **Android** — release builds fall back to the debug keystore so the APK is
  installable for testing. Before publishing to Google Play, generate a
  release keystore, add `key.properties` (git-ignored) and a
  `signingConfigs.release` block in `android/app/build.gradle`, and switch the
  release build type to it.
- **macOS / iOS** — unsigned. On macOS, right-click the app and choose
  **Open** on first run (Gatekeeper). On iOS, sideload via Xcode, Apple
  Configurator, or AltStore with your own development certificate.

## Continuous integration

Every push and pull request runs the CI workflow: dependency resolution,
`flutter analyze` (strict lint set) and the full `flutter test` suite. Keep CI
green before tagging; both build workflows use the same pinned Flutter version
so CI results predict build results.

## Versioning

`pubspec.yaml` follows `MAJOR.MINOR.PATCH+BUILD`. The tag must match the
version (`v1.0.1` ↔ `1.0.1`). Continuous builds stamp `version: <name>+<run
number>` into pubspec at build time only — the committed file stays untouched.
Feature releases may add tables to the SQLite schema — bump `DbService`'s
schema version and provide a migration path in the same change.
