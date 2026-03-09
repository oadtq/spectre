import AppKit
import SwiftUI
import Combine
import GhosttyKit

/// Manages the state for vertical tab sidebar mode.
/// Each tab holds its own surface tree (which may contain splits).
class VerticalTabModel: ObservableObject {
    /// A single tab in the vertical tab bar.
    struct Tab: Identifiable, Equatable {
        let id: UUID
        var title: String
        var tabColor: TerminalTabColor
        var hasBell: Bool
        var surfaceTree: SplitTree<Ghostty.SurfaceView>
        var pwd: String?
        /// The focused surface within this tab's split tree.
        weak var focusedSurface: Ghostty.SurfaceView?

        init(
            id: UUID = UUID(),
            title: String = "Spectre",
            tabColor: TerminalTabColor = .none,
            hasBell: Bool = false,
            surfaceTree: SplitTree<Ghostty.SurfaceView>,
            pwd: String? = nil,
            focusedSurface: Ghostty.SurfaceView? = nil
        ) {
            self.id = id
            self.title = title
            self.tabColor = tabColor
            self.hasBell = hasBell
            self.surfaceTree = surfaceTree
            self.pwd = pwd
            self.focusedSurface = focusedSurface
        }

        static func == (lhs: Tab, rhs: Tab) -> Bool {
            lhs.id == rhs.id
        }
    }

    /// A group of tabs
    struct TabGroup: Identifiable, Equatable {
        let id: UUID
        var title: String
        var tabs: [Tab]
        var isExpanded: Bool
        /// The base working directory for this group. New tabs created inside
        /// this group will inherit this path as their initial working directory.
        var basePath: String?

        init(id: UUID = UUID(), title: String, tabs: [Tab] = [], isExpanded: Bool = true, basePath: String? = nil) {
            self.id = id
            self.title = title
            self.tabs = tabs
            self.isExpanded = isExpanded
            self.basePath = basePath
        }

        static func == (lhs: TabGroup, rhs: TabGroup) -> Bool {
            lhs.id == rhs.id
        }
    }

    /// An item in the sidebar, which can be a tab or a group
    enum SidebarItem: Identifiable, Equatable {
        case tab(Tab)
        case group(TabGroup)

        var id: UUID {
            switch self {
            case .tab(let t): return t.id
            case .group(let g): return g.id
            }
        }
    }

    @Published var items: [SidebarItem] = []
    @Published var selectedTabId: UUID?
    @Published var terminalBackgroundColor: NSColor?

    /// Flattened list of all tabs, compatible with older flat model.
    var tabs: [Tab] {
        items.flatMap { item -> [Tab] in
            switch item {
            case .tab(let t): return [t]
            case .group(let g): return g.tabs
            }
        }
    }

    /// The currently selected tab, if any.
    var selectedTab: Tab? {
        guard let id = selectedTabId else { return tabs.first }
        return tabs.first(where: { $0.id == id })
    }

    /// The index of the currently selected tab.
    var selectedTabIndex: Int? {
        guard let id = selectedTabId else { return tabs.isEmpty ? nil : 0 }
        return tabs.firstIndex(where: { $0.id == id })
    }

    /// Add a new tab with the given surface tree, optionally after a specific tab.
    @discardableResult
    func addTab(
        surfaceTree: SplitTree<Ghostty.SurfaceView>,
        title: String = "Spectre",
        afterTabId: UUID? = nil,
        select: Bool = true
    ) -> Tab {
        let tab = Tab(surfaceTree: surfaceTree, focusedSurface: surfaceTree.first)
        var inserted = false

        if let afterId = afterTabId ?? selectedTabId {
            for (i, item) in items.enumerated() {
                switch item {
                case .tab(let t):
                    if t.id == afterId {
                        items.insert(.tab(tab), at: i + 1)
                        inserted = true
                    }
                case .group(var g):
                    if let j = g.tabs.firstIndex(where: { $0.id == afterId }) {
                        g.tabs.insert(tab, at: j + 1)
                        items[i] = .group(g)
                        inserted = true
                    } else if g.id == afterId {
                        items.insert(.tab(tab), at: i + 1)
                        inserted = true
                    }
                }
                if inserted { break }
            }
        }

        if !inserted {
            // Find if selected item is in a group
            var activeGroupId: UUID? = nil
            if let selectedId = selectedTabId {
                for item in items {
                    if case .group(let g) = item, g.tabs.contains(where: { $0.id == selectedId }) {
                        activeGroupId = g.id
                        break
                    }
                }
            }

            if let activeGroupId, let index = items.firstIndex(where: { $0.id == activeGroupId }) {
                if case .group(var g) = items[index] {
                    g.tabs.append(tab)
                    items[index] = .group(g)
                }
            } else {
                items.append(.tab(tab))
            }
        }

        if select {
            selectedTabId = tab.id
        }
        return tab
    }

