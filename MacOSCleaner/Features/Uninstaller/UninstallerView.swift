import SwiftUI

struct UninstallerView: View {
    var body: some View {
        VStack {
            Image(systemName: "trash")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
                .padding(.bottom, 8)
            Text("Uninstaller")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Remove apps completely.")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    UninstallerView()
}
