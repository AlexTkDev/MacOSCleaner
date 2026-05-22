import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
            
            VStack(spacing: 4) {
                Text("app_title".localized)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("about_version".localized)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 12) {
                Text("about_developer".localized)
                    .font(.headline)
                
                Link(destination: URL(string: "https://github.com/AlexTkDev/MacOSCleaner/issues")!) {
                    HStack {
                        Image(systemName: "link.circle.fill")
                        Text("about_problem_link".localized)
                    }
                }
                
                Link(destination: URL(string: "https://www.linkedin.com/in/aleksandrtk/")!) {
                    HStack {
                        Image(systemName: "person.crop.circle.fill")
                        Text("about_linkedin".localized)
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            Text("about_copyright".localized)
                .font(.footnote)
                .foregroundColor(.secondary)
            
            Button("close".localized) {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .padding(.top, 10)
        }
        .padding(30)
        .frame(width: 350)
        .fixedSize()
    }
}

#Preview {
    AboutView()
}
