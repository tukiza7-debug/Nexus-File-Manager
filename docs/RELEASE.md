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

## Signing (Android)

Since v1.0.2 (audit item 23) the Gradle build signs release artifacts with a
real keystore when credentials are provided as repository secrets, and falls
back to the debug keystore otherwise so CI source builds stay installable:

| GitHub secret | Contents |
|---------------|----------|
| `KEYSTORE_BASE64` | Base64 of the release `.jks`/`.keystore` file |
| `KEYSTORE_PASSWORD` | Keystore password |
| `KEY_ALIAS` | Key alias inside the keystore |
| `KEY_PASSWORD` | Key password |

The workflow decodes `KEYSTORE_BASE64` into `android/key.properties`
(git-ignored) before running Gradle. Locally you can simply drop a
`key.properties` file next to `android/build.gradle`. After every build the
workflow prints the APK certificate SHA-256 (`apksigner verify --print-certs`)
so logs prove the same key is used across releases.

> **Signing-key incompatibility note:** Android refuses to *update* an
> installed app when the signing key changes. Every build up to and including
> v1.0.5 was signed with a per-run CI debug key — the certificates verifiably
> differ between releases (v1.0.2 SHA-256 `3522…5152`, v1.0.5 SHA-256
> `E638…F10F`, both `CN=Android Debug`), which is why those builds could not
> update over each other. From **v1.1.0** the dedicated release keystore is
> provisioned through repository secrets and every current and future build
> uses the SAME key:
>
> - Alias: `nexus-release`
> - Certificate SHA-256: `D3:83:27:8D:B7:AA:78:61:46:D8:BC:68:5C:AA:D4:DC:2B:1B:70:60:AE:08:B7:68:91:DB:19:46:C3:71:78:1C`
> - Valid until: 30 September 2056
>
> Installing v1.1.0 (or any later build) over a v1.0.x installation requires a
> **one-time uninstall first**; app-private data is removed by that uninstall,
> so back up before switching. From v1.1.0 onward updates install directly
> over each other. Keep the `.jks` backup forever — losing it means losing
> the ability to ship updates, and never commit it to git (it is ignored).

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
