import SwiftUI

/// An NSHostingView subclass that prevents window dragging when clicking on the view.
///
/// By default, NSHostingViews in the titlebar allow the window to be dragged when
/// clicked. This subclass overrides `mouseDownCanMoveWindow` to return false,
/// preventing the window from being dragged when the user clicks on this view.
///
/// This is useful for titlebar accessories that contain interactive elements
/// (buttons, links, etc.) where you don't want accidental window dragging.
class NonDraggableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { false }
}

/// An NSHostingView subclass for the vertical-tab sidebar that zooms the window
/// when the user double-clicks on an empty (non-interactive) area of the sidebar.
///
/// All existing SwiftUI interactions (tab selection, buttons, etc.) are preserved
/// because we always call super first and only zoom when the hit lands on the
/// hosting view's own background layer — not on any interactive subview.
class SidebarHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        // Always let SwiftUI handle the event first so buttons/taps work normally.
        super.mouseDown(with: event)

        guard event.clickCount == 2 else { return }

        // Only zoom when the double-click landed on the background (this view),
        // not on an interactive SwiftUI subview. We check by hit-testing: if the
        // deepest view at the click point is self or one of the internal
        // NSHostingView rendering layers (which have no user interaction), zoom.
        let point = convert(event.locationInWindow, from: nil)
        let hit = hitTest(point)
        // If hit is nil or is self, the click was on empty background → zoom.
        // If hit is a descendant that is a control/button, skip zoom.
        let isBackground = hit == nil || hit == self
        if isBackground {
            window?.zoom(nil)
        }
    }
}
