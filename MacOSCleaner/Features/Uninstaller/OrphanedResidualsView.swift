import SwiftUI
import AppKit
import OSLog

private extension Logger {
    static let orphanView = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.macos-cleaner", category: "OrphanedResidualsView")
}

public struct OrphanedResidualsView: View {
    let service: UninstallerService
    let settings: AppSettings

    @State private var items: [OrphanItem] = []
    @State private var isLoading = false
    @State private var hasScanned = false
    @State private var scanProgressMessage = ""
    @State private var searchText = ""
    @State private var selectedFilterTier: ConfidenceTier? = nil
    @State private var expandedItemIDs: Set<UUID> = []
    @State private var showingConfirmation = false
    @State private var isCleaning = false
    @State private var scanTask: Task<Void, Never>? = nil

    public init(service: UninstallerService, settings: AppSettings) {
        self.service = service
        self.settings = settings
    }

    private var filteredItems: [OrphanItem] {
        items.filter { item in
            let matchesSearch = searchText.isEmpty
                || item.name.localizedCaseInsensitiveContains(searchText)
                || (item.bundleID?.localizedCaseInsensitiveContains(searchText) ?? false)
                || item.url.path.localizedCaseInsensitiveContains(searchText)

            let matchesTier: Bool
            if let filterTier = selectedFilterTier {
                matchesTier = item.confidence == filterTier
            } else {
                matchesTier = true
            }

            return matchesSearch && matchesTier
        }
    }

    private var selectedItems: [OrphanItem] {
        items.filter(\.isSelected)
    }

    private var selectedSizeBytes: Int64 {
        selectedItems.reduce(0) { $0 + $1.sizeBytes }
    }

    private var totalFoundSizeBytes: Int64 {
        items.reduce(0) { $0 + $1.sizeBytes }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Content
            if isLoading {
                AnimatedScanView(
                    title: "uninstaller_scanning_leftovers".localized,
                    subtitle: scanProgressMessage,
                    currentStep: 1,
                    totalSteps: 1
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !hasScanned {
                heroStateView
            } else if items.isEmpty {
                emptyStateView
            } else {
                resultsView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog(
            "uninstaller_confirm_trash_leftovers_title".localized,
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("uninstaller_move_trash".localized, role: .destructive) {
                performCleaning()
            }
            Button("cancel".localized, role: .cancel) { }
        } message: {
            Text(String(
                format: "uninstaller_confirm_trash_leftovers_message".localized,
                Int64(selectedItems.count),
                ByteCountFormatter.localizedString(fromByteCount: selectedSizeBytes, countStyle: .file)
            ))
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

            Button(action: startScan) {
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

            Button(action: startScan) {
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
                // Search box
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    TextField("uninstaller_search".localized, text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
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

                // Filter chips
                HStack(spacing: 4) {
                    filterChip(title: "uninstaller_filter_all".localized, tier: nil)
                    filterChip(title: ConfidenceTier.guaranteed.displayKey.localized, tier: .guaranteed)
                    filterChip(title: ConfidenceTier.veryLikely.displayKey.localized, tier: .veryLikely)
                    filterChip(title: ConfidenceTier.possible.displayKey.localized, tier: .possible)
                }

                Spacer()

                Button(action: startScan) {
                    Image(systemName: "arrow.clockwise")
                }
                .glassButtonStyle()
                .help("uninstaller_reload".localized)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.2))

            Divider()

            // List of items
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
                    Text(items.allSatisfy(\.isSelected) ? "deselect_all".localized : "select_all".localized)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)

                Text("•")
                    .foregroundColor(.secondary)
                    .font(.caption2)

                Text(String(format: "uninstaller_leftovers_found_count".localized, Int64(items.count)))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text(String(format: "uninstaller_space_reclaim".localized, ByteCountFormatter.localizedString(fromByteCount: selectedSizeBytes, countStyle: .file)))
                    .font(.headline)

                Button(action: { showingConfirmation = true }) {
                    HStack(spacing: 6) {
                        if isCleaning {
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
                .disabled(selectedItems.isEmpty || isCleaning)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        }
    }

    @ViewBuilder
    private func filterChip(title: String, tier: ConfidenceTier?) -> some View {
        let isSelected = selectedFilterTier == tier
        Button(action: {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                selectedFilterTier = tier
            }
        }) {
            Text(title)
                .font(.caption2)
                .fontWeight(isSelected ? .bold : .medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(
                    Capsule().fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
    }

    private func toggleSelectAll() {
        let allSelected = items.allSatisfy(\.isSelected)
        for i in items.indices {
            items[i].isSelected = !allSelected
        }
    }

    @ViewBuilder
    private func orphanRow(for item: OrphanItem) -> some View {
        let isExpanded = expandedItemIDs.contains(item.id)
        let index = items.firstIndex(where: { $0.id == item.id })

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Toggle("", isOn: Binding(
                    get: { item.isSelected },
                    set: { val in
                        if let idx = index {
                            items[idx].isSelected = val
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
                            expandedItemIDs.remove(item.id)
                        } else {
                            expandedItemIDs.insert(item.id)
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

    // MARK: - Actions

    private func startScan() {
        scanTask?.cancel()
        isLoading = true
        scanProgressMessage = "uninstaller.progress.discovering".localized

        scanTask = Task {
            do {
                let found = try await service.scanOrphanedResiduals()
                await MainActor.run {
                    self.items = found
                    self.isLoading = false
                    self.hasScanned = true
                }
            } catch {
                Logger.orphanView.error("Orphan scan failed: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    self.isLoading = false
                    self.hasScanned = true
                }
            }
        }
    }

    private func performCleaning() {
        let targets = selectedItems
        guard !targets.isEmpty else { return }

        isCleaning = true
        Task {
            defer { isCleaning = false }
            do {
                let freed = try await service.removeOrphanedResiduals(
                    targets,
                    bypassTrash: settings.bypassTrashOnUninstall
                )
                
                await MainActor.run {
                    let removedIDs = Set(targets.map(\.id))
                    self.items.removeAll { removedIDs.contains($0.id) }
                    
                    if settings.showNotifications {
                        let title = "uninstaller_complete_title".localized
                        let body = String(
                            format: "uninstaller_leftovers_cleaned_notification".localized,
                            Int64(targets.count),
                            ByteCountFormatter.localizedString(fromByteCount: freed, countStyle: .file)
                        )
                        NotificationManager.shared.sendNotification(title: title, body: body)
                    }
                }
            } catch {
                Logger.orphanView.error("Cleaning failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
