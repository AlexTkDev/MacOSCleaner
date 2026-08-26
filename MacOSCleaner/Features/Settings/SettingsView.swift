import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let permissionsManager: PermissionsManager
    let onForget: () -> Void
    @Binding var availableUpdate: AvailableUpdate?

    @State private var selectedCategory: SettingsCategory? = .general
    @State private var searchText: String = ""

    var body: some View {
        HStack(spacing: 0) {
            sidebarContent
                .frame(width: 220)
                
            Divider()
            
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .searchable(text: $searchText, prompt: Text("settings_search_prompt".localized))
        .frame(minWidth: 780, minHeight: 520)
    }

    // MARK: - Custom Sidebar

    private var sidebarContent: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(SettingsCategory.allCases) { category in
                    sidebarRow(for: category)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 14)
            .padding(.bottom, 10)
        }
    }

    private func sidebarRow(for category: SettingsCategory) -> some View {
        let isSelected = (selectedCategory == category)

        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                selectedCategory = category
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: category.iconName)
                    .foregroundStyle(isSelected ? Color.white : category.iconColor)
                    .font(.headline)
                    .frame(width: 22)

                Text(category.displayName)
                    .font(.body.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail View

    @ViewBuilder
    private var detailView: some View {
        if !searchText.isEmpty {
            searchResultsView
        } else {
            switch selectedCategory ?? .general {
            case .general:
                SettingsGeneralView(
                    settings: settings,
                    permissionsManager: permissionsManager,
                    availableUpdate: $availableUpdate,
                    onForget: onForget
                )
            case .cleanup:
                SettingsCleanupView(
                    settings: settings
                )
            case .automation:
                SettingsAutomationView(
                    settings: settings
                )
            case .processes:
                SettingsProcessesView(
                    settings: settings
                )
            case .advanced:
                SettingsAdvancedView(
                    settings: settings
                )
            case .about:
                SettingsAboutView()
            }
        }
    }

    // MARK: - Search Results

    private var searchResultsView: some View {
        let results = SettingsSearchRegistry.search(searchText)
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(format: "settings_search_results_title".localized, searchText))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)

                if results.isEmpty {
                    ContentUnavailableView(
                        "settings_search_no_results".localized,
                        systemImage: "magnifyingglass",
                        description: Text("settings_search_no_results_sub".localized)
                    )
                } else {
                    ForEach(results) { item in
                        Button {
                            searchText = ""
                            selectedCategory = item.category
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.iconName)
                                    .font(.title3)
                                    .foregroundStyle(item.category.iconColor)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    if let subtitle = item.subtitle {
                                        Text(subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                StatusPill(item.category.displayName, iconName: item.category.iconName, style: .neutral, size: .small)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(12)
                            .background(Color.primary.opacity(0.03))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
        }
    }
}

#Preview {
    SettingsView(
        settings: AppSettings(),
        permissionsManager: PermissionsManager(),
        onForget: {},
        availableUpdate: .constant(AvailableUpdate(version: "2.3.0", dmgURL: nil))
    )
}
