import SwiftUI

public struct StartupServicesView: View {
    let settings: AppSettings
    @State private var viewModel = StartupServicesViewModel()

    public var body: some View {
        GlassEffectContainer {
            VStack(spacing: 0) {
                filterPicker
                    .padding()

                if viewModel.isLoading {
                    AnimatedScanView(
                        title: "startup_scanning".localized,
                        subtitle: "",
                        currentStep: 0,
                        totalSteps: 1
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.lastError {
                    errorView(error)
                } else if viewModel.services.isEmpty {
                    emptyView
                } else {
                    serviceList
                }
            }
        }
        .navigationSubtitle("startup_subtitle".localized)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { Task { await viewModel.scan() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("startup_refresh".localized)
            }
        }
        .onAppear { Task { await viewModel.scan() } }
    }

    private var filterPicker: some View {
        HStack(spacing: 8) {
            filterButton(title: "startup_filter_all".localized, tag: nil, count: viewModel.services.count)

            Divider().frame(height: 16)

            filterButton(
                title: "startup_category_user".localized,
                tag: .user,
                count: viewModel.userCount,
                icon: ServiceCategory.user.icon,
                color: ServiceCategory.user.color
            )

            filterButton(
                title: "startup_category_third_party".localized,
                tag: .thirdParty,
                count: viewModel.thirdPartyCount,
                icon: ServiceCategory.thirdParty.icon,
                color: ServiceCategory.thirdParty.color
            )

            filterButton(
                title: "startup_category_system".localized,
                tag: .system,
                count: viewModel.systemCount,
                icon: ServiceCategory.system.icon,
                color: ServiceCategory.system.color
            )
        }
        .padding(.horizontal, 4)
    }

    private func filterButton(
        title: String,
        tag: ServiceCategory?,
        count: Int,
        icon: String? = nil,
        color: Color? = nil
    ) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.filter = tag
            }
        }) {
            HStack(spacing: 4) {
                if let icon, let color {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundColor(color)
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(viewModel.filter == tag
                                  ? (color ?? Color.accentColor).opacity(0.2)
                                  : Color.secondary.opacity(0.1))
                    )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(viewModel.filter == tag
                          ? (color ?? Color.accentColor).opacity(0.1)
                          : Color.clear)
            )
            .overlay(
                Capsule()
                    .stroke(viewModel.filter == tag
                            ? (color ?? Color.accentColor).opacity(0.3)
                            : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var serviceList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.filteredServices) { service in
                    ServiceRow(service: service, settings: settings) {
                        Task { await viewModel.toggle(service: service) }
                    }
                    if service.id != viewModel.filteredServices.last?.id {
                        Divider().padding(.leading, 120)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .glassCard()
            .padding()
        }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bolt.horizontal.circle")
                .font(.system(size: 64, weight: .thin))
                .foregroundColor(.secondary.opacity(0.5))
            VStack(spacing: 8) {
                Text("startup_no_agents".localized)
                    .font(.headline)
                Text("startup_no_agents_sub".localized)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 64, weight: .thin))
                .foregroundColor(.orange)
            VStack(spacing: 8) {
                Text("startup_scan_failed".localized)
                    .font(.headline)
                Text(error)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Button("try_again".localized) {
                Task { await viewModel.scan() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ServiceRow: View {
    let service: StartupService
    let settings: AppSettings
    let onToggle: () -> Void

    @State private var isExpanded = false
    @State private var aiExplanation = ""
    @State private var isGenerating = false
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                CategoryBadge(category: service.category)

                VStack(alignment: .leading, spacing: 4) {
                    Text(service.name)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                    Text(service.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                if settings.enableAI && AIExplanationService.shared.isAvailable {
                    Button {
                        withAnimation(.spring()) {
                            isExpanded.toggle()
                        }
                        if isExpanded && aiExplanation.isEmpty && !isGenerating {
                            generateAIExplanation()
                        }
                    } label: {
                        Image(systemName: "sparkles")
                            .foregroundColor(isExpanded ? .purple : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("uninstaller_explain_with_ai".localized)
                }

                StatusBadge(isEnabled: service.isEnabled)

                Button(service.isEnabled ? "startup_disable".localized : "startup_enable".localized) {
                    onToggle()
                }
                .buttonStyle(.bordered)
                .tint(service.isEnabled ? .red : .accentColor)
                .controlSize(.small)
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Divider().padding(.vertical, 4)
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "sparkles")
                            .foregroundColor(.purple)
                            .font(.caption)
                        
                        if isGenerating {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("uninstaller_ai_explaining".localized)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        } else {
                            Text(aiExplanation)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.leading, 102)
                .padding(.bottom, 4)
            }
        }
        .padding(.vertical, 12)
    }

    private func generateAIExplanation() {
        isGenerating = true
        errorMessage = nil
        
        let lang = settings.language
        Task {
            do {
                let result = try await AIExplanationService.shared.explainStartupService(
                    serviceName: service.name,
                    filePath: service.path,
                    category: service.category.displayName,
                    isEnabled: service.isEnabled,
                    language: lang
                )
                
                await MainActor.run {
                    self.aiExplanation = result
                    self.isGenerating = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isGenerating = false
                }
            }
        }
    }
}

struct CategoryBadge: View {
    let category: ServiceCategory

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: category.icon)
                .font(.system(size: 10, weight: .bold))
            Text(category.displayName)
                .font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(category.color.opacity(0.12)))
        .foregroundColor(category.color)
        .help(categoryHelpText)
        .frame(minWidth: 90)
    }

    private var categoryHelpText: String {
        switch category {
        case .user: return "startup_help_user".localized
        case .thirdParty: return "startup_help_third_party".localized
        case .system: return "startup_help_system".localized
        }
    }
}

struct StatusBadge: View {
    let isEnabled: Bool

    var body: some View {
        Text(isEnabled ? "startup_status_loaded".localized : "startup_status_unloaded".localized)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(isEnabled ? Color.green.opacity(0.15) : Color.secondary.opacity(0.15))
            )
            .foregroundColor(isEnabled ? .green : .secondary)
    }
}

#Preview {
    StartupServicesView(settings: AppSettings())
}
