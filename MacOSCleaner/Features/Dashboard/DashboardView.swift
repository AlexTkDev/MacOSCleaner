import SwiftUI

struct DashboardView: View {
    var body: some View {
        VStack {
            Image(systemName: "gauge.medium")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
                .padding(.bottom, 8)
            Text("Dashboard")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Overview of your system health.")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    DashboardView()
}
