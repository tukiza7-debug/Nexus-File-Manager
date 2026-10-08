# Nexus File Manager

**Powerful. Precise. Beautiful.** — a keyboard-first, cross-platform file manager built with Flutter, for Android, iOS, Windows, macOS and Linux.

[![CI](https://github.com/tukiza7-debug/Nexus-File-Manager/actions/workflows/ci.yml/badge.svg)](https://github.com/tukiza7-debug/Nexus-File-Manager/actions/workflows/ci.yml)

<p align="center">
  <img src="assets/logo/nexus-logo-primary.svg" width="220" alt="Nexus logo" />
</p>

Nexus is a full file manager: a fast, custom-designed browsing core plus 36 deeply integrated power features — live mirroring, transform pipelines, LAN teleports, a complete reversible operation journal and more. Nothing is a mock: every feature drives real file operations through one audited core.

---

## Quick start

```bash
flutter pub get
flutter run                # pick a device: Windows / macOS / Linux / Android / iOS
```

Requirements: Flutter (stable, Dart 3.5+). No codegen, no native setup steps — `pub get` is the whole install.

## Feature map

| # | Feature | Where |
|---|---------|-------|
| 1 | **Live Folder Mirror** — continuous two-way sync pairs | Tools → Mirror |
| 2 | **Breadcrumb Timeline** — every stop a tab made, one click away | Explorer breadcrumb bar |
| 3 | **Path Alias** — name any folder, jump by name (also in palette) | Sidebar · Aliases |
| 4 | **Folder Stack** — snapshot open tabs as a named stack | Sidebar · Folder Stacks |
| 5 | **Ghost Mode** — instant window transparency (`Ctrl G`) | Title bar / shortcut |
| 6 | **Spatial Memory** — free tile placement remembered per folder | Explorer · spatial toggle |
| 7 | **Pin to Edge / Favorites Dock** — four edge docks, drag-to-pin | Shell edges |
| 8 | **Work Session** — full workspace save/restore + autosave recovery | `Ctrl S` · Sessions |
| 9 | **Smart Paste** — per-item conflict resolution dialog | `Ctrl V` |
| 10 | **Multi-Clipboard Stack** — 25 slots, active slot model | Sidebar · Clipboard Stack |
| 11 | **File Transform Pipeline** — visual step chain with live name preview | Tools → Pipeline |
| 12 | **Visual File Splitter** — by parts or byte marker | Tools → Splitter |
| 13 | **Merge Files** — PDF pages, images, CSV, text, binary rejoin | Tools → Merge |
| 14 | **Content-Aware Rename** — EXIF/ID3/doc-driven patterns | Tools → Rename |
| 15 | **Batch Rule Engine** — if-then rules with plan preview | Automation → Rules |
| 16 | **Deep Undo History** — searchable, batch-level, undo *and* redo | `Ctrl Z/Y` · Paper Trail |
| 17 | **File Diff View** — line diff with word highlights | Tools → Diff |
| 18 | **Drag to Action Zone** — drop files on the edge to move/copy/zip/freeze/teleport/pipeline | Drag any tile |
| 19 | **Zen Mode** (`F1`) | Title bar |
| 20 | **Peek Preview** — Alt+hover card with text/image/metadata | Explorer |
| 21 | **Floating Inspector** — draggable metadata panel (`Ctrl I`) | Explorer |
| 22 | **Split by Type** — tabs per category | Explorer view menu |
| 23 | **Focus Tunnel** — dim everything but the focused item | Context menu |
| 24 | **Color Blind Safe Mode** — pattern textures, never colour alone | Settings |
| 25 | **One-Hand / Touch Mode** — big tiles + thumb action bar | Settings |
| 26 | **Legacy Themes** — Windows 98 / XP / 7 personality packs | Settings |
| 27 | **Macro Recorder** — record real operations, replay anywhere | Automation → Macros |
| 28 | **Folder Watchdog** — folder triggers → actions, live feed | Automation → Watchdog |
| 29 | **Scheduled Actions** — one-shot and repeating jobs | Automation → Scheduler |
| 30 | **Template Drop** — file/folder/text templates with tokens | Automation → Templates |
| 31 | **Auto Versioning** — snapshot before overwrite, restore anytime | Tools → Versions |
| 32 | **Batch Metadata Editor** — EXIF, ID3 and document properties | Automation → Metadata |
| 33 | **File Teleport** — UDP discovery + TCP push across your LAN | Tools → Teleport |
| 34 | **Paper Trail** — every operation, searchable and reversible | `Ctrl Z` · Paper Trail |
| 35 | **Secure Freeze** — lock files read-only, enforced by every writer | Context menu |
| 36 | **Quick Session Switcher** — fuzzy session jump (`Ctrl Shift S`) | Global |

Keyboard-first: `Ctrl K` command palette, `Ctrl Z / Y` undo/redo, `F2` rename, `Del` delete, `F1` zen, `F5` refresh, `Ctrl B` sidebar, `Ctrl H` hidden files, `Ctrl I` inspector, `Ctrl D` new tab, `Ctrl W` close tab, `Ctrl S` save session, `Ctrl Shift S` session switcher.

## Architecture

```
lib/
├── core/            # theme (Nexus design system + legacy brands), router,
│   ├── services/    # file ops, journal, mirror, watchdog, scheduler, teleport,
│   │                # metadata (EXIF/ID3/docProps), diff, merge, split, rules…
│   ├── db/          # sqlite3 data layer (WAL), typed DAOs
│   └── utils/       # result types, path/format helpers, fuzzy matcher
├── domain/          # pure models & enums (no Flutter imports)
├── state/           # Riverpod 2 wiring: services, tabs, directory, settings
└── features/        # feature-first UI: splash, explorer, tools, papertrail,
                     # sessions, settings
```

- **Clean layering** — presentation → state → services/domain → data; models are plain Dart, testable off-UI.
- **One choke point** — every mutation flows through `FileOpsService`: freeze enforcement → execution → journal record → progress broadcast. Undo, macros, watchdogs and schedules all share it.
- **Performance** — directory listings load in isolates, watchers are debounced, and SQLite (WAL) keeps history queries instant even with thousands of entries.

## Platforms

| Platform | Notes |
|----------|-------|
| Windows / macOS / Linux | Custom frameless window, native open/reveal, real window-opacity Ghost Mode |
| Android | All-files access (requested at first launch), share-sheet receiving (SAF), touch mode with one-hand bar |
| iOS | Document browsing + Teleport over local network |

## Releases

Pipelines are fully automated on **Flutter 3.47.6 stable**: every push to
`main` is analyzed, tested, and published as APKs to the rolling **Latest
Build (Auto)** pre-release; pushing a tag `v1.2.3` additionally builds all
five platforms and attaches the artifacts to the matching GitHub Release.
See [docs/RELEASE.md](docs/RELEASE.md) for the full process and signing notes.

## Tests

```bash
flutter test
```

Covers the diff engine, rule engine, path utilities and fuzzy matcher.
