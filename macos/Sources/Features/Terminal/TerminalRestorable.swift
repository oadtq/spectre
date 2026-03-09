import Cocoa

protocol TerminalRestorable: Codable {
    static var selfKey: String { get }
    static var versionKey: String { get }
    static var version: Int { get }
    init(copy other: Self)

    /// Returns a base configuration to use when restoring terminal surfaces.
    /// Override this to provide custom environment variables or other configuration.
    var baseConfig: Ghostty.SurfaceConfiguration? { get }
}

extension TerminalRestorable {
    static var selfKey: String { "state" }
    static var versionKey: String { "version" }

    /// Default implementation returns nil (no custom base config).
    var baseConfig: Ghostty.SurfaceConfiguration? { nil }

    init?(coder aDecoder: NSCoder) {
        // If the version doesn't match then we can't decode. In the future we can perform
        // version upgrading or something but for now we only have one version so we
        // don't bother.
        guard aDecoder.decodeInteger(forKey: Self.versionKey) == Self.version else {
            return nil
        }

        guard let v = aDecoder.decodeObject(of: CodableBridge<Self>.self, forKey: Self.selfKey) else {
            return nil
        }

        self.init(copy: v.value)
    }

    func encode(with coder: NSCoder) {
        coder.encode(Self.version, forKey: Self.versionKey)
        coder.encode(CodableBridge(self), forKey: Self.selfKey)
    }
}

/// The state stored for terminal window restoration.
class TerminalRestorableState: TerminalRestorable {
    class var version: Int { 7 }

    let focusedSurface: String?
    let surfaceTree: SplitTree<Ghostty.SurfaceView>
    let effectiveFullscreenMode: FullscreenMode?
    let tabColor: TerminalTabColor
    let titleOverride: String?

    init(from controller: TerminalController) {
        self.focusedSurface = controller.focusedSurface?.id.uuidString
        self.surfaceTree = controller.surfaceTree
        self.effectiveFullscreenMode = controller.fullscreenStyle?.fullscreenMode
        self.tabColor = (controller.window as? TerminalWindow)?.tabColor ?? .none
        self.titleOverride = controller.titleOverride
    }

    required init(copy other: TerminalRestorableState) {
        self.surfaceTree = other.surfaceTree
        self.focusedSurface = other.focusedSurface
        self.effectiveFullscreenMode = other.effectiveFullscreenMode
        self.tabColor = other.tabColor
        self.titleOverride = other.titleOverride
    }
}

/// Snapshot of a single vertical tab for persistence.
struct VerticalTabSnapshot: Codable {
    let id: String
    let title: String
    let tabColor: TerminalTabColor
    let surfaceTree: SplitTree<Ghostty.SurfaceView>
    let pwd: String?
    let focusedSurface: String?
}

/// Snapshot of a vertical tab group for persistence.
struct VerticalTabGroupSnapshot: Codable {
    let id: String
    let title: String
    let tabs: [VerticalTabSnapshot]
    let isExpanded: Bool
    let basePath: String?
}

/// Snapshot of a sidebar item (tab or group) for persistence.
enum VerticalSidebarItemSnapshot: Codable {
    case tab(VerticalTabSnapshot)
    case group(VerticalTabGroupSnapshot)

    enum CodingKeys: String, CodingKey {
        case type
        case tab
        case group
    }

    enum ItemType: String, Codable {
        case tab
        case group
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ItemType.self, forKey: .type)
        switch type {
        case .tab:
            self = .tab(try container.decode(VerticalTabSnapshot.self, forKey: .tab))
        case .group:
            self = .group(try container.decode(VerticalTabGroupSnapshot.self, forKey: .group))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .tab(let t):
            try container.encode(ItemType.tab, forKey: .type)
            try container.encode(t, forKey: .tab)
        case .group(let g):
            try container.encode(ItemType.group, forKey: .type)
            try container.encode(g, forKey: .group)
        }
    }
}

/// The state stored for vertical-tabs window restoration.
class VerticalTabRestorableState: TerminalRestorable {
    class var version: Int { 1 }

    let items: [VerticalSidebarItemSnapshot]
    let selectedTabId: String?
    let effectiveFullscreenMode: FullscreenMode?

