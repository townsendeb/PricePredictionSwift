import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppDataStore

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "internaldrive.fill")
                        .font(.title2)
                        .foregroundStyle(Color(red: 0.2, green: 0.6, blue: 0.9))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Local storage")
                            .font(.headline)
                        Text("Predictions and learnings are stored on this device. Pull to refresh on Overview to update.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(AppDataStore.preview)
    }
}