    /// Remove a tab by ID. Returns the removed tab if found.
    @discardableResult
    func removeTab(id: UUID) -> Tab? {
        var removedTab: Tab? = nil
        let allTabs = self.tabs
        guard let index = allTabs.firstIndex(where: { $0.id == id }) else { return nil }

        for (i, item) in items.enumerated() {
            switch item {
            case .tab(let t):
                if t.id == id {
                    removedTab = t
                    items.remove(at: i)
                }
            case .group(var g):
                if let j = g.tabs.firstIndex(where: { $0.id == id }) {
                    removedTab = g.tabs.remove(at: j)
                    if g.tabs.isEmpty {
                        items.remove(at: i)
                    } else {
                        items[i] = .group(g)
                    }
                }
            }
            if removedTab != nil { break }
        }

        // If we removed the selected tab, select an adjacent one.
        if selectedTabId == id {
            if index < allTabs.count - 1 {
                // There is a next tab, wait, we removed current one so next tab shifted to `index`
                selectedTabId = allTabs[index + 1].id
            } else if allTabs.count > 1 {
                selectedTabId = allTabs[index - 1].id
            } else {
                selectedTabId = nil
            }
        }
        return removedTab
    }

    /// Select a tab by ID.
    func selectTab(id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabId = id
    }

    /// Select the next tab, wrapping around.
    func selectNextTab() {
        let allTabs = self.tabs
        guard let index = selectedTabIndex, !allTabs.isEmpty else { return }
        let next = (index + 1) % allTabs.count
        selectedTabId = allTabs[next].id
    }

    /// Select the previous tab, wrapping around.
    func selectPreviousTab() {
        let allTabs = self.tabs
        guard let index = selectedTabIndex, !allTabs.isEmpty else { return }
        let prev = (index - 1 + allTabs.count) % allTabs.count
        selectedTabId = allTabs[prev].id
    }

    /// Select a tab by 1-based index.
    func selectTab(at oneBasedIndex: Int) {
        let allTabs = self.tabs
        let index = oneBasedIndex - 1
        guard index >= 0, index < allTabs.count else { return }
        selectedTabId = allTabs[index].id
    }

    /// Move the selected tab by the given amount (positive = right, negative = left).
    func moveSelectedTab(by amount: Int) {
        let allTabs = self.tabs
        guard let index = selectedTabIndex, allTabs.count > 1 else { return }
        let target = max(0, min(allTabs.count - 1, index + amount))
        guard target != index else { return }
        let targetId = allTabs[target].id
        let selectedId = allTabs[index].id

        let wasSelected = (selectedId == selectedTabId)

        // Take it out
        guard let tab = removeTab(id: selectedId) else { return }
        
        // Find path to targetId and insert there
        var inserted = false
        for (i, item) in items.enumerated() {
            switch item {
            case .tab(let t):
                if t.id == targetId {
                    items.insert(.tab(tab), at: (amount > 0) ? i + 1 : i)
                    inserted = true
                }
            case .group(var g):
                if let j = g.tabs.firstIndex(where: { $0.id == targetId }) {
                    g.tabs.insert(tab, at: (amount > 0) ? j + 1 : j)
                    items[i] = .group(g)
                    inserted = true
                }
            }
            if inserted { break }
        }
        
        // Restore selection
        if wasSelected {
            selectedTabId = selectedId
        }
    }

