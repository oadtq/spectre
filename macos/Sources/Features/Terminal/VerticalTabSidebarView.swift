import SwiftUI
import GhosttyKit

/// The vertical tab sidebar view, rendered on the left side of the window.
/// Displays a list of tabs with titles, color indicators, and close buttons.
struct VerticalTabSidebarView: View {
    @ObservedObject var model: VerticalTabModel
    var onNewTab: () -> Void
    var onNewGroup: () -> Void
    var onCloseTab: (UUID) -> Void

    /// Width of the sidebar
    static let defaultWidth: CGFloat = 200

    /// Resolved background: terminal color or a sensible dark fallback.
    private var sidebarBackground: Color {
        if let bg = model.terminalBackgroundColor {
            return Color(nsColor: bg)
        }
        // Default to a dark neutral so the sidebar never flashes white on launch.
        return Color(nsColor: NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1))
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                // Tab list
                ScrollView {
                    let groups = model.items.compactMap { item -> VerticalTabModel.TabGroup? in
                        if case .group(let g) = item { return g }
                        return nil
                    }
                    let independentTabs = model.items.compactMap { item -> VerticalTabModel.Tab? in
                        if case .tab(let t) = item { return t }
                        return nil
                    }

                    LazyVStack(alignment: .leading, spacing: 6) {
                        if !groups.isEmpty {
                            Text("Projects")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.top, 4)
                                .padding(.bottom, 2)
                            
                            ForEach(groups) { group in
                                VerticalTabGroupRow(
                                    group: group,
                                    selectedTabId: model.selectedTabId,
                                    onSelectTab: { model.selectTab(id: $0) },
                                    onCloseTab: { onCloseTab($0) },
                                    onToggleExpand: { model.toggleGroupExpandedState(groupId: group.id) },
                                    onMoveToNewGroup: { model.moveTabToNewGroup(tabId: $0) },
                                    onMoveToGroup: { tabId, groupId in model.moveTabToGroup(tabId: tabId, groupId: groupId) },
                                    groupList: model.groupList
                                )
                            }
                        }
                        
                        if !independentTabs.isEmpty {
                            Text("Terminals")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.top, groups.isEmpty ? 4 : 16)
                                .padding(.bottom, 2)
                            
                            ForEach(independentTabs) { tab in
                                tabRow(for: tab)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                }

                Spacer(minLength: 0)

                // Bottom action buttons — stacked vertically, no dividers
                VStack(spacing: 2) {
                    SidebarActionButton(
                        icon: "plus",
                        label: "New Terminal",
                        action: onNewTab
                    )
                    SidebarActionButton(
                        icon: "folder.badge.plus",
                        label: "New Project",
                        action: onNewGroup
                    )
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .padding(.top, 4)
            }

            // Subtle edge separator
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 1)
        }
        .frame(width: Self.defaultWidth)
        .background(sidebarBackground)
    }

    @ViewBuilder
    private func tabRow(for tab: VerticalTabModel.Tab) -> some View {
        VerticalTabRow(
            tab: tab,
            isSelected: tab.id == model.selectedTabId,
            onSelect: { model.selectTab(id: tab.id) },
            onClose: { onCloseTab(tab.id) }
        )
        .contextMenu {
            Button("Move to New Project") {
                model.moveTabToNewGroup(tabId: tab.id)
            }
            if !model.groupList.isEmpty {
                Menu("Move to Project") {
                    ForEach(model.groupList) { g in
                        Button(g.title) {
                            model.moveTabToGroup(tabId: tab.id, groupId: g.id)
                        }
                    }
                }
            }
        }
    }
}

/// A minimal, hover-aware action button for the sidebar bottom area.
private struct SidebarActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(label)
                    .font(.system(size: 13))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovering ? Color.white.opacity(0.07) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
        .onHover { hovering in isHovering = hovering }
    }
}

/// A group of vertical tabs in the sidebar.
struct VerticalTabGroupRow: View {
    let group: VerticalTabModel.TabGroup
    let selectedTabId: UUID?
    let onSelectTab: (UUID) -> Void
    let onCloseTab: (UUID) -> Void
    let onToggleExpand: () -> Void
    let onMoveToNewGroup: (UUID) -> Void
    let onMoveToGroup: (UUID, UUID) -> Void
    let groupList: [VerticalTabModel.TabGroup]

    var body: some View {
        VStack(spacing: 4) {
            Button(action: onToggleExpand) {
                HStack(spacing: 8) {
                    Image(systemName: group.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 14)

                    Text(group.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if group.isExpanded {
                ForEach(group.tabs) { tab in
                    VerticalTabRow(
                        tab: tab,
                        isSelected: tab.id == selectedTabId,
                        onSelect: { onSelectTab(tab.id) },
                        onClose: { onCloseTab(tab.id) }
                    )
                    .padding(.leading, 12)
                    .contextMenu {
                        tabContextMenu(for: tab)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tabContextMenu(for tab: VerticalTabModel.Tab) -> some View {
        Button("Move to New Project") {
            onMoveToNewGroup(tab.id)
        }
        if !groupList.isEmpty {
            Menu("Move to Project") {
                ForEach(groupList) { g in
                    if g.id != group.id {
                        Button(g.title) {
                            onMoveToGroup(tab.id, g.id)
                        }
                    }
                }
            }
        }
    }
}

/// A single row in the vertical tab sidebar.
struct VerticalTabRow: View {
    let tab: VerticalTabModel.Tab
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            // Tab title
            Text(tabDisplayTitle)
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.head)
                // Prevents SwiftUI from completely discarding and recreating the view 
                // when tracking ID or view state shifts dynamically (the "splash effect")
                .id(tab.id.uuidString)

            Spacer(minLength: 0)

            // Bell indicator for background tabs
            if tab.hasBell {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.orange)
                    .accessibilityLabel("Notification")
            }

            // Close button (visible on hover or when selected)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 18, height: 18)
            .opacity(isHovering || isSelected ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected
                      ? Color.accentColor.opacity(0.15)
                      : (isHovering ? Color.white.opacity(0.06) : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            isHovering = hovering
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tab: \(tabDisplayTitle)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var tabDisplayTitle: String {
        if let pwd = tab.pwd {
            let url = URL(fileURLWithPath: pwd)
            let lastComponent = url.lastPathComponent
            return lastComponent.isEmpty ? "Home" : lastComponent
        }
        return tab.title
    }
}
