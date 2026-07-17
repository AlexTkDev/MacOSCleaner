import SwiftUI

public struct ProcessesView: View {
    let settings: AppSettings
    @State private var viewModel = ProcessesViewModel()
    @State private var isEditMode = false

    public init(settings: AppSettings) {
        self.settings = settings
    }

    public var body: some View {
        GlassEffectContainer {
            VStack(spacing: 0) {
                header

                HStack(spacing: 12) {
                    searchField
                    Spacer()
                    Text("\(viewModel.filteredProcesses.count)/\(viewModel.processes.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                if isEditMode {
                    selectionToolbar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if viewModel.isLoading {
                    AnimatedScanView(
                        title: "processes_scanning".localized,
                        subtitle: "",
                        currentStep: 0,
                        totalSteps: 1
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.lastError {
                    errorView(error)
                } else if viewModel.filteredProcesses.isEmpty && !viewModel.searchText.isEmpty {
                    emptySearchView
                } else if viewModel.processes.isEmpty {
                    emptyView
                } else {
                    if viewModel.viewMode == .grouped {
                        groupedProcessList
                    } else {
                        flatProcessList
                    }
                }
            }
        }
        .sheet(isPresented: $viewModel.showBlacklistAlert) {
            blacklistSheet
        }
        .sheet(isPresented: $viewModel.showWhitelistAlert) {
            whitelistSheet
        }
        .onAppear {
            Task { await viewModel.scan() }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("processes_title".localized)
                    .font(.title2)
                    .fontWeight(.bold)
                Text("processes_subtitle".localized)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()

            if !viewModel.memoryHogs.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "memorychip")
                        .font(.system(size: 12))
                    Text(viewModel.totalMemoryFormatted)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.red.opacity(0.1)))
                .foregroundColor(.red)
            }

            Menu {
                Picker("view_mode".localized, selection: $viewModel.viewMode) {
                    ForEach(ProcessesViewModel.ViewMode.allCases) { mode in
                        Text(mode.localizedName).tag(mode)
                    }
                }
                Divider()
                Picker("sort_by".localized, selection: $viewModel.sortOption) {
                    ForEach(ProcessSortOption.allCases) { option in
                        Text(option.localizedName).tag(option)
                    }
                }
                Divider()
                Button(action: {
                    isEditMode.toggle()
                    if !isEditMode {
                        viewModel.deselectAll()
                    }
                }) {
                    Label(
                        isEditMode ? "cancel_selection".localized : "select_multiple".localized,
                        systemImage: isEditMode ? "xmark.circle" : "checkmark.circle"
                    )
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14, weight: .semibold))
            }
            .glassButtonStyle()

            Button(action: { viewModel.showBlacklistAlert = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 14, weight: .semibold))
                    if !viewModel.blacklist.isEmpty {
                        Text("\(viewModel.blacklist.count)")
                            .font(.system(size: 10, weight: .bold))
                    }
                }
            }
            .glassButtonStyle()
            .help("processes_tooltip_blacklist".localized)

            Button(action: { viewModel.showWhitelistAlert = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "lock.circle")
                        .font(.system(size: 14, weight: .semibold))
                    if !viewModel.whitelist.isEmpty {
                        Text("\(viewModel.whitelist.count)")
                            .font(.system(size: 10, weight: .bold))
                    }
                }
            }
            .glassButtonStyle()
            .help("processes_tooltip_whitelist".localized)

            Button(action: { Task { await viewModel.scan() } }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
            }
            .glassButtonStyle()
            .help("processes_tooltip_refresh".localized)
        }
        .padding()
    }

    private var selectionToolbar: some View {
        HStack(spacing: 12) {
            Button(action: viewModel.selectAll) {
                Label("select_all".localized, systemImage: "checkmark.circle")
            }
            .glassButtonStyle()

            Button(action: viewModel.deselectAll) {
                Label("deselect_all".localized, systemImage: "circle")
            }
            .glassButtonStyle()

            Spacer()

            Text(String(format: "processes_selected_count".localized, viewModel.selection.count))
                .font(.caption)
                .foregroundColor(.secondary)

            Button(action: { Task { await viewModel.terminateSelected() } }) {
                Label("terminate_selected".localized, systemImage: "xmark.circle")
            }
            .glassButtonStyle()
            .disabled(viewModel.selection.isEmpty)

            Button(role: .destructive, action: { Task { await viewModel.forceKillSelected() } }) {
                Label("force_kill_selected".localized, systemImage: "exclamationmark.triangle")
            }
            .glassButtonStyle()
            .disabled(viewModel.selection.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 12))
            TextField("processes_search".localized, text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassCapsule()
    }

    private var groupedProcessList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.processGroups) { group in
                    processGroupRow(group)
                    Divider()
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .glassCard()
            .padding()
        }
    }

    private var flatProcessList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.filteredProcesses) { process in
                    processRow(process)
                    Divider()
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .glassCard()
            .padding()
        }
    }

    private func processGroupRow(_ group: ProcessGroup) -> some View {
        DisclosureGroup {
            ForEach(group.processes) { process in
                processRow(process)
                    .padding(.leading, 20)
            }
        } label: {
            HStack(spacing: 12) {
                if let icon = group.processes.first(where: { $0.bundleID != nil }) {
                    AppIconView(path: icon.path)
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                        .frame(width: 24)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(group.displayName)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)

                    HStack(spacing: 8) {
                        Text(String(format: "processes_process_count".localized, group.processCount))
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 2) {
                            Image(systemName: "cpu")
                                .font(.system(size: 10))
                            Text(group.totalCPUFormatted)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                        }
                        .foregroundColor(group.totalCPU > 50 ? .red : .secondary)

                        HStack(spacing: 2) {
                            Image(systemName: "memorychip")
                                .font(.system(size: 10))
                            Text(group.totalMemoryFormatted)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                        }
                        .foregroundColor(group.totalMemory > 1_000_000_000 ? .red : .secondary)
                    }
                }

                Spacer()

                Menu {
                    Button(action: { Task { await viewModel.terminateGroup(group) } }) {
                        Label("processes_terminate_all".localized, systemImage: "xmark.circle")
                    }
                    Button(role: .destructive, action: { Task { await viewModel.forceKillGroup(group) } }) {
                        Label("processes_force_kill_all".localized, systemImage: "exclamationmark.triangle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 30)
            }
            .padding(.vertical, 8)
        }
    }

    private func processRow(_ process: RunningProcess) -> some View {
        ProcessRow(
            process: process,
            permission: viewModel.checkPermission(process),
            isSelected: viewModel.selection.contains(process.pid),
            settings: settings,
            onTerminate: {
                GlassOverlayManager.shared.showAlert(
                    title: "processes_confirm_terminate".localized,
                    message: String(format: "processes_confirm_terminate_message".localized, process.name, process.pid),
                    type: .warning,
                    primaryButtonTitle: "processes_terminate".localized,
                    primaryAction: {
                        Task { await viewModel.terminate(process) }
                    }
                )
            },
            onForceKill: {
                GlassOverlayManager.shared.showAlert(
                    title: "processes_confirm_force".localized,
                    message: String(format: "processes_confirm_force_message".localized, process.name, process.pid),
                    type: .critical,
                    primaryButtonTitle: "processes_force_kill".localized,
                    primaryAction: {
                        Task { await viewModel.forceKill(process) }
                    }
                )
            },
            onToggleSelection: { viewModel.toggleSelection(process) }
        )
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "cpu")
                .font(.system(size: 64, weight: .thin))
                .foregroundColor(.secondary.opacity(0.5))
            VStack(spacing: 8) {
                Text("processes_no_processes".localized)
                    .font(.headline)
                Text("processes_no_processes_sub".localized)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptySearchView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 64, weight: .thin))
                .foregroundColor(.secondary.opacity(0.5))
            Text("processes_no_results".localized)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 64, weight: .thin))
                .foregroundColor(.orange)
            VStack(spacing: 8) {
                Text("processes_scan_failed".localized)
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

    private var blacklistSheet: some View {
        VStack(spacing: 16) {
            Text("processes_blacklist_title".localized)
                .font(.headline)

            Text("processes_tooltip_blacklist".localized)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                TextField("processes_blacklist_placeholder".localized, text: $viewModel.newBlacklistEntry)
                    .textFieldStyle(.roundedBorder)
                Button("add".localized) {
                    Task { await viewModel.addToBlacklist() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.newBlacklistEntry.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            List {
                ForEach(viewModel.blacklist, id: \.self) { name in
                    HStack {
                        Text(name)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Button(action: { Task { await viewModel.removeFromBlacklist(name) } }) {
                            Image(systemName: "minus.circle")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button("done".localized) {
                viewModel.showBlacklistAlert = false
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(width: 420, height: 380)
    }

    private var whitelistSheet: some View {
        VStack(spacing: 16) {
            Text("processes_whitelist_title".localized)
                .font(.headline)

            Text("processes_tooltip_whitelist".localized)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                TextField("processes_whitelist_placeholder".localized, text: $viewModel.newWhitelistEntry)
                    .textFieldStyle(.roundedBorder)
                Button("add".localized) {
                    Task { await viewModel.addToWhitelist() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.newWhitelistEntry.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            List {
                ForEach(viewModel.whitelist, id: \.self) { name in
                    HStack {
                        Text(name)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Button(action: { Task { await viewModel.removeFromWhitelist(name) } }) {
                            Image(systemName: "minus.circle")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button("done".localized) {
                viewModel.showWhitelistAlert = false
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(width: 420, height: 380)
    }
}

private struct AppIconView: View {
    let path: String?
    @State private var icon: NSImage?

    var body: some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 20, height: 20)
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: 18))
                .foregroundColor(.secondary)
                .frame(width: 24)
                .task { await loadIcon() }
        }
    }

    private func loadIcon() async {
        guard let path else { return }
        icon = NSWorkspace.shared.icon(forFile: path)
    }
}

#Preview {
    ProcessesView(settings: AppSettings())
}
