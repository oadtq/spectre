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
                    LazyVStack(spacing: 2) {
                        ForEach(model.items) { item in
                            switch item {
                            case .tab(let tab):
                                tabRow(for: tab)
                            case .group(let group):
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
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                }

                Spacer(minLength: 0)

                // Bottom action buttons — stacked vertically, no dividers
                VStack(spacing: 2) {
                    SidebarActionButton(
                        icon: "plus",
                        label: "New Tab",
                        action: onNewTab
                    )
                    SidebarActionButton(
                        icon: "folder.badge.plus",
                        label: "New Group",
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
            Button("Move to New Group") {
                model.moveTabToNewGroup(tabId: tab.id)
            }
            if !model.groupList.isEmpty {
                Menu("Move to Group") {
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
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(label)
                    .font(.system(size: 12))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
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
        VStack(spacing: 2) {
            Button(action: onToggleExpand) {
                HStack(spacing: 6) {
                    Image(systemName: group.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 12)

                    Text(group.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
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
        Button("Move to New Group") {
            onMoveToNewGroup(tab.id)
        }
        if !groupList.isEmpty {
            Menu("Move to Group") {
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
        HStack(spacing: 6) {
            // Tab color indicator
            if let color = tab.tabColor.displayColor {
                Circle()
                    .fill(Color(nsColor: color))
                    .frame(width: 8, height: 8)
            } else {
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                    .frame(width: 8, height: 8)
            }

            // Tab title
            Text(tabDisplayTitle)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            // Close button (visible on hover or when selected)
            if isHovering || isSelected {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 16, height: 16)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
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
