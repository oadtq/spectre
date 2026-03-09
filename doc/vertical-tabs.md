# Vertical Tab Sidebar Feature

## Overview

Added Arc-style vertical tab management to Ghostty on macOS, activated via config:

```
macos-titlebar-style = vertical-tabs
```

This runs alongside the existing tab system as a new mode. Each tab manages its own surface tree (with splits), and a SwiftUI sidebar on the left displays the tab list.

## Config

Add to `~/.config/ghostty/config`:

```
macos-titlebar-style = vertical-tabs
```

Or launch with: `zig build run -- --macos-titlebar-style=vertical-tabs`

## Architecture

Instead of macOS native `NSWindowTabGroup` (one `NSWindow` per tab), vertical-tabs mode uses a single window with:
- A `VerticalTabModel` holding an array of tabs, each with its own `SplitTree<Ghostty.SurfaceView>`
- A SwiftUI sidebar (`VerticalTabSidebarView`) rendered via `NSHostingView` on the left
- A `TerminalViewContainer` on the right, swapped when tabs change
- Auto Layout constraints: sidebar fixed at 200pt width, terminal fills remaining space

## Files Created

| File | Purpose |
|------|---------|
| `macos/Sources/Features/Terminal/VerticalTabModel.swift` | Tab data model — add/remove/select/move/reorder tabs |
| `macos/Sources/Features/Terminal/VerticalTabSidebarView.swift` | SwiftUI sidebar — tab rows with color indicators, close buttons, hover states, new tab button |
| `macos/Sources/Features/Terminal/Window Styles/TerminalVerticalTabs.xib` | Window nib with native tabbing disabled |

## Files Modified

| File | Change |
|------|--------|
| `src/config/Config.zig` | Added `vertical-tabs` to `MacTitlebarStyle` enum |
| `macos/Sources/Features/Terminal/TerminalController.swift` | Vertical tab mode: layout setup, tab switching, overrides for closeSurface/closeTab/surfaceTreeDidChange/replaceSurfaceTree/onGotoTab/onMoveTab/onCloseTab |
| `macos/Sources/App/macOS/AppDelegate.swift` | Routes `ghosttyNewTab` notification to `addVerticalTab` when in vertical-tabs mode |
| `macos/Ghostty.xcodeproj/project.pbxproj` | Registered new source files and xib |

## Supported Operations

- New tab (Cmd+T or sidebar "+" button)
- Close tab (keybind or sidebar close button, with confirmation for running processes)
- Switch tabs (goto_tab keybinds: next/previous/numbered)
- Move/reorder tabs (move_tab keybind)
- Tab title tracking from terminal
- Tab color indicators
- Splits within each tab
- Proper cleanup when last tab closes (closes window)

## Shell Commands (`mkgroup` and friends)

The `mkgroup` command lets users create a tab group from the current working directory. It works by sending an OSC 0 (set-title) escape sequence with a special `ghostty-cmd:` prefix that the app intercepts in `Ghostty.App.swift`:

```sh
mkgroup() {
  printf '\033]0;ghostty-cmd:create-tab-group\007'
}
```

This command is added to the existing shell integration scripts so it's automatically available when shell integration is active:

- Bash: `src/shell-integration/bash/ghostty.bash`
- Zsh: `src/shell-integration/zsh/ghostty-integration`
- Fish: `src/shell-integration/fish/vendor_conf.d/ghostty-shell-integration.fish`

Shell integration is auto-injected by the app at runtime (no rc file writes needed). Any new shell commands should live in those scripts. Users who disable shell integration would need to add the function manually — that's acceptable and expected.

## Bell Notification

Vertical tabs use a lightweight notification system for bell events, separate from the base controller's bell-in-title mechanism used by horizontal tabs.

Why: Horizontal tabs display `window.title` (which includes "🔔" via `BaseTerminalController.computeTitle`). Vertical tabs display `tabDisplayTitle` derived from `pwd` (folder name), bypassing `tab.title` entirely. So the title-based bell approach is invisible in the sidebar.