    // Helper to update a tab
    private func updateTab(_ id: UUID, modify: (inout Tab) -> Void) {
        for (i, item) in items.enumerated() {
            switch item {
            case .tab(var t):
                if t.id == id {
                    modify(&t)
                    items[i] = .tab(t)
                    return
                }
            case .group(var g):
                if let j = g.tabs.firstIndex(where: { $0.id == id }) {
                    modify(&g.tabs[j])
                    items[i] = .group(g)
                    return
                }
            }
        }
    }

    /// Update the surface tree for a specific tab.
    func updateSurfaceTree(for tabId: UUID, tree: SplitTree<Ghostty.SurfaceView>) {
        updateTab(tabId) { $0.surfaceTree = tree }
    }

    /// Update the title for a specific tab.
    func updateTitle(for tabId: UUID, title: String) {
        updateTab(tabId) { $0.title = title }
    }

    /// Update the pwd for a specific tab.
    func updatePwd(for tabId: UUID, pwd: String?) {
        updateTab(tabId) { $0.pwd = pwd }
    }

    /// Update the tab color for a specific tab.
    func updateTabColor(for tabId: UUID, color: TerminalTabColor) {
        updateTab(tabId) { $0.tabColor = color }
    }

    /// Update the bell indicator state for a specific tab.
    func updateBell(for tabId: UUID, isActive: Bool) {
        guard tabs.first(where: { $0.id == tabId })?.hasBell != isActive else { return }
        updateTab(tabId) { $0.hasBell = isActive }
    }

    /// Update the overall terminal background color for the sidebar.
    func updateTerminalBackgroundColor(_ color: NSColor?) {
        self.terminalBackgroundColor = color
    }

    /// Update the focused surface for a specific tab.
    func updateFocusedSurface(for tabId: UUID, surface: Ghostty.SurfaceView?) {
        updateTab(tabId) { $0.focusedSurface = surface }
    }

    // MARK: - Grouping Features

    func createGroup(title: String, containing tabs: [Tab]) {
        let group = TabGroup(title: title, tabs: tabs)
        let tabIds = Set(tabs.map { $0.id })
        for tabId in tabIds {
            _ = removeTab(id: tabId)
        }
        items.append(.group(group))
    }
    
    func moveTabToNewGroup(tabId: UUID, groupTitle: String? = nil, basePath: String? = nil) {
        let isSelected = (selectedTabId == tabId)
        guard let tab = removeTab(id: tabId) else { return }

        // Use the provided title, or the active folder name, or fallback.
        let finalTitle: String
        if let groupTitle = groupTitle {
            finalTitle = groupTitle
        } else if let path = basePath ?? tab.pwd {
            let url = URL(fileURLWithPath: path)
            finalTitle = url.lastPathComponent.isEmpty ? "Home" : url.lastPathComponent
        } else {
            finalTitle = "New Group"
        }

        let finalBasePath = basePath ?? tab.pwd
        let group = TabGroup(title: finalTitle, tabs: [tab], basePath: finalBasePath)
        items.append(.group(group))
        if isSelected {
            selectedTabId = tabId
        }
    }

    func moveTabToGroup(tabId: UUID, groupId: UUID) {
        let isSelected = (selectedTabId == tabId)
        guard let tab = removeTab(id: tabId) else { return }
        for (i, item) in items.enumerated() {
            if case .group(var g) = item, g.id == groupId {
                g.tabs.append(tab)
                items[i] = .group(g)
                if isSelected {
                    selectedTabId = tabId
                }
                return
            }
        }
        items.append(.tab(tab))
        if isSelected {
            selectedTabId = tabId
        }
    }
    
    func toggleGroupExpandedState(groupId: UUID) {
        for (i, item) in items.enumerated() {
            if case .group(var g) = item, g.id == groupId {
                g.isExpanded.toggle()
                items[i] = .group(g)
                return
            }
        }
    }
    
    var groupList: [TabGroup] {
        items.compactMap {
            if case .group(let g) = $0 { return g }
            return nil
        }
    }

    /// Returns the base path of the group that contains the currently selected tab, if any.
    var activeGroupBasePath: String? {
        guard let selectedId = selectedTabId else { return nil }
        for item in items {
            if case .group(let g) = item, g.tabs.contains(where: { $0.id == selectedId }) {
                return g.basePath
            }
        }
        return nil
    }
}
