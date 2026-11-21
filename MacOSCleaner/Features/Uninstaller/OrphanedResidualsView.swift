import SwiftUI
import AppKit
import OSLog

private extension Logger {
    static let orphanView = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.macos-cleaner", category: "OrphanedResidualsView")
}

public struct OrphanedResidualsView: View {
    @Bindable var viewModel: UninstallerViewModel
    let settings: AppSettings

    @State private var showingConfirmation = false

    public init(viewModel: UninstallerViewModel, settings: AppSettings) {
        self.viewModel = viewModel
        self.settings = settings
    }

    private var filteredItems: [OrphanItem] {
        viewModel.orphanItems.filter { item in
            let matchesSearch = viewModel.orphanSearchText.isEmpty
                || item.name.localizedCaseInsensitiveContains(viewModel.orphanSearchText)
                || (item.bundleID?.localizedCaseInsensitiveContains(viewModel.orphanSearchText) ?? false)
                || item.url.path.localizedCaseInsensitiveContains(viewModel.orphanSearchText)

            let matchesTier: Bool
            if let filterTier = viewModel.orphanFilterTier {
                matchesTier = item.confidence == filterTier
            } else {
                matchesTier = true
            }

            return matchesSearch && matchesTier
        }
    }

    private var selectedItems: [OrphanItem] {
        viewModel.orphanItems.filter(\.isSelected)
    }

    private var selectedSizeBytes: Int64 {
        selectedItems.reduce(0) { $0 + $1.sizeBytes }
    }

    public var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoadingOrphans {
                AnimatedScanView(
                    title: "uninstaller_scanning_leftovers".localized,
                    subtitle: viewModel.orphanScanProgressMessage,
                    currentStep: 1,
                    totalSteps: 1
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !viewModel.hasScannedOrphans {
                heroStateView
            } else if viewModel.orphanItems.isEmpty {
                emptyStateView
            } else {
                resultsView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog(
            settings.bypassTrashOnUninstall
                ? "uninstaller_confirm_perm_delete".localized
                : "uninstaller_confirm_trash_leftovers_title".localized,
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                settings.bypassTrashOnUninstall
                    ? "uninstaller_delete_permanently".localized
                    : "uninstaller_move_trash".localized,
                role: .destructive
            ) {
                viewModel.cleanSelectedOrphans(selectedItems, settings: settings)
            }
            Button("cancel".localized, role: .cancel) { }
        } message: {
            Text(String(
                format: "uninstaller_confirm_trash_leftovers_message".localized,
                Int64(selectedItems.count),
                ByteCountFormatter.localizedString(fromByteCount: selectedSizeBytes, countStyle: .file)
            ))
        }
        .alert("error".localized, isPresented: $viewModel.showingOrphanErrorAlert) {
            Button("ok".localized, role: .cancel) { }
        } message: {
            if let errorMessage = viewModel.orphanErrorMessage {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Hero View

    private var heroStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "shippingbox.and.arrow.backward")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor.gradient)
                .padding(.bottom, 4)

            VStack(spacing: 8) {
                Text("uninstaller_leftovers_hero_title".localized)
                    .font(.title2)
                    .fontWeight(.bold)

                Text("uninstaller_leftovers_hero_subtitle".localized)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }

            Button(action: { viewModel.startOrphanScan() }) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    Text("uninstaller_start_leftover_scan".localized)
                        .font(.headline)
                }
                .frame(minWidth: 200, minHeight: 32)
            }
            .glassButtonStyle()
            .controlSize(.large)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            VStack(spacing: 6) {
                Text("uninstaller_no_leftovers_title".localized)
                    .font(.title3)
                    .fontWeight(.bold)

                Text("uninstaller_no_leftovers_subtitle".localized)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Button(action: { viewModel.startOrphanScan() }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("uninstaller_reload".localized)
                }
            }
            .glassButtonStyle()
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    // MARK: - Results View

