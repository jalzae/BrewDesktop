# BrewDesktop

Native macOS (SwiftUI) desktop manager for Homebrew. Wraps `brew` CLI in a GUI: browse installed packages, manage launchd-registered services, upgrade, taps, cleanup, doctor — with live console output for every operation.

## Run

```bash
swift run                 # dev
./scripts/make_app.sh     # release bundle
open build/BrewDesktop.app
```

Requires macOS 14+ and Homebrew installed at `/opt/homebrew` or `/usr/local`.

## Features

- **Overview** — brew version/prefix, formula & cask counts, outdated count, running/registered services, tap count, Cellar size; one-click `brew update`, Upgrade All, Doctor, Cleanup.
- **Installed** — formulae + casks with versions, descriptions, badges (outdated / pinned / service / deprecated / dependency-only). Toolbar search filters instantly. Detail pane: dependencies, caveats, install date, homepage. Context menu: upgrade, reinstall, pin/unpin, uninstall (+ `--zap` for casks with confirmation).
- **Services** — every service `brew services list` knows: status dot (running / available / error / stopped), registered plist path, exit code, root flag. Start / Stop / Restart / Run-once / Kill. Root-owned services elevate via the macOS admin-password dialog. Auto-refreshes every 15 s.
- **Outdated** — installed → current versions, pinned entries highlighted, upgrade selected or all.
- **Taps** — official badge, remote, formula/cask counts, add/untap.
- **Cleanup** — `brew cleanup -n` analysis with reclaimable-space estimate, then real cleanup.
- **Doctor** — `brew doctor` output + pass/fail badge.
- **Install sheet** (⌘I) — debounced `brew search` across formulae & casks, per-hit info card (deps, caveats, homepage), install with live console.
- **Console** — every mutating command streams stdout/stderr into a live console sheet; cancellable mid-run.

## Layout

```
Sources/BrewDesktop/
├── BrewDesktopApp.swift     # entry, menu commands, notifications
├── BrewStore.swift          # @MainActor state + all brew operations
├── BrewParser.swift         # pure JSON/text parsing (unit-tested)
├── ShellRunner.swift        # Process wrapper, GUI-safe PATH, streaming, sudo via osascript
├── Models.swift             # PackageEntry, ServiceEntry, OutdatedEntry, TapEntry, …
└── Views/                   # ContentView, Overview, Installed, Services, Outdated, Taps, Cleanup, Doctor, InstallSheet
Tests/BrewDesktopTests/      # parser tests against real brew output shapes
```

## Homebrew 7 notes

- `brew list --json` is gone; installed inventory uses `brew info --json=v2 --installed`.
- `brew services list --json` and `brew tap-info --json=v1 --installed` are the supported JSON surfaces.
- `HOMEBREW_NO_AUTO_UPDATE=1` is set for all read commands; JSON payloads are preamble-stripped defensively.

## Security model

Read-only commands run as the logged-in user. Root-owned services (`user: root`) require admin privileges — BrewDesktop shells out through `osascript … with administrator privileges`, which shows the standard macOS password prompt. No credentials are captured or stored.
