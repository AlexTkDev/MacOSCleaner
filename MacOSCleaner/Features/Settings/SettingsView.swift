import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack {
            Image(systemName: "gear")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
                .padding(.bottom, 8)
            Text("Settings")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Configure app preferences.")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SettingsView()
}
