import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var store: AppDataStore
    @State private var isRefreshing = false

    var body: some View {
        List {
            if let msg = store.errorMessage {
                Section {
                    Text(msg)
                        .foregroundStyle(.red)
                }
            }
            if let w = store.latestWeatherToday {
                Section("LA weather — today's high") {
                    weatherSectionContent(w)
                }
            }
            if let w = store.latestWeatherTomorrow {
                Section("LA weather — tomorrow's high") {
                    weatherSectionContent(w)
                }
            }
            if let b10 = store.latestBitcoin10am {
                Section("Bitcoin — 10am EST") {
                    cryptoSectionContent(b10)
                }
            }
            if let b5 = store.latestBitcoin5pm {
                Section("Bitcoin — 5pm EST") {
                    cryptoSectionContent(b5)
                }
            }
            if let e10 = store.latestEthereum10am {
                Section("Ethereum — 10am EST") {
                    cryptoSectionContent(e10)
                }
            }
            if let e5 = store.latestEthereum5pm {
                Section("Ethereum — 5pm EST") {
                    cryptoSectionContent(e5)
                }
            }
            if let s10 = store.latestSolana10am {
                Section("Solana — 10am EST") {
                    cryptoSectionContent(s10)
                }
            }
            if let s5 = store.latestSolana5pm {
                Section("Solana — 5pm EST") {
                    cryptoSectionContent(s5)
                }
            }
            if store.latestWeatherToday == nil && store.latestWeatherTomorrow == nil && store.latestBitcoin10am == nil && store.latestBitcoin5pm == nil && store.latestEthereum10am == nil && store.latestEthereum5pm == nil && store.latestSolana10am == nil && store.latestSolana5pm == nil && !store.isLoading {
                Section {
                    Text("No predictions yet. Pull to refresh to load predictions.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Overview")
        .refreshable {
            isRefreshing = true
            await store.refreshAll()
            isRefreshing = false
        }
        .overlay {
            if store.isLoading && !isRefreshing {
                ProgressView()
            }
        }
    }

    private func weatherSectionContent(_ p: Prediction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(p.predictedValue, specifier: "%.0f") °F")
                .font(.title2.bold())
            if let updated = p.lastUpdated {
                Text("Updated \(updated)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let explanation = p.explanation, !explanation.isEmpty {
                Text(explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func cryptoSectionContent(_ p: Prediction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("$\(p.predictedValue, specifier: "%.2f")")
                .font(.title2.bold())
            if let updated = p.lastUpdated {
                Text("Updated \(updated)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let explanation = p.explanation, !explanation.isEmpty {
                Text(explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        OverviewView()
            .environmentObject(AppDataStore.preview)
    }
}
