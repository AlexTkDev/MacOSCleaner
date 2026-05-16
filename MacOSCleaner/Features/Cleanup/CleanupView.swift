import SwiftUI

public struct CleanupView: View {
    @State private var viewModel: CleanupViewModel
    @Environment(\.colorScheme) private var colorScheme
    
    public init(viewModel: CleanupViewModel) {
        _viewModel = State(initialValue: viewModel)
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            footer
        }
        .background(
            ZStack {
                Color(NSColor.windowBackgroundColor)
                if viewModel.state == .scanning || viewModel.state == .executing {
                    LinearGradient(
                        colors: [.accentColor.opacity(0.05), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
        )
    }
    
    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle:
            statusView(
                icon: "sparkles",
                title: "Ready to Clean",
                subtitle: "Scan your system to find safe-to-remove caches and temporary files.",
                buttonTitle: "Start Scan",
                action: { viewModel.startScan() }
            )
        case .scanning:
            progressView(title: "Scanning System...", subtitle: viewModel.stepTitle)
        case .preview:
            previewListView
        case .executing:
            progressView(title: "Cleaning Up...", subtitle: viewModel.stepTitle)
        case .completed:
            statusView(
                icon: "checkmark.seal.fill",
                iconColor: .green,
                title: "Cleanup Complete",
                subtitle: "Successfully freed \(viewModel.totalFreedMB) MB of disk space.",
                buttonTitle: "Done",
                action: { viewModel.reset() }
            )
        case .failed:
            statusView(
                icon: "exclamationmark.triangle.fill",
                iconColor: .red,
                title: "Cleanup Failed",
                subtitle: "An error occurred during the cleanup process.",
                buttonTitle: "Try Again",
                action: { viewModel.reset() }
            )
        case .cancelled:
            statusView(
                icon: "xmark.circle.fill",
                iconColor: .secondary,
                title: "Cancelled",
                subtitle: "The operation was cancelled by user.",
                buttonTitle: "Back",
                action: { viewModel.reset() }
            )
        }
    }
    
    private func statusView(
        icon: String,
        iconColor: Color = .accentColor,
        title: String,
        subtitle: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 72, weight: .thin))
                .foregroundStyle(
                    LinearGradient(
                        colors: [iconColor, iconColor.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: iconColor.opacity(0.3), radius: 10, x: 0, y: 5)
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.title)
                    .fontWeight(.bold)
                
                Text(subtitle)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            
            Button(action: action) {
                Text(buttonTitle)
                    .fontWeight(.semibold)
                    .frame(width: 150, height: 32)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
    
    private func progressView(title: String, subtitle: String) -> some View {
        VStack(spacing: 24) {
            ProgressView()
                .controlSize(.large)
            
            VStack(spacing: 12) {
                Text(title)
                    .font(.headline)
                
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 8)
                        
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.accentColor, .accentColor.opacity(0.6)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * CGFloat(viewModel.currentStep) / CGFloat(max(1, viewModel.totalSteps)), height: 8)
                            .animation(.spring(), value: viewModel.currentStep)
                    }
                }
                .frame(width: 300, height: 8)
            }
        }
    }
    
    private var previewListView: some View {
        List {
            Section(header: Text("Recommended for removal")) {
                ForEach(viewModel.items) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.label)
                                .font(.headline)
                            riskBadge(for: item.risk)
                        }
                        
                        Spacer()
                        
                        Text("\(item.sizeMB) MB")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.inset)
    }
    
    private func riskBadge(for risk: OperationRisk) -> some View {
        Text(risk.rawValue.uppercased())
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(riskColor(for: risk).opacity(0.15))
            .foregroundColor(riskColor(for: risk))
            .cornerRadius(4)
    }
    
    private func riskColor(for risk: OperationRisk) -> Color {
        switch risk {
        case .safe: return .green
        case .moderate: return .orange
        case .dangerous: return .red
        case .protected: return .secondary
        }
    }
    
    private var footer: some View {
        HStack {
            if viewModel.state == .preview {
                Text("Total size: \(viewModel.items.reduce(0) { $0 + $1.sizeMB }) MB")
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if viewModel.state == .preview {
                Button("Reset") {
                    viewModel.reset()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Clean Now") {
                    viewModel.executeCleanup()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .background(VisualEffectView(material: .titlebar, blendingMode: .withinWindow))
    }
}

// Помощник для эффекта размытия (Glassmorphism)
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
