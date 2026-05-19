import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
            
            VStack(spacing: 4) {
                Text("MacOS Cleaner")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Version 0.0.2")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 12) {
                Text("Developed by AlexTkDev")
                    .font(.headline)
                
                Link(destination: URL(string: "https://github.com/AlexTkDev/MacOSCleaner/issues")!) {
                    HStack {
                        Image(systemName: "link.circle.fill")
                        Text("If you have a problem with the app, let me know here")
                    }
                }
                
                Link(destination: URL(string: "https://www.linkedin.com/in/aleksandrtk/")!) {
                    HStack {
                        Image(systemName: "person.crop.circle.fill")
                        Text("LinkedIn Profile")
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            Text("© 2026 AlexTkDev. All rights reserved.")
                .font(.footnote)
                .foregroundColor(.secondary)
            
            Button("Close") {
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
