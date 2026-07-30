import SwiftUI

// MARK: - Status Pill

enum StatusPillStyle {
    case success
    case warning
    case error
    case info
    case neutral

    var backgroundColor: Color {
        switch self {
        case .success: return Color.green.opacity(0.15)
        case .warning: return Color.orange.opacity(0.15)
        case .error: return Color.red.opacity(0.15)
        case .info: return Color.blue.opacity(0.15)
        case .neutral: return Color.secondary.opacity(0.15)
        }
    }

    var foregroundColor: Color {
        switch self {
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        case .info: return .blue
        case .neutral: return .secondary
        }
    }
}

enum StatusPillSize {
    case small
    case regular
    case large

    var font: Font {
        switch self {
        case .small: return .caption2.bold()
        case .regular: return .caption.bold()
        case .large: return .subheadline.bold()
        }
    }

    var paddingHorizontal: CGFloat {
        switch self {
        case .small: return 6
        case .regular: return 10
        case .large: return 14
        }
    }

    var paddingVertical: CGFloat {
        switch self {
        case .small: return 2
        case .regular: return 4
        case .large: return 6
        }
    }
}

struct StatusPill: View {
    let title: String
    let iconName: String?
    let style: StatusPillStyle
    let size: StatusPillSize

    init(
        _ title: String,
        iconName: String? = nil,
        style: StatusPillStyle = .neutral,
        size: StatusPillSize = .regular
    ) {
        self.title = title
        self.iconName = iconName
        self.style = style
        self.size = size
    }

    var body: some View {
        HStack(spacing: 4) {
            if let iconName {
                Image(systemName: iconName)
            }
            Text(title)
        }
        .font(size.font)
        .padding(.horizontal, size.paddingHorizontal)
        .padding(.vertical, size.paddingVertical)
        .background(style.backgroundColor)
        .foregroundStyle(style.foregroundColor)
        .clipShape(Capsule())
    }
}

// MARK: - Generic Glass Card

struct GlassCard<Header: View, Content: View, Footer: View>: View {
    let header: Header
    let content: Content
    let footer: Footer
    var isDestructive: Bool = false

    init(
        @ViewBuilder header: () -> Header = { EmptyView() },
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer = { EmptyView() },
        isDestructive: Bool = false
    ) {
        self.header = header()
        self.content = content()
        self.footer = footer()
        self.isDestructive = isDestructive
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if Header.self != EmptyView.self {
                header
            }

            content

            if Footer.self != EmptyView.self {
                footer
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isDestructive ? Color.red.opacity(0.08) : Color.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isDestructive ? Color.red.opacity(0.2) : Color.primary.opacity(0.06), lineWidth: 1)
                )
        }
    }
}

// MARK: - Metric & Status Cards

struct SettingsMetricCard: View {
    let title: String
    let value: String
    let subtitle: String?
    let iconName: String
    let iconColor: Color

    var body: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundStyle(iconColor)
                    .frame(width: 36, height: 36)
                    .background(iconColor.opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.title3.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct SettingsCardGrid<Content: View>: View {
    let columns: [GridItem]
    let content: Content

    init(
        columnCount: Int = 2,
        spacing: CGFloat = 12,
        @ViewBuilder content: () -> Content
    ) {
        self.columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnCount)
        self.content = content()
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            content
        }
    }
}

// MARK: - Section Header & Rows

struct SettingsSectionHeader: View {
    let title: String
    let subtitle: String?
    let iconName: String?
    let iconColor: Color

    init(
        _ title: String,
        subtitle: String? = nil,
        iconName: String? = nil,
        iconColor: Color = .blue
    ) {
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.iconColor = iconColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let iconName {
                    Image(systemName: iconName)
                        .foregroundStyle(iconColor)
                        .font(.headline)
                }
                Text(title)
                    .font(.headline)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 4)
    }
}

struct SettingsToggleRow: View {
    let title: String
    let subtitle: String?
    let iconName: String?
    @Binding var isOn: Bool

    init(
        _ title: String,
        subtitle: String? = nil,
        iconName: String? = nil,
        isOn: Binding<Bool>
    ) {
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self._isOn = isOn
    }

    var body: some View {
        HStack(spacing: 12) {
            if let iconName {
                Image(systemName: iconName)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
    }
}

struct SettingsActionRow: View {
    let title: String
    let subtitle: String?
    let iconName: String?
    let buttonTitle: String
    let buttonIcon: String?
    let isDestructive: Bool
    let action: () -> Void

    init(
        _ title: String,
        subtitle: String? = nil,
        iconName: String? = nil,
        buttonTitle: String,
        buttonIcon: String? = nil,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.buttonTitle = buttonTitle
        self.buttonIcon = buttonIcon
        self.isDestructive = isDestructive
        self.action = action
    }

    var body: some View {
        HStack(spacing: 12) {
            if let iconName {
                Image(systemName: iconName)
                    .foregroundStyle(isDestructive ? .red : .secondary)
                    .frame(width: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(role: isDestructive ? .destructive : nil, action: action) {
                HStack(spacing: 4) {
                    if let buttonIcon {
                        Image(systemName: buttonIcon)
                    }
                    Text(buttonTitle)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(isDestructive ? .red : .accentColor)
            .controlSize(.small)
        }
    }
}

struct SettingsInfoRow: View {
    let title: String
    let value: String
    let iconName: String?

    init(_ title: String, value: String, iconName: String? = nil) {
        self.title = title
        self.value = value
        self.iconName = iconName
    }

    var body: some View {
        HStack(spacing: 12) {
            if let iconName {
                Image(systemName: iconName)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
            }
            Text(title)
                .font(.body)
            Spacer()
            Text(value)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider()
            .opacity(0.5)
            .padding(.vertical, 2)
    }
}
