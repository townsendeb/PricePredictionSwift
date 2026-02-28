import SwiftUI

@main
struct PredictorAppApp: App {
    @StateObject private var store = AppDataStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasRefreshedOnLaunch = false

    var body: some Scene {
        #if os(macOS)
        MenuBarExtra("Predictor", systemImage: "chart.line.uptrend.xyaxis") {
            Button("Open") {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        #endif
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active, !hasRefreshedOnLaunch {
                hasRefreshedOnLaunch = true
                Task { await store.refreshAll() }
            }
        }
    }
}
