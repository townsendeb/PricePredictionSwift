import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AppDataStore
    var body: some View {
        NavigationStack {
            DashboardTabView()
        }
    }
}

struct DashboardTabView: View {
    @State private var selectedTab = 0
    var body: some View {
        TabView(selection: $selectedTab) {
            OverviewView()
                .tabItem { Label("Overview", systemImage: "gauge.high") }
                .tag(0)
            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(1)
            LearningsView()
                .tabItem { Label("Learnings", systemImage: "lightbulb") }
                .tag(2)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(3)
        }
    }
}

#Preview("ContentView") {
    ContentView()
        .environmentObject(AppDataStore.shared)
}

#Preview("Dashboard with data") {
    DashboardTabView()
        .environmentObject(AppDataStore.preview)
}
