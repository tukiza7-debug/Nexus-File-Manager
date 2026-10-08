# Changelog

All notable changes to Nexus File Manager are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/) and the
project adheres to semantic versioning for the pubspec `MAJOR.MINOR.PATCH` part.

## [1.1.0+26] — 2026-10-08

Fifty-item engineering audit across data safety, automation, Android
integration, Teleport, interaction speed, accessibility and code hygiene.
No features were removed and the architecture (Riverpod StateNotifiers,
FileOpsService, OperationJournal) is unchanged.

### Data safety (items 1–12)

- Copying a file onto itself now lands a unique `name (2).ext` copy instead of
  clobbering or corrupting the source; move-onto-itself is a no-op.
- Directory-rename undo/redo works across devices (safe move-back with
  cross-device fallback), and `movePaths` refuses to move a folder into its
  own descendant.
- Zip extraction records every produced path so Deep Undo removes exactly what
  the extraction created — never pre-existing destination content.
- Overwriting through copy/rename keeps the previous file in the journal
  (delete-with-backup) so the overwrite itself is undoable.
- Android cross-device deletes fall back to a same-volume `.nexus-trash`
  folder with 30-day retention surfaced through Empty Trash.
- File-name validation (traversal, reserved device names, control characters,
  length) is enforced at every mutating entry point.
- Secure Freeze now checks destinations as well as sources, and path
  comparison is case-insensitive on Windows.
- Zip-slip protection plus total-size / entry-count limits and isolate-based
  extraction for large archives.
- OperationJournal handles per-step errors without aborting whole batches,
  invalidates the redo stack on new work, and metadata edits are atomic with
  journaled backups.
- Unfreeze uses a single recursive command per platform (`chmod -R u+w` /
  `attrib -R`) instead of per-file system calls.

### Automation (items 13–19)

- Watcher: per-path event debounce, multiple listeners per folder, and a
  polling fallback for filesystems without native events.
- Watchdog: echo suppression for self-triggered events plus loop and cycle
  guards so rules can no longer amplify themselves.
- Scheduler: per-job running lock prevents overlapping ticks, failures record
  an `error: …` status instead of failing silently, and mirror jobs run only
  the explicitly selected mirror.
- Mirror: deletions go through the journal trash, mtime-aware comparison, a
  manifest for resumable syncs, and a dry-run mode.
- Versioning: size+mtime+hash dedupe, retention caps and path-hash keys.
- Macro recorder exposes a broadcast behaviour signal so the recording FAB
  reacts reliably; PipelineService guarantees run() executes exactly what
  plan() predicted.

### Android (items 20–23)

- Incoming share names are sanitized before writing; background copies stream
  in chunks with a free-space check.
- Open-with uses ACTION_VIEW through a FileProvider with a share-sheet
  fallback when no handler exists.
- Storage permissions are requested after the first frame via an onboarding
  gate (MANAGE_EXTERNAL_STORAGE / legacy / media permissions) with a limited
  mode.
- Release signing reads `android/key.properties` from CI secrets with an
  automatic debug-keystore fallback. The dedicated release keystore
  (`nexus-release`, certificate SHA-256 `D3:83:27:8D…78:1C`, valid until 2056)
  is now provisioned as repository secrets, so every build from v1.1.0 shares
  the same signature and future updates install directly over previous ones.
  Builds up to v1.0.5 used per-run debug keys (each release had a different
  certificate) and need a one-time uninstall before installing v1.1.0; the
  workflow now also prints the APK certificate SHA-256 after each build so
  signing consistency is verifiable in CI logs.

### Teleport (items 24–25)

- Discovery speaks ANNOUNCE/REPLY correctly (no more ping-pong), rate-limits
  replies per peer, escapes device-name separators and uses secure random
  device ids.
- Receiver gates transfers behind consent/pairing, validates sizes, never
  overwrites existing files, and stops all servers when disabled.

### Interaction speed (items 26–34)

- Single tap opens on touch devices (double-click stays desktop-only),
  drags use LongPressDraggable, and Alt-peek/inspector hints use
  platform-aware wording.
- Rebuild storms eliminated via provider `select()` and RepaintBoundary.
- Directory listing is async with an instant cache of the last listing and
  in-memory filtering; diff/merge/split/metadata heavy work runs in isolates.
- SQLite writes are transactional with a wasSelfOp cache for echo checks;
  spatial view persists positions on pan end only.
- Image previews decode at display size (`cacheWidth`/`cacheHeight`).

### Interface & accessibility (items 35–45)

- Edge-to-edge drawing respects system insets (SafeArea around shell and
  toasts).
- List view gains sortable headers with direction arrows; phones under 600 dp
  drop the SIZE/KIND columns; touch-mode hit targets are ≥ 48 dp.
- Text scaling is capped at 1.3 with a minimum body size of 11 sp.
- File tiles expose Semantics (name, size, selected state) plus a non-colour
  check-badge selection cue; contrast of dim text verified ≥ 4.5:1.
- Error toasts stay visible for 6 s and destructive operations offer an
  inline Undo action.
- The title-bar logo renders through flutter_svg; dead tap handlers removed.
- Phones get the sidebar as a Drawer; Ghost mode is hidden on touch devices.
- Infinite animations honour the OS "disable animations" setting.
- `use_build_context_synchronously` is an error-level lint; every async gap
  is guarded.
- Localization infrastructure ships with ARB files for **English, Bahasa
  Indonesia and Bahasa Malaysia** across shell, sidebar, onboarding and core
  toasts.

### Housekeeping (items 46–50)

- Every previously swallowed `catch (_) {}` reports through the central
  logger; user-initiated failures surface as toasts.
- Templates decode as UTF-8 (`allowMalformed`) so multi-byte text survives.
- Split validates part counts up front and cleans up partial outputs on
  failure.
- Two real data bugs found by the new tests were fixed: the internal JSON
  parser mis-parsed every number followed by more content, and model objects
  (macros) were serialized as `Instance of …` and could never round-trip.

### Tests

`flutter test` grew from 16 to **49 tests** covering journal undo/redo, the
same-file copy guard, overwrite+undo, zip extract+undo, rename validation,
watcher/watchdog behaviour, scheduler locks and error status, macro streams,
pipeline plan==run parity, split/template utilities and Teleport protocol
fuzzing. `flutter analyze` reports **zero issues** with
`use_build_context_synchronously` promoted to error.

## [1.0.2+3] — 2026-10-07

- Windows builds: pinned the release runner to `windows-2022` and defined
  `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS` so MSVC 14.51 (VS 18)
  accepts `permission_handler_windows`.
- Release publish job only runs for tag pushes.

## [1.0.1+2] — 2026-10-07

- Guarded the release publish job against manual branch dispatches creating a
  bogus release.
