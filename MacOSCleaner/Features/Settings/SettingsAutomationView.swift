import SwiftUI
import FoundationModels

struct SettingsAutomationView: View {
    @Bindable var settings: AppSettings
    @State private var editingCommand: CustomSiriCommand? = nil
    @State private var isAddCommandSheetPresented: Bool = false
    @State private var modelAvailability: SystemLanguageModel.Availability = SystemLanguageModel.default.availability
    @State private var isCheckingAvailability: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                aiToggleCard
                automationTogglesCard
                if settings.enableSiri || settings.enableShortcutsAndAutomator {
                    siriCommandsCard
                }
                aiFeaturesCard
            }
            .padding(20)
        }
        .task {
            refreshModelAvailability(prewarmIfReady: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshModelAvailability(prewarmIfReady: false)
        }
        .sheet(isPresented: $isAddCommandSheetPresented) {
            CustomSiriCommandEditSheet { newCmd in
                settings.customSiriCommands.append(newCmd)
            }
        }
        .sheet(item: $editingCommand) { cmd in
            CustomSiriCommandEditSheet(commandToEdit: cmd) { updatedCmd in
                if let idx = settings.customSiriCommands.firstIndex(where: { $0.id == updatedCmd.id }) {
                    settings.customSiriCommands[idx] = updatedCmd
                }
            }
        }
    }

    private var automationTogglesCard: some View {
        GlassCard(
            header: {
                SettingsSectionHeader("settings_automation_title".localized, subtitle: "settings_automation_sub".localized, iconName: "waveform", iconColor: .purple)
            },
            content: {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsToggleRow(
                        "settings_siri_toggle_title".localized,
                        subtitle: "settings_enable_siri_sub".localized,
                        isOn: $settings.enableSiri
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        "settings_automator_toggle_title".localized,
                        subtitle: "settings_enable_shortcuts_sub".localized,
                        isOn: $settings.enableShortcutsAndAutomator
                    )

                    if settings.enableSiri || settings.enableShortcutsAndAutomator {
                        SettingsDivider()
                        SettingsLabeledControl(
                            "settings_open_shortcuts_title".localized,
                            subtitle: "settings_open_shortcuts_sub".localized
                        ) {
                            Button("settings_launch_shortcuts_button".localized) {
                                if let url = URL(string: "shortcuts://") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
        )
    }

    private var siriCommandsCard: some View {
        GlassCard(
            header: {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top) {
                        SettingsSectionHeader("settings_custom_siri_commands".localized, subtitle: "settings_custom_siri_commands_sub".localized, iconName: "mic.fill", iconColor: .pink)
                        Spacer(minLength: 8)
                        Button("siri_add_command_button".localized) {
                            isAddCommandSheetPresented = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .fixedSize()
                        .layoutPriority(1)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        SettingsSectionHeader("settings_custom_siri_commands".localized, subtitle: "settings_custom_siri_commands_sub".localized, iconName: "mic.fill", iconColor: .pink)
                        Button("siri_add_command_button".localized) {
                            isAddCommandSheetPresented = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            },
            content: {
                VStack(spacing: 8) {
                    if settings.customSiriCommands.isEmpty {
                        Text("settings_no_custom_commands".localized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(settings.customSiriCommands) { cmd in
                            HStack(spacing: 12) {
                                Toggle("", isOn: Binding(
                                    get: { cmd.isEnabled },
                                    set: { newValue in
                                        if let idx = settings.customSiriCommands.firstIndex(where: { $0.id == cmd.id }) {
                                            settings.customSiriCommands[idx].isEnabled = newValue
                                        }
                                    }
                                ))
                                .labelsHidden()

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(cmd.displayTitle)
                                        .font(.body.weight(.medium))
                                    Text("«\(cmd.displayPhrase)»")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button {
                                    editingCommand = cmd
                                } label: {
                                    Image(systemName: "pencil")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    settings.customSiriCommands.removeAll(where: { $0.id == cmd.id })
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            SettingsDivider()
                        }
                    }
                }
            }
        )
    }

    private var isCurrentLocaleSupportedByAI: Bool {
        SystemLanguageModel.default.supportsLocale(Locale.current) ||
        SystemLanguageModel.default.supportsLocale(LanguageManager.shared.currentLocale)
    }

    private var aiToggleCard: some View {
        GlassCard(
            header: {
                SettingsSectionHeader("settings_ai_title".localized, subtitle: "settings_ai_sub".localized, iconName: "sparkles", iconColor: .pink)
            },
            content: {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsToggleRow(
                        "settings_enable_ai".localized,
                        subtitle: "settings_enable_ai_sub".localized,
                        isOn: $settings.enableAI
                    )

                    SettingsDivider()

                    SettingsLabeledControl(
                        "settings_ai_readiness".localized,
                        subtitle: "settings_ai_readiness_sub".localized
                    ) {
                        aiStatusLabel
                    }

                    if settings.enableAI, let hint = aiStatusHint {
                        aiHintView(hint: hint, showSystemSettingsButton: shouldShowSystemSettingsButton)
                    }
                }
            }
        )
    }

    @ViewBuilder
    private var aiStatusLabel: some View {
        if !settings.enableAI {
            StatusPill("settings_ai_status_disabled".localized, iconName: "slash.circle", style: .neutral)
        } else {
            HStack(spacing: 8) {
                switch modelAvailability {
                case .available:
                    StatusPill("settings_ai_status_ready".localized, iconName: "checkmark.circle.fill", style: .success)
                case .unavailable(let reason):
                    switch reason {
                    case .deviceNotEligible:
                        StatusPill("settings_ai_status_unsupported_device".localized, iconName: "exclamationmark.triangle.fill", style: .warning)
                    case .appleIntelligenceNotEnabled:
                        StatusPill("settings_ai_status_not_enabled".localized, iconName: "exclamationmark.circle.fill", style: .warning)
                    case .modelNotReady:
                        if !isCurrentLocaleSupportedByAI {
                            StatusPill("settings_ai_status_unsupported_language".localized, iconName: "globe.badge.chevron.backward", style: .warning)
                        } else {
                            StatusPill("settings_ai_status_preparing".localized, iconName: "clock.arrow.circlepath", style: .info)
                        }
                    @unknown default:
                        StatusPill("settings_ai_status_unavailable".localized, iconName: "xmark.circle.fill", style: .error)
                    }
                }

                Button {
                    refreshModelAvailability(prewarmIfReady: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isCheckingAvailability ? 360 : 0))
                        .animation(isCheckingAvailability ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: isCheckingAvailability)
                }
                .buttonStyle(.plain)
                .help("settings_ai_refresh_status".localized)
                .onHover { inside in
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
        }
    }

    private var aiStatusHint: String? {
        guard settings.enableAI else { return nil }
        switch modelAvailability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "settings_ai_hint_unsupported_device".localized
            case .appleIntelligenceNotEnabled:
                return "settings_ai_hint_not_enabled".localized
            case .modelNotReady:
                if !isCurrentLocaleSupportedByAI {
                    return "settings_ai_hint_unsupported_language".localized
                } else {
                    return "settings_ai_hint_preparing".localized
                }
            @unknown default:
                return nil
            }
        }
    }

    private var shouldShowSystemSettingsButton: Bool {
        guard settings.enableAI else { return false }
        switch modelAvailability {
        case .available:
            return false
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return false
            case .appleIntelligenceNotEnabled, .modelNotReady:
                return true
            @unknown default:
                return false
            }
        }
    }

    private func aiHintView(hint: String, showSystemSettingsButton: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(.top, 1)

                Text(hint)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showSystemSettingsButton {
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("settings_ai_open_system_settings".localized)
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 10))
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .padding(.leading, 21)
                .onHover { inside in
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
        )
        .padding(.top, 2)
    }

    private func refreshModelAvailability(prewarmIfReady: Bool) {
        isCheckingAvailability = true
        let currentStatus = SystemLanguageModel.default.availability
        modelAvailability = currentStatus
        if prewarmIfReady, case .unavailable(.modelNotReady) = currentStatus {
            let session = LanguageModelSession(model: SystemLanguageModel.default)
            session.prewarm()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            modelAvailability = SystemLanguageModel.default.availability
            isCheckingAvailability = false
        }
    }

    private var aiFeaturesCard: some View {
        GlassCard(
            header: {
                SettingsSectionHeader("settings_ai_capabilities".localized, subtitle: "settings_ai_capabilities_sub".localized, iconName: "star.square.on.square.fill", iconColor: .yellow)
            },
            content: {
                SettingsCardGrid(columnCount: 2) {
                    aiFeatureRow("settings_ai_feat_smart_cleanup".localized, "settings_ai_feat_smart_cleanup_sub".localized, icon: "wand.and.stars")
                    aiFeatureRow("settings_ai_feat_recs".localized, "settings_ai_feat_recs_sub".localized, icon: "lightbulb.fill")
                    aiFeatureRow("settings_ai_feat_duplicates".localized, "settings_ai_feat_duplicates_sub".localized, icon: "doc.on.doc.fill")
                    aiFeatureRow("settings_ai_feat_privacy".localized, "settings_ai_feat_privacy_sub".localized, icon: "lock.shield.fill")
                    aiFeatureRow("settings_ai_feat_voice".localized, "settings_ai_feat_voice_sub".localized, icon: "waveform")
                    aiFeatureRow("settings_ai_feat_shortcuts".localized, "settings_ai_feat_shortcuts_sub".localized, icon: "bolt.fill")
                }
            }
        )
    }

    private func aiFeatureRow(_ title: String, _ desc: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
        }
    }
}