How it works:
- `TerminalController` observes `ghosttyBellDidRing` via `NotificationCenter` (one observer, O(1) per event)
- When a bell fires on a background tab's surface, `onBellDidRing` finds the owning tab and sets `hasBell = true` on the model
- The sidebar view shows an orange bell icon when `tab.hasBell` is true
- `hasBell` is cleared when the user switches to that tab (`verticalTabSelectionDidChange`)
- `updateBell` has a no-op guard to skip unnecessary `@Published` mutations

This replaces an earlier `refreshVerticalTabBellTracking` approach that rebuilt Combine subscriptions across all surfaces on every state change, causing O(N^2) main-thread churn and eventual terminal degradation under heavy load.

## Known Limitations

- Sidebar width is fixed (not user-resizable yet)
- No drag-to-reorder tabs in the sidebar
- No undo/redo for vertical tab operations
- Window restoration not implemented for vertical-tabs mode

## Session Persistence — Investigation Notes

We attempted to implement session persistence (restore tabs/groups/splits across restarts) for vertical-tabs mode. The implementation was complete at the code level but could not be verified due to a macOS platform constraint. The code was reverted. Notes below for future attempts.

### What was implemented

- `VerticalTabSnapshot`, `VerticalTabGroupSnapshot`, `VerticalSidebarItemSnapshot`, `VerticalTabRestorableState` — `Codable` snapshots of the full `VerticalTabModel` state (tabs, groups, split trees, titles, colors, PWDs, selected tab)
- `TerminalWindowRestoration.restoreWindow` extended to handle a new `"VerticalTabsWindowRestoration"` window identifier, decoding `VerticalTabRestorableState` and rebuilding the model
- `TerminalController.window(_:willEncodeRestorableState:)` branched to encode `VerticalTabRestorableState` in vertical-tabs mode
- `TerminalController.windowDidLoad` sets a distinct `window.identifier` for vertical-tabs windows, and guards `addTab(surfaceTree:)` so a restored model isn't overwritten with a blank tab
- `VerticalTabModel.init(from: VerticalTabRestorableState)` to rebuild the model from a snapshot
- `AppDelegate.ghosttyConfigDidChange` auto-enables `NSQuitAlwaysKeepsWindows` when `macos-titlebar-style = vertical-tabs` so users don't need `window-save-state = always`

### Why it didn't work

macOS's `NSWindowRestoration` pipeline requires the app to be **properly code-signed with a Team ID**. The debug build produced by `zig build run` is ad-hoc signed (`Signature=adhoc`, `TeamIdentifier=not set`), and macOS silently skips writing the saved state directory (`~/Library/Saved Application State/<bundle-id>.savedState`) for ad-hoc signed apps.

Confirmed findings:
- `NSQuitAlwaysKeepsWindows = 1` was correctly set in `UserDefaults` for `com.oadtq.spectre.debug`
- Even after `defaults write NSGlobalDomain NSQuitAlwaysKeepsWindows -bool true`, no savedState directory was created after Cmd+Q
- The existing classic-tab restoration (`TerminalWindowRestoration`) has the same constraint and would fail identically in a debug build

### To resume this work

The implementation approach is sound. To test and ship it:
1. Build with a proper Apple Developer Team ID (production or development certificate, not ad-hoc)
2. Verify `~/Library/Saved Application State/<bundle-id>.savedState` is created after Cmd+Q
3. Confirm `window(_:willEncodeRestorableState:)` is called by checking logs
4. Re-apply the changes to these files:
   - `macos/Sources/Features/Terminal/TerminalRestorable.swift` — add snapshot types + extend `restoreWindow`
   - `macos/Sources/Features/Terminal/VerticalTabModel.swift` — add `init(from: VerticalTabRestorableState)`
   - `macos/Sources/Features/Terminal/TerminalController.swift` — branch encode, set identifier, guard `addTab`, add convenience init
   - `macos/Sources/App/macOS/AppDelegate.swift` — auto-enable `NSQuitAlwaysKeepsWindows` for vertical-tabs mode
