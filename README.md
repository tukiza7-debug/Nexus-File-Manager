# Nexus File Manager

**Powerful. Precise. Beautiful.**

<p align="center">
  <img src="assets/logo/nexus-logo-primary.svg" alt="Nexus File Manager Logo" width="200"/>
</p>

<p align="center">
  <strong>Modern cross-platform file manager</strong><br>
  Android • iOS • Windows • macOS • Linux
</p>

Nexus is a premium, fast, and uniquely powerful file manager built with Flutter.  
It combines refined design, high performance, and carefully crafted features — without bloat or unnecessary complexity.

---

## Official Logo

All logo assets are available in [`assets/logo/`](assets/logo/).

| File | Usage |
|------|-------|
| `nexus-logo-primary.svg` | Main brand logo |
| `nexus-icon.svg` | App icon (all platforms) |
| `nexus-logo.svg` | Alternative version |

A polished **logo animation** is required on every app launch.

---

## Vision

Most file managers are either too basic or overloaded with disconnected features.  
Nexus aims to be different:

- Exceptionally clean and polished UI
- Excellent experience on both mobile and desktop
- Unique productivity features that actually matter
- Fast and lightweight
- Fully open source

---

## Tech Stack

| Layer              | Technology                          |
|--------------------|-------------------------------------|
| Framework          | Flutter (latest stable)             |
| Language           | Dart (null safety)                  |
| State Management   | Riverpod 2                          |
| Navigation         | GoRouter                            |
| Database           | Isar / Drift                        |
| Animations         | Flutter + flutter_animate           |
| Theming            | Custom Material 3                   |
| Platforms          | Android, iOS, Windows, macOS, Linux |

---

## Features

### Navigation & Organization
- **Live Folder Mirror** — Virtual folders that stay in sync both ways
- **Breadcrumb Timeline** — Scrollable history of visited paths
- **Path Alias** — Create short custom aliases for long paths
- **Folder Stack** — Group multiple folders into expandable stacks
- **Ghost Mode** — Hide specific files and reveal with hotkey/gesture
- **Spatial Memory** — Remember view positions and layout per folder
- **Pin to Edge / Favorites Dock** — Quick access to important items
- **Work Session** — Save & restore entire workspace state

### File Operations
- **Smart Paste** — Intelligent conflict handling
- **Multi-Clipboard Stack** — Multiple clipboard items with quick selector
- **File Transform Pipeline** — Chain actions (rename → convert → move, etc.)
- **Visual File Splitter** — Split large files with visual control
- **Merge Files** — Merge PDFs, text files, and images
- **Content-Aware Rename** — Rename using content from PDF/EPUB etc.
- **Batch Rule Engine** — Create powerful if-then rules
- **Deep Undo History** — Searchable undo stack
- **File Diff View** — Side-by-side comparison
- **Drag to Action Zone** — Quick action zones

### Interface & Experience
- **Zen Mode** — Distraction-free minimal interface
- **Peek Preview** — Quick preview of folder/file contents
- **Floating Inspector** — Detachable details panel
- **Split by Type** — Automatically split view by file type
- **Focus Tunnel** — Blur non-focused items
- **Color Blind Safe Mode**
- **One-Hand Mode** — Optimized for large phones
- **Legacy Themes** — Retro-inspired themes

### Automation
- Macro Recorder
- Folder Watchdog
- Scheduled Actions
- Template Drop
- Auto Versioning
- Batch Metadata Editor

### Extra
- File Teleport (local network)
- Paper Trail (full file movement history)
- Secure Freeze
- Quick Session Switcher

---

## Platform Support

| Platform  | Support       | Notes                                |
|-----------|---------------|--------------------------------------|
| Android   | Full support  | Scoped Storage + SAF                 |
| iOS       | Full support  | Proper sandboxing                    |
| Windows   | Full support  | Native dialogs + keyboard shortcuts  |
| macOS     | Full support  | Native feel + keyboard shortcuts     |
| Linux     | Full support  | Desktop file integration             |

---

## Design Principles

- No AI slop
- No vibe coding
- Every UI decision must feel intentional
- Performance and clarity over feature count
- Beautiful dark mode & light mode as first-class citizens
- Excellent touch experience on mobile
- Keyboard-first on desktop

---

## Getting Started

```bash
git clone https://github.com/tukiza7-debug/Nexus-File-Manager.git
cd Nexus-File-Manager
flutter pub get
flutter run
```

---

## Contributing

This project is in active full development.  
High-quality contributions are welcome once the core architecture is stabilized.

---

## License

MIT License

---

**Nexus File Manager** — Built with care.
