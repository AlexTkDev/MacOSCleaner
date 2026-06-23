import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

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
                Text("app_title".localized)
                    .font(.title)
                    .fontWeight(.bold)
                Text("about_version".localized)
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
            Link(destination: URL(string: "https://github.com/AlexTkDev/MacOSCleaner/issues")!) {
                Label("about_problem_link".localized, systemImage: "exclamationmark.bubble.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .contentShape(Rectangle())
            }
            Divider().padding(.leading, 44)
            Link(destination: URL(string: "https://www.linkedin.com/in/aleksandrtk/")!) {
                Label("about_linkedin".localized, systemImage: "person.crop.circle.badge.plus")
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
    AboutView()
}
