import SwiftUI
import AppKit

public struct PostUninstallLeftoversSheet: View {
    @Binding var report: VerificationReport?
    let onClean: ([LeftoverItem]) -> Void
    let onDismiss: () -> Void

    @State private var items: [LeftoverItem] = []
    @State private var expandedItemIDs: Set<UUID> = []

    public init(
        report: Binding<VerificationReport?>,
        onClean: @escaping ([LeftoverItem]) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self._report = report
        self.onClean = onClean
        self.onDismiss = onDismiss
    }

    private var selectedCount: Int {
        items.filter(\.isSelected).count
    }

    private var selectedSizeBytes: Int64 {
        items.filter(\.isSelected).reduce(0) { $0 + $1.sizeBytes }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("uninstaller_post_leftovers_title".localized)
                        .font(.headline)
                        .fontWeight(.bold)

                    if let rep = report {
                        Text(String(format: "uninstaller_post_leftovers_subtitle".localized, rep.appName))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            // Leftover list
            ScrollView {
                VStack(spacing: 8) {
                    ForEach($items) { $item in
                        leftoverRow(for: $item)
                    }
                }
                .padding(16)
            }
            .frame(maxHeight: 360)

            Divider()

            // Action footer
            HStack {
                Button(action: toggleSelectAll) {
                    Text(items.allSatisfy(\.isSelected) ? "deselect_all".localized : "select_all".localized)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)

                Spacer()

                Text(String(format: "uninstaller_space_reclaim".localized, ByteCountFormatter.localizedString(fromByteCount: selectedSizeBytes, countStyle: .file)))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                Button("close".localized, action: onDismiss)
                    .glassButtonStyle()

                Button(action: {
                    let selected = items.filter(\.isSelected)
                    onClean(selected)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                        Text("uninstaller_clean_selected_leftovers".localized)
                    }
                }
                .destructiveGlassButtonStyle()
                .disabled(selectedCount == 0)
            }
            .padding(16)
        }
        .frame(minWidth: 540, maxWidth: 640)
        .onAppear {
            if let rep = report {
                self.items = rep.items
            }
        }
    }

    private func toggleSelectAll() {
        let allSelected = items.allSatisfy(\.isSelected)
        for i in items.indices {
            items[i].isSelected = !allSelected
        }
    }

    @ViewBuilder
    private func leftoverRow(for itemBinding: Binding<LeftoverItem>) -> some View {
        let item = itemBinding.wrappedValue
        let isExpanded = expandedItemIDs.contains(item.id)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Toggle("", isOn: itemBinding.isSelected)
                    .toggleStyle(.checkbox)

                Image(systemName: iconForURL(item.url))
                    .foregroundColor(.secondary)
                    .font(.subheadline)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.url.lastPathComponent)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)

                        ConfidenceBadgeView(tier: item.confidence)
                    }

                    Text(NormalizedPath.displayString(item.url))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

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

                if !item.rawEvidence.isEmpty || !item.evidence.isEmpty {
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
            }

            if isExpanded {
                EvidenceCardView(
                    appName: item.appName,
                    bundleID: item.bundleID,
                    evidence: item.rawEvidence,
                    artifactEvidence: item.evidence,
                    score: item.score,
                    tier: item.confidence
                )
                .padding(.leading, 28)
                .padding(.top, 2)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .cornerRadius(8)
    }

    private func iconForURL(_ url: URL) -> String {
        let path = url.path
        if path.contains("/Preferences/") { return "gearshape.fill" }
        if path.contains("/Application Support/") { return "folder.fill" }
        if path.contains("/Caches/") { return "archivebox.fill" }
        if path.contains("/Containers/") || path.contains("/Group Containers/") { return "shippingbox.fill" }
        if path.contains("/LaunchAgents/") || path.contains("/LaunchDaemons/") { return "bolt.horizontal.fill" }
        if path.contains("/Logs/") { return "doc.text.fill" }
        return "doc.fill"
    }
}

public struct ConfidenceBadgeView: View {
    let tier: ConfidenceTier

    public init(tier: ConfidenceTier) {
        self.tier = tier
    }

    private var color: Color {
        switch tier {
        case .guaranteed: return .green
        case .veryLikely: return .blue
        case .possible: return .orange
        case .ignore: return .gray
        }
    }

    private var icon: String {
        switch tier {
        case .guaranteed: return "checkmark.shield.fill"
        case .veryLikely: return "shield.fill"
        case .possible: return "questionmark.circle.fill"
        case .ignore: return "slash.circle"
        }
    }

    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
            Text(tier.displayKey.localized)
                .font(.system(size: 9, weight: .semibold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundStyle(color)
        .background(Capsule().fill(color.opacity(0.12)))
        .overlay(
            Capsule().strokeBorder(color.opacity(0.25), lineWidth: 0.8)
        )
    }
}

public struct EvidenceCardView: View {
    let appName: String
    let bundleID: String?
    let evidence: Set<Evidence>
    let artifactEvidence: [ArtifactEvidence]
    let score: Int
    let tier: ConfidenceTier

    public init(
        appName: String,
        bundleID: String?,
        evidence: Set<Evidence>,
        artifactEvidence: [ArtifactEvidence] = [],
        score: Int = 0,
        tier: ConfidenceTier = .possible
    ) {
        self.appName = appName
        self.bundleID = bundleID
        self.evidence = evidence
        self.artifactEvidence = artifactEvidence
        self.score = score
        self.tier = tier
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass.circle.fill")
                    .foregroundColor(.accentColor)
                    .font(.caption)
                Text("uninstaller_evidence_card_title".localized)
                    .font(.caption)
                    .fontWeight(.bold)
                Spacer()
                Text("Score: \(score)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            if !evidence.isEmpty {
                let context = ExplanationContext(bundleID: bundleID, appName: appName, teamID: nil)
                let grouped = EvidenceExplanations.explanations(for: evidence, context: context)
                ForEach(Array(grouped.keys.sorted(by: { $0.rawValue < $1.rawValue })), id: \.self) { category in
                    if let items = grouped[category], !items.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(items, id: \.self) { expl in
                                HStack(alignment: .top, spacing: 4) {
                                    Text("•")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(expl.title)
                                            .font(.system(size: 10, weight: .semibold))
                                        Text(expl.description)
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            } else if !artifactEvidence.isEmpty {
                ForEach(artifactEvidence, id: \.self) { art in
                    HStack(spacing: 4) {
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\(String(describing: art.source)) (+\(art.weight))")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(8)
        .background(Color.accentColor.opacity(0.06))
        .cornerRadius(6)
    }
}
