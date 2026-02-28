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
    private static let accent = Color(red: 0.2, green: 0.6, blue: 0.9)

    var body: some View {
        TabView(selection: $selectedTab) {
            OverviewView()
                .tabItem { Label("Overview", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(0)
            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(1)
            LearningsView()
                .tabItem { Label("Learnings", systemImage: "lightbulb.fill") }
                .tag(2)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(3)
        }
        .tint(Self.accent)
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
