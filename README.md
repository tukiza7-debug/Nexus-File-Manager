# Nexus File Manager

**Powerful. Precise. Beautiful.**

Nexus is a modern, cross-platform file manager built with intention.  
It combines speed, refined design, and carefully chosen unique features — without bloat or unnecessary complexity.

> Currently in early development.

---

## Vision

Most file managers are either too basic or overloaded with features that feel disconnected.  
Nexus aims to be different:

- Exceptionally clean and polished UI
- Keyboard-first workflow
- Unique productivity features that actually matter
- Fast and lightweight (built with Tauri + Rust)
- Fully open source

---

## Tech Stack

| Layer              | Technology                      |
|--------------------|---------------------------------|
| Framework          | Tauri 2                         |
| Frontend           | React 19 + TypeScript (strict)  |
| Styling            | Tailwind CSS + customized shadcn/ui |
| State Management   | Zustand                         |
| Core / Backend     | Rust                            |
| Database           | SQLite                          |
| Package Manager    | pnpm                            |
| CI/CD              | GitHub Actions                  |

---

## Unique Features

### Navigation & Organization
- **Live Folder Mirror** — Virtual folders that stay in sync both ways
- **Breadcrumb Timeline** — Scrollable history of visited paths
- **Path Alias** — Create short custom aliases for long paths
- **Folder Stack** — Group multiple folders into one expandable stack
- **Ghost Mode** — Hide specific files and reveal them with a hotkey
- **Spatial Memory** — Remember icon positions inside folders
- **Pin to Edge** — Pin important files/folders to the window edge
- **Work Session** — Save & restore entire workspace state (tabs, paths, layout, selection)

### File Operations
- **Smart Paste** — Intelligent conflict handling
- **Multi-Clipboard Stack** — Multiple clipboard items with quick selector
- **File Transform Pipeline** — Chain actions (rename → convert → move, etc.)
- **Visual File Splitter** — Split large files by dragging on the preview
- **Merge Files** — Merge PDFs, text files, and images
- **Content-Aware Rename** — Rename using content from PDF/EPUB etc.
- **Batch Rule Engine** — Create powerful if-then rules
- **Deep Undo History** — Searchable undo stack
- **File Diff View** — Side-by-side comparison
- **Drag to Action Zone** — Quick action zones on window edges

### Interface & Experience
- **Zen Mode** — Distraction-free minimal interface
- **Peek Window** — Preview folder contents with Alt + Hover
- **Floating Inspector** — Detachable details panel
- **Split by Type** — Automatically split view by file type
- **Focus Tunnel** — Blur non-focused items
- **Color Blind Safe Mode**
- **One-Hand / Touch Mode**
- **Legacy Themes** — Windows 98 / XP / 7 inspired themes

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

## Project Structure

```text
Nexus-File-Manager/
├── src-tauri/                 # Rust backend (Tauri)
│   └── src/
├── src-ui/                    # React frontend
│   └── src/
│       ├── components/        # Reusable UI components
│       ├── features/          # Feature-based modules
│       ├── hooks/
│       ├── stores/            # Zustand stores
│       ├── lib/
│       ├── styles/
│       └── types/
├── .github/
│   └── workflows/             # CI/CD pipelines
├── docs/
└── README.md
```

---

## Development Roadmap

### v0.1 — MVP
- Core file navigation (list + grid)
- Tabs + basic dual pane
- Breadcrumb Timeline
- Work Session
- Zen Mode
- Multi-Clipboard Stack
- Essential file operations

### v0.5
- Live Folder Mirror
- Path Alias
- Smart Paste
- Batch Rule Engine
- Folder Watchdog
- Floating Inspector
- Peek Window

### v1.0
- Full feature set
- Plugin system (basic)
- Auto-update via GitHub Releases
- Polished installer for Windows, macOS, and Linux

---

## Design Principles

- No AI slop
- No vibe coding
- Every UI decision must feel intentional
- Performance and clarity over feature count
- Beautiful dark mode & light mode as first-class citizens
- Keyboard-first, mouse-friendly

---

## Getting Started (Coming Soon)

Development setup instructions will be added once the initial scaffolding is complete.

```bash
# (Planned)
pnpm install
pnpm tauri dev
```

---

## Contributing

This project is in very early stage.  
Architecture and core structure are currently being established.

---

## License

MIT License (planned)

---

**Nexus File Manager** — Built with care.
