import SwiftUI

public struct ProcessesView: View {
    @State private var viewModel: ProcessesViewModel

    public init(viewModel: ProcessesViewModel = ProcessesViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
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

            Divider()

            if viewModel.isLoading {
                ProgressView("processes_scanning".localized)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.lastError {
                errorView(error)
            } else if viewModel.filteredProcesses.isEmpty && !viewModel.searchText.isEmpty {
                emptySearchView
            } else if viewModel.processes.isEmpty {
                emptyView
            } else {
                processList
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .alert(
            "processes_confirm_terminate".localized,
            isPresented: Binding(
                get: { viewModel.confirmKill != nil },
                set: { if !$0 { viewModel.confirmKill = nil } }
            )
        ) {
            Button("cancel".localized, role: .cancel) { viewModel.confirmKill = nil }
            Button("processes_terminate".localized, role: .destructive) {
                if let proc = viewModel.confirmKill {
                    Task { await viewModel.terminate(proc) }
                }
            }
        } message: {
            if let proc = viewModel.confirmKill {
                Text(String(
                    format: "processes_confirm_terminate_message".localized,
                    proc.name,
                    proc.pid
                ))
            }
        }
        .alert(
            "processes_confirm_force".localized,
            isPresented: Binding(
                get: { viewModel.confirmForceKill != nil },
                set: { if !$0 { viewModel.confirmForceKill = nil } }
            )
        ) {
            Button("cancel".localized, role: .cancel) { viewModel.confirmForceKill = nil }
            Button("processes_force_kill".localized, role: .destructive) {
                if let proc = viewModel.confirmForceKill {
                    Task { await viewModel.forceKill(proc) }
                }
            }
        } message: {
            if let proc = viewModel.confirmForceKill {
                Text(String(
                    format: "processes_confirm_force_message".localized,
                    proc.name,
                    proc.pid
                ))
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

            Button(action: {
                viewModel.showBlacklistAlert = true
            }) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .help("processes_manage_blacklist".localized)

            Button(action: {
                viewModel.showWhitelistAlert = true
            }) {
                Image(systemName: "lock.circle")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .help("processes_manage_whitelist".localized)

            Button(action: {
                Task { await viewModel.scan() }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .help("processes_refresh".localized)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("processes_search".localized, text: $viewModel.searchText)
                .textFieldStyle(.plain)
        }
        .padding(6)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(6)
    }

    private var processList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.filteredProcesses) { process in
                    ProcessRow(
                        process: process,
                        permission: viewModel.checkPermission(process),
                        onTerminate: { viewModel.confirmKill = process },
                        onForceKill: { viewModel.confirmForceKill = process }
                    )
                    Divider()
                }
            }
            .padding(.horizontal)
        }
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

            HStack {
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
                        Button(action: {
                            Task { await viewModel.removeFromBlacklist(name) }
                        }) {
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
        .frame(width: 400, height: 350)
    }

    private var whitelistSheet: some View {
        VStack(spacing: 16) {
            Text("processes_whitelist_title".localized)
                .font(.headline)

            HStack {
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
                        Button(action: {
                            Task { await viewModel.removeFromWhitelist(name) }
                        }) {
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
        .frame(width: 400, height: 350)
    }
}

#Preview {
    ProcessesView()
}
