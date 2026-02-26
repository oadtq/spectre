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

## Known Limitations

- Sidebar width is fixed (not user-resizable yet)
- No drag-to-reorder tabs in the sidebar
- No undo/redo for vertical tab operations
- Window restoration not implemented for vertical-tabs mode
