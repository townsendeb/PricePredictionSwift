import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var store: AppDataStore
    @State private var filterType: String = "all"

    private static let filterAll = "all"

    var filteredPredictions: [Prediction] {
        let withActuals = store.predictions.filter { $0.actualValue != nil }
        guard filterType != Self.filterAll, let type = PredictionType(rawValue: filterType) else { return withActuals }
        return withActuals.filter { $0.type == type.rawValue }
    }

    var body: some View {
        List {
            Picker("Type", selection: $filterType) {
                Text("All").tag(Self.filterAll)
                Text("Weather").tag(PredictionType.weather.rawValue)
                Text("BTC").tag(PredictionType.bitcoin.rawValue)
                Text("ETH").tag(PredictionType.ethereum.rawValue)
                Text("SOL").tag(PredictionType.solana.rawValue)
            }
            .pickerStyle(.menu)

            ForEach(filteredPredictions) { p in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text([p.typeLabel, p.targetSlotLabel].compactMap { $0 }.joined(separator: " — "))
                            .font(.subheadline.bold())
                        Spacer()
                        if let passed = p.passed {
                            Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(passed ? .green : .red)
                        }
                    }
                    Text("Predicted: \(p.predictedValue, specifier: p.isCrypto ? "%.2f" : "%.0f")\(p.isCrypto ? " USD" : " °F")")
                        .font(.caption)
                    if let actual = p.actualValue {
                        Text("Actual: \(actual, specifier: p.isCrypto ? "%.2f" : "%.0f")\(p.isCrypto ? " USD" : " °F")")
                            .font(.caption)
                    }
                    if let direction = p.predictionDirectionLabel {
                        Text(direction)
                            .font(.caption)
                            .foregroundStyle(direction == "Prediction was low" ? .orange : direction == "Prediction was high" ? .blue : .secondary)
                    }
                    if let err = p.errorMagnitude {
                        Text("Error: \(err, specifier: "%.2f")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let created = p.lastUpdated {
                        Text(created)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("History")
        .onAppear {
            store.loadFromLocalStore()
        }
    }
}

#Preview {
    NavigationStack {
        HistoryView()
            .environmentObject(AppDataStore.preview)
    }
}
