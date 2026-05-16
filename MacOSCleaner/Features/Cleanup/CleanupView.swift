import SwiftUI

struct CleanupView: View {
    var body: some View {
        VStack {
            Image(systemName: "sparkles")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
                .padding(.bottom, 8)
            Text("Cleanup")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Reclaim space by cleaning cache and logs.")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    CleanupView()
}
