import SwiftUI

struct NavRailHoverTarget: Equatable {
    let item: NavigationItem
    let anchor: Anchor<CGRect>

    static func == (lhs: NavRailHoverTarget, rhs: NavRailHoverTarget) -> Bool {
        lhs.item == rhs.item
    }
}

struct NavRailHoverPreferenceKey: PreferenceKey {
    static let defaultValue: NavRailHoverTarget? = nil

    static func reduce(value: inout NavRailHoverTarget?, nextValue: () -> NavRailHoverTarget?) {
        value = nextValue() ?? value
    }
}

/// Compact 48pt icon-only Navigation Rail grouped by `SidebarSection.all`.
struct NavigationRailView: View {
    @Binding var selectedItem: NavigationItem
    @State private var hoveredItem: NavigationItem? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var topSections: [SidebarSection] {
        SidebarSection.all.compactMap { section in
            let filtered = section.items.filter { $0 != .settings }
            return filtered.isEmpty ? nil : SidebarSection(titleKey: section.titleKey, items: filtered)
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(topSections.indices, id: \.self) { index in
                if index > 0 {
                    sectionDivider
                }

                VStack(spacing: 4) {
                    ForEach(topSections[index].items) { item in
                        railButton(for: item)
                    }
                }
            }

            Spacer(minLength: 0)

            sectionDivider
            railButton(for: .settings)
        }
        .padding(.top, 44)
        .padding(.bottom, 12)
        .frame(width: 48)
        .frame(maxHeight: .infinity)
        .background {
            if reduceTransparency {
                Color(NSColor.windowBackgroundColor)
            } else {
                Color.clear
            }
        }
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.primary.opacity(0.07))
            .frame(width: 20, height: 1)
            .padding(.vertical, 4)
    }

    private func railButton(for item: NavigationItem) -> some View {
        let isSelected = selectedItem == item
        let isHovered = hoveredItem == item

        return Button {
            if reduceMotion {
                selectedItem = item
            } else {
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedItem = item
                }
            }
        } label: {
            Image(systemName: item.systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(iconColor(isSelected: isSelected, isHovered: isHovered))
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(buttonBackground(isSelected: isSelected, isHovered: isHovered))
                )
                .shadow(
                    color: isSelected ? Color.accentColor.opacity(0.35) : .clear,
                    radius: isSelected ? 6 : 0,
                    x: 0,
                    y: isSelected ? 2 : 0
                )
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(item.keyboardKey, modifiers: .command)
        .accessibilityLabel(item.localizedTitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { hovering in
            if hovering {
                hoveredItem = item
            } else if hoveredItem == item {
                hoveredItem = nil
            }
        }
        .anchorPreference(key: NavRailHoverPreferenceKey.self, value: .bounds) { anchor in
            isHovered ? NavRailHoverTarget(item: item, anchor: anchor) : nil
        }
    }

    private func iconColor(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return .white
        }
        if colorScheme == .dark {
            return Color.white.opacity(isHovered ? 0.88 : 0.55)
        }
        return Color.primary.opacity(isHovered ? 0.90 : 0.55)
    }

    private func buttonBackground(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return Color.accentColor
        }
        if isHovered {
            return colorScheme == .dark ? Color.white.opacity(0.07) : Color.primary.opacity(0.07)
        }
        return .clear
    }
}

/// Floating tooltip rendered at `RootView` level so it is never clipped by the 48pt rail or split views.
struct NavRailTooltipLabel: View {
    let title: String

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(textColor)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.14), radius: 8, x: 0, y: 3)
    }

    private var textColor: Color {
        if reduceTransparency && colorScheme == .light {
            return .primary
        }
        return colorScheme == .dark ? .white : .primary
    }

    private var backgroundColor: Color {
        if reduceTransparency {
            return Color(NSColor.controlBackgroundColor)
        }
        return colorScheme == .dark ? Color(white: 0.14) : Color(NSColor.controlBackgroundColor)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.primary.opacity(0.12)
    }
}
