import SwiftUI

struct PrivacyView: View {
    let permissionsManager: PermissionsManager
    @Binding var initialBundleIDFilter: String?

    @State private var viewModel = PrivacyViewModel()
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 0) {
                headerBar

                Divider()

                if let notice = viewModel.actionNotice {
                    noticeBanner(notice, isError: false)
                } else if let error = viewModel.errorMessage {
                    noticeBanner(error, isError: true)
                }

                tabContent
            }
        }
        .onAppear {
            applyInitialBundleFilter()
            Task { await viewModel.loadTCCIfNeeded() }
        }
        .onChange(of: initialBundleIDFilter) { _, _ in
            applyInitialBundleFilter()
        }
        .onChange(of: viewModel.selectedTab) { _, tab in
            Task {
                switch tab {
                case .tcc: await viewModel.loadTCCIfNeeded()
                case .network: await viewModel.captureNetworkSnapshotIfNeeded()
                case .extensions: await viewModel.loadExtensionsIfNeeded()
                }
            }
        }
        .background {
            Button("") { isSearchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        }
    }

    private func applyInitialBundleFilter() {
        if let bundleID = initialBundleIDFilter, !bundleID.isEmpty {
            viewModel.selectedTab = .tcc
            viewModel.searchText = bundleID
            initialBundleIDFilter = nil
        }
    }

    private var headerBar: some View {
        WorkspaceHeaderBar {
            GlassPillPicker(
                items: PrivacyTab.allCases,
                selection: $viewModel.selectedTab,
                icon: { $0.iconName },
                label: { $0.localizedTitle }
            )

            Spacer()

            CompactSearchField(
                placeholder: "privacy_search_placeholder".localized,
                text: $viewModel.searchText,
                width: 210
            )
            .focused($isSearchFocused)

            Button {
                Task { await viewModel.refreshCurrentTab() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .glassButtonStyle()
            .help("privacy_refresh".localized)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.selectedTab {
        case .tcc:
            PrivacyTCCView(viewModel: viewModel, permissionsManager: permissionsManager)
        case .network:
            PrivacyNetworkView(viewModel: viewModel)
        case .extensions:
            PrivacyExtensionsView(viewModel: viewModel)
        }
    }

    private func noticeBanner(_ text: String, isError: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(isError ? .red : .accentColor)
            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button {
                if isError { viewModel.errorMessage = nil } else { viewModel.actionNotice = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background((isError ? Color.red : Color.accentColor).opacity(0.08))
    }
}
