import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    var availableUpdate: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .frame(width: 400)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)

            VStack(spacing: 2) {
                Text("MacOS Cleaner")
                    .font(.title)
                    .fontWeight(.bold)
                Text(String(format: "about_version".localized, Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "version_unknown".localized))
                    .font(.subheadline)
                    .opacity(0.85)
            }
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background {
            LinearGradient(
                colors: [
                    .accentColor.opacity(colorScheme == .dark ? 0.8 : 0.65),
                    .accentColor.opacity(colorScheme == .dark ? 0.3 : 0.15),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var content: some View {
        VStack(spacing: 16) {
            if let update = availableUpdate {
                updateBanner(version: update)
            }

            developerCard
            linksCard

            Text("about_copyright".localized)
                .font(.footnote)
                .foregroundColor(.secondary)

            Button("close".localized) { dismiss() }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
        }
        .padding(20)
    }

    private func updateBanner(version: String) -> some View {
        Button {
            NSWorkspace.shared.open(UpdateChecker.releasesURL)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.multicolor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "update.available".localized, version))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("update.download".localized + " →")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(14)
            .background(
                LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .blue.opacity(0.3), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
    }

    private var developerCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.circle.fill")
                .font(.title2)
                .foregroundColor(.accentColor)
            Text("about_developer".localized)
                .font(.headline)
            Spacer()
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var linksCard: some View {
        VStack(spacing: 0) {
            Link(destination: URL(string: "https://alextkdev.github.io/MacOSCleaner/")!) {
                Label("about_website".localized, systemImage: "globe")
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .contentShape(Rectangle())
            }
            Divider().padding(.leading, 44)
            Link(destination: URL(string: "https://github.com/AlexTkDev/MacOSCleaner/issues")!) {
                Label("about_problem_link".localized, systemImage: "exclamationmark.bubble.fill")
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .contentShape(Rectangle())
            }
            Divider().padding(.leading, 44)
            Link(destination: URL(string: "https://www.linkedin.com/in/aleksandrtk/")!) {
                Label("about_linkedin".localized, systemImage: "person.crop.circle.badge.plus")
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .contentShape(Rectangle())
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .buttonStyle(.plain)
    }
}

#Preview {
    AboutView(availableUpdate: "2.0.0")
}
