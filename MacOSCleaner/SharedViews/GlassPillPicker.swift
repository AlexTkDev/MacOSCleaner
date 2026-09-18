import SwiftUI

/// Reusable glass-style pill picker matching the top navigation bar design.
/// Replaces `.pickerStyle(.segmented)` across the app for visual consistency.
/// Shrinks horizontal padding when the available width is tight.
struct GlassPillPicker<T: Hashable>: View {
    let items: [T]
    @Binding var selection: T
    var icon: ((T) -> String)? = nil
    let label: (T) -> String

    @Environment(\.locale) private var locale

    init(
        items: [T],
        selection: Binding<T>,
        icon: ((T) -> String)? = nil,
        label: @escaping (T) -> String
    ) {
        self.items = items
        self._selection = selection
        self.icon = icon
        self.label = label
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            pillRow(horizontalPadding: 12)
            pillRow(horizontalPadding: 8)
            pillRow(horizontalPadding: 6)
        }
        // glassEffect can retain a previous text snapshot — force rebuild on locale change.
        .id(locale.identifier)
    }

    private func pillRow(horizontalPadding: CGFloat) -> some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                let isSelected = selection == item
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        selection = item
                    }
                } label: {
                    HStack(spacing: 5) {
                        if let iconName = icon?(item) {
                            Image(systemName: iconName)
                                .font(.system(size: 11, weight: .medium))
                        }
                        Text(label(item))
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, 5)
                    .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.75))
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.accentColor.opacity(0.88),
                                            Color.accentColor.opacity(0.72)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(
                                            LinearGradient(
                                                stops: [
                                                    .init(color: Color.white.opacity(0.50), location: 0.0),
                                                    .init(color: Color.accentColor.opacity(0.5), location: 0.5),
                                                    .init(color: Color.white.opacity(0.12), location: 1.0)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                                .shadow(color: Color.accentColor.opacity(0.35), radius: 6, x: 0, y: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .glassEffect(Glass.regular, in: Capsule())
    }
}
