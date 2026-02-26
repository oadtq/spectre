import AppKit

/// Terminal window for the vertical-tabs titlebar style.
/// Unlike HiddenTitlebarTerminalWindow, this keeps the standard traffic-light
/// buttons visible so users can close/minimize/zoom the window normally.
/// The content view still extends under the titlebar area so the sidebar
/// can fill the full height of the window.
class VerticalTabsTerminalWindow: TerminalWindow {
    // Vertical-tabs sidebar handles update notifications itself.
    override var supportsUpdateAccessory: Bool { false }

    override func awakeFromNib() {
        super.awakeFromNib()
        applyVerticalTabsStyle()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(fullscreenDidExit(_:)),
            name: .fullscreenDidExit,
            object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func applyVerticalTabsStyle() {
        guard !(terminalController?.fullscreenStyle?.isFullscreen ?? false) else { return }

        let base: NSWindow.StyleMask = [.titled, .fullSizeContentView, .resizable, .closable, .miniaturizable]
        if styleMask.contains(.fullScreen) {
            styleMask = base.union([.fullScreen])
        } else {
            styleMask = base
        }

        // Keep the title hidden but keep the titlebar so traffic lights show.
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        // Disallow native tab bar — we manage tabs ourselves.
        tabbingMode = .disallowed
    }

    // MARK: NSWindow

    override var title: String {
        didSet {
            // macOS 15+ can re-show the title on update; re-hide it.
            titleVisibility = .hidden
        }
    }

    // MARK: Notifications

    @objc private func fullscreenDidExit(_ notification: Notification) {
        guard let fullscreen = notification.object as? FullscreenBase else { return }
        guard fullscreen.window == self else { return }
        applyVerticalTabsStyle()
    }
}
