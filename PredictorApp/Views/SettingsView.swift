import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppDataStore

    var body: some View {
        List {
            Section {
                Text("Predictions and learnings are stored locally on this device. Pull to refresh on Overview to update.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(AppDataStore.preview)
    }
}
