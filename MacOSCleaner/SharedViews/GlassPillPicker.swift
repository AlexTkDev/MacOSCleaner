import SwiftUI

/// Reusable glass-style pill picker matching the top navigation bar design.
/// Replaces `.pickerStyle(.segmented)` across the app for visual consistency.
/// Shrinks horizontal padding when the available width is tight.
struct GlassPillPicker<T: Hashable>: View {
    let items: [T]
    @Binding var selection: T
    let label: (T) -> String

    @Environment(\.locale) private var locale

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
                    Text(label(item))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.vertical, 5)
                        .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.6))
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color.accentColor)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .glassEffect(Glass.regular, in: RoundedRectangle(cornerRadius: 12))
    }
}
