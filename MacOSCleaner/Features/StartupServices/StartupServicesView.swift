import SwiftUI

struct StartupServicesView: View {
    var body: some View {
        VStack {
            Image(systemName: "bolt.horizontal")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
                .padding(.bottom, 8)
            Text("Startup Services")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Manage apps that launch on startup.")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    StartupServicesView()
}