    private var resultsView: some View {
        VStack(spacing: 0) {
            // Filter Bar
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    TextField("uninstaller_search".localized, text: $viewModel.orphanSearchText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                    if !viewModel.orphanSearchText.isEmpty {
                        Button(action: { viewModel.orphanSearchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                .cornerRadius(8)
                .frame(maxWidth: 240)

                HStack(spacing: 4) {
                    filterChip(title: "uninstaller_filter_all".localized, tier: nil)
                    filterChip(title: ConfidenceTier.guaranteed.displayKey.localized, tier: .guaranteed)
                    filterChip(title: ConfidenceTier.veryLikely.displayKey.localized, tier: .veryLikely)
                    filterChip(title: ConfidenceTier.possible.displayKey.localized, tier: .possible)
                }

                Spacer()

                Button(action: { viewModel.startOrphanScan() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .glassButtonStyle()
                .help("uninstaller_reload".localized)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            Divider()

            List {
                ForEach(filteredItems) { item in
                    orphanRow(for: item)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)

            Divider()

            // Bottom Action Bar
            HStack(spacing: 12) {
                Button(action: toggleSelectAll) {
                    Text(viewModel.orphanItems.allSatisfy(\.isSelected) ? "deselect_all".localized : "select_all".localized)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)

                Text("•")
                    .foregroundColor(.secondary)
                    .font(.caption2)

                Text(String(format: "uninstaller_leftovers_found_count".localized, Int64(viewModel.orphanItems.count)))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text(String(format: "uninstaller_space_reclaim".localized, ByteCountFormatter.localizedString(fromByteCount: selectedSizeBytes, countStyle: .file)))
                    .font(.headline)

                Button(action: { showingConfirmation = true }) {
                    HStack(spacing: 6) {
                        if viewModel.isCleaningOrphans {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "trash")
                        }
                        Text("uninstaller_clean_selected_leftovers".localized)
                            .font(.headline)
                    }
                    .frame(minWidth: 160, minHeight: 30)
                }
                .destructiveGlassButtonStyle()
                .controlSize(.large)
                .disabled(selectedItems.isEmpty || viewModel.isCleaningOrphans)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private func filterChip(title: String, tier: ConfidenceTier?) -> some View {
        let isSelected = viewModel.orphanFilterTier == tier
        Button(action: {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                viewModel.orphanFilterTier = tier
            }
        }) {
            Text(title)
                .font(.caption2)
                .fontWeight(isSelected ? .bold : .medium)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.85))
                .background(
                    Capsule().fill(isSelected ? Color.accentColor : Color.black.opacity(0.35))
                )
                .overlay(
                    Capsule().strokeBorder(isSelected ? Color.white.opacity(0.2) : Color.white.opacity(0.08), lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
    }

    private func toggleSelectAll() {
        let allSelected = viewModel.orphanItems.allSatisfy(\.isSelected)
        for i in viewModel.orphanItems.indices {
            viewModel.orphanItems[i].isSelected = !allSelected
        }
    }

    @ViewBuilder
    private func orphanRow(for item: OrphanItem) -> some View {
        let isExpanded = viewModel.expandedOrphanIDs.contains(item.id)
        let index = viewModel.orphanItems.firstIndex(where: { $0.id == item.id })

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Toggle("", isOn: Binding(
                    get: { item.isSelected },
                    set: { val in
                        if let idx = index {
                            viewModel.orphanItems[idx].isSelected = val
                        }
                    }
                ))
                .toggleStyle(.checkbox)

                Image(systemName: iconForCategory(item.category))
                    .foregroundColor(.secondary)
                    .font(.body)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)

                        if let bid = item.bundleID {
                            Text(bid)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(4)
                        }

                        Text(item.category)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.08))
                            .cornerRadius(4)

                        ConfidenceBadgeView(tier: item.confidence)
                    }

                    Text(NormalizedPath.displayString(item.url))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                if let date = item.modificationDate {
                    Text(date.formatted(.dateTime.year().month().day().locale(LanguageManager.shared.currentLocale)))
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }

                Text(ByteCountFormatter.localizedString(fromByteCount: item.sizeBytes, countStyle: .file))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                        .foregroundColor(.accentColor)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("uninstaller_show_in_finder".localized)

                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        if isExpanded {
                            viewModel.expandedOrphanIDs.remove(item.id)
                        } else {
                            viewModel.expandedOrphanIDs.insert(item.id)
                        }
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "info.circle")
                        .foregroundColor(isExpanded ? .accentColor : .secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("uninstaller_evidence_why_flagged".localized)
            }

            if isExpanded {
                EvidenceCardView(
                    appName: item.name,
                    bundleID: item.bundleID,
                    evidence: item.evidence,
                    score: item.score,
                    tier: item.confidence
                )
                .padding(.leading, 28)
                .padding(.top, 2)
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .cornerRadius(8)
    }

    private func iconForCategory(_ category: String) -> String {
        switch category {
        case "Preferences": return "gearshape.fill"
        case "Application Support": return "folder.fill"
        case "Caches": return "archivebox.fill"
        case "Containers": return "shippingbox.fill"
        case "Logs": return "doc.text.fill"
        case "Developer": return "wrench.and.screwdriver.fill"
        default: return "doc.fill"
        }
    }
}