    init(from controller: TerminalController) {
        guard let model = controller.verticalTabModel else {
            self.items = []
            self.selectedTabId = nil
            self.effectiveFullscreenMode = nil
            return
        }

        self.items = model.items.map { item in
            switch item {
            case .tab(let t):
                return .tab(VerticalTabSnapshot(
                    id: t.id.uuidString,
                    title: t.title,
                    tabColor: t.tabColor,
                    surfaceTree: t.surfaceTree,
                    pwd: t.pwd,
                    focusedSurface: t.focusedSurface?.id.uuidString
                ))
            case .group(let g):
                return .group(VerticalTabGroupSnapshot(
                    id: g.id.uuidString,
                    title: g.title,
                    tabs: g.tabs.map { t in
                        VerticalTabSnapshot(
                            id: t.id.uuidString,
                            title: t.title,
                            tabColor: t.tabColor,
                            surfaceTree: t.surfaceTree,
                            pwd: t.pwd,
                            focusedSurface: t.focusedSurface?.id.uuidString
                        )
                    },
                    isExpanded: g.isExpanded,
                    basePath: g.basePath
                ))
            }
        }
        self.selectedTabId = model.selectedTabId?.uuidString
        self.effectiveFullscreenMode = controller.fullscreenStyle?.fullscreenMode
    }

    required init(copy other: VerticalTabRestorableState) {
        self.items = other.items
        self.selectedTabId = other.selectedTabId
        self.effectiveFullscreenMode = other.effectiveFullscreenMode
    }
}

enum TerminalRestoreError: Error {
    case delegateInvalid
    case identifierUnknown
    case stateDecodeFailed
    case windowDidNotLoad
}

/// The NSWindowRestoration implementation that is called when a terminal window needs to be restored.
/// The encoding of a terminal window is handled elsewhere (usually NSWindowDelegate).
class TerminalWindowRestoration: NSObject, NSWindowRestoration {
    /// The window identifier used for vertical-tabs mode restoration.
    static let verticalTabsIdentifier = NSUserInterfaceItemIdentifier("VerticalTabsWindowRestoration")

    static func restoreWindow(
        withIdentifier identifier: NSUserInterfaceItemIdentifier,
        state: NSCoder,
        completionHandler: @escaping (NSWindow?, Error?) -> Void
    ) {
        let standardId = NSUserInterfaceItemIdentifier(String(describing: Self.self))

        // Verify the identifier is one we handle
        guard identifier == standardId || identifier == verticalTabsIdentifier else {
            completionHandler(nil, TerminalRestoreError.identifierUnknown)
            return
        }

        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else {
            completionHandler(nil, TerminalRestoreError.delegateInvalid)
            return
        }

        if appDelegate.ghostty.config.windowSaveState == "never" {
            completionHandler(nil, nil)
            return
        }

        // Vertical-tabs restoration path
        if identifier == verticalTabsIdentifier {
            restoreVerticalTabsWindow(state: state, appDelegate: appDelegate, completionHandler: completionHandler)
            return
        }

        // Standard (horizontal tab) restoration path
        guard let state = TerminalRestorableState(coder: state) else {
            completionHandler(nil, TerminalRestoreError.stateDecodeFailed)
            return
        }

        let c = TerminalController.init(
            appDelegate.ghostty,
            withSurfaceTree: state.surfaceTree)
        guard let window = c.window else {
            completionHandler(nil, TerminalRestoreError.windowDidNotLoad)
            return
        }

        (window as? TerminalWindow)?.tabColor = state.tabColor
        c.titleOverride = state.titleOverride

        if let focusedStr = state.focusedSurface {
            var foundView: Ghostty.SurfaceView?
            for view in c.surfaceTree where view.id.uuidString == focusedStr {
                foundView = view
                break
            }

            if let view = foundView {
                c.focusedSurface = view
                restoreFocus(to: view, inWindow: window)
            }
        }

        completionHandler(window, nil)
        guard let mode = state.effectiveFullscreenMode, mode != .native else {
            return
        }
        c.toggleFullscreen(mode: mode)
    }

