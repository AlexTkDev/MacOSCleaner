import SwiftUI

/// Reusable glass-style pill picker matching the top navigation bar design.
/// Replaces `.pickerStyle(.segmented)` across the app for visual consistency.
struct GlassPillPicker<T: Hashable>: View {
    let items: [T]
    @Binding var selection: T
    let label: (T) -> String

    var body: some View {
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
                        .fixedSize()
                        .padding(.horizontal, 12)
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