    /// Restore a vertical-tabs window from saved state.
    private static func restoreVerticalTabsWindow(
        state: NSCoder,
        appDelegate: AppDelegate,
        completionHandler: @escaping (NSWindow?, Error?) -> Void
    ) {
        guard let vtState = VerticalTabRestorableState(coder: state) else {
            completionHandler(nil, TerminalRestoreError.stateDecodeFailed)
            return
        }

        // Build the restored model
        let model = VerticalTabModel()
        var selectedTabUUID: UUID? = nil
        if let idStr = vtState.selectedTabId {
            selectedTabUUID = UUID(uuidString: idStr)
        }

        for item in vtState.items {
            switch item {
            case .tab(let snap):
                let tab = VerticalTabModel.Tab(
                    id: UUID(uuidString: snap.id) ?? UUID(),
                    title: snap.title,
                    tabColor: snap.tabColor,
                    surfaceTree: snap.surfaceTree,
                    pwd: snap.pwd,
                    focusedSurface: findSurface(id: snap.focusedSurface, in: snap.surfaceTree)
                )
                model.items.append(.tab(tab))

            case .group(let gSnap):
                var tabs: [VerticalTabModel.Tab] = []
                for tSnap in gSnap.tabs {
                    let tab = VerticalTabModel.Tab(
                        id: UUID(uuidString: tSnap.id) ?? UUID(),
                        title: tSnap.title,
                        tabColor: tSnap.tabColor,
                        surfaceTree: tSnap.surfaceTree,
                        pwd: tSnap.pwd,
                        focusedSurface: findSurface(id: tSnap.focusedSurface, in: tSnap.surfaceTree)
                    )
                    tabs.append(tab)
                }
                let group = VerticalTabModel.TabGroup(
                    id: UUID(uuidString: gSnap.id) ?? UUID(),
                    title: gSnap.title,
                    tabs: tabs,
                    isExpanded: gSnap.isExpanded,
                    basePath: gSnap.basePath
                )
                model.items.append(.group(group))
            }
        }

        // Select the previously selected tab, or the first tab
        if let selectedTabUUID, model.tabs.contains(where: { $0.id == selectedTabUUID }) {
            model.selectedTabId = selectedTabUUID
        } else {
            model.selectedTabId = model.tabs.first?.id
        }

        // Use the selected tab's surface tree to create the controller
        let initialTree = model.selectedTab?.surfaceTree ?? SplitTree<Ghostty.SurfaceView>()

        let c = TerminalController(
            appDelegate.ghostty,
            withSurfaceTree: initialTree,
            restoredVerticalTabModel: model
        )
        guard let window = c.window else {
            completionHandler(nil, TerminalRestoreError.windowDidNotLoad)
            return
        }

        // Restore focus to the selected tab's focused surface
        if let focusedView = model.selectedTab?.focusedSurface {
            c.focusedSurface = focusedView
            restoreFocus(to: focusedView, inWindow: window)
        } else if let firstView = model.selectedTab?.surfaceTree.first {
            c.focusedSurface = firstView
            restoreFocus(to: firstView, inWindow: window)
        }

        completionHandler(window, nil)
        guard let mode = vtState.effectiveFullscreenMode, mode != .native else {
            return
        }
        c.toggleFullscreen(mode: mode)
    }

    /// Find a surface view by UUID string in a surface tree.
    private static func findSurface(id: String?, in tree: SplitTree<Ghostty.SurfaceView>) -> Ghostty.SurfaceView? {
        guard let idStr = id else { return nil }
        return tree.first(where: { $0.id.uuidString == idStr })
    }

    /// This restores the focus state of the surfaceview within the given window. When restoring,
    /// the view isn't immediately attached to the window since we have to wait for SwiftUI to
    /// catch up. Therefore, we sit in an async loop waiting for the attachment to happen.
    private static func restoreFocus(to: Ghostty.SurfaceView, inWindow: NSWindow, attempts: Int = 0) {
        // For the first attempt, we schedule it immediately. Subsequent events wait a bit
        // so we don't just spin the CPU at 100%. Give up after some period of time.
        let after: DispatchTime
        if attempts == 0 {
            after = .now()
        } else if attempts > 40 {
            // 2 seconds, give up
            return
        } else {
            after = .now() + .milliseconds(50)
        }

        DispatchQueue.main.asyncAfter(deadline: after) {
            // If the view is not attached to a window yet then we repeat.
            guard let viewWindow = to.window else {
                restoreFocus(to: to, inWindow: inWindow, attempts: attempts + 1)
                return
            }

            // If the view is attached to some other window, we give up
            guard viewWindow == inWindow else { return }

            inWindow.makeFirstResponder(to)

            // If the window is main, then we also make sure it comes forward. This
            // prevents a bug found in #1177 where sometimes on restore the windows
            // would be behind other applications.
            if viewWindow.isMainWindow {
                viewWindow.orderFront(nil)
            }
        }
    }
}

