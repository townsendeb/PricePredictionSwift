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
            Section {
                Picker("Filter", selection: $filterType) {
                    Text("All").tag(Self.filterAll)
                    Text("Weather").tag(PredictionType.weather.rawValue)
                    Text("BTC").tag(PredictionType.bitcoin.rawValue)
                    Text("ETH").tag(PredictionType.ethereum.rawValue)
                    Text("SOL").tag(PredictionType.solana.rawValue)
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            ForEach(filteredPredictions) { p in
                historyRow(p)
            }
            .listRowBackground(Color(.secondarySystemGroupedBackground))
        }
        .listStyle(.insetGrouped)
        .navigationTitle("History")
        .onAppear {
            store.loadFromLocalStore()
        }
    }

    private func historyRow(_ p: Prediction) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: iconForType(p.type))
                    .font(.title3)
                    .foregroundStyle(tintForType(p.type))
                Text([p.typeLabel, p.targetSlotLabel].compactMap { $0 }.joined(separator: " — "))
                    .font(.headline)
                Spacer()
                if let passed = p.passed {
                    Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(passed ? Color.green : Color.red)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                labelValue("Predicted", "\(p.predictedValue, default: p.isCrypto ? "%.2f" : "%.0f")\(p.isCrypto ? " USD" : "°F")")
                if p.actualValue != nil {
                    labelValue("Actual", "\(p.actualValue!, default: p.isCrypto ? "%.2f" : "%.0f")\(p.isCrypto ? " USD" : "°F")")
                }
            }
            .font(.subheadline)
            if let direction = p.predictionDirectionLabel {
                Text(direction)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(direction == "Prediction was low" ? .orange : direction == "Prediction was high" ? .blue : .secondary)
            }
            if let created = p.lastUpdated {
                Text(created)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }

    private func labelValue(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
        }
    }

    private func iconForType(_ type: String) -> String {
        switch type {
        case PredictionType.weather.rawValue: return "cloud.sun.fill"
        case PredictionType.bitcoin.rawValue: return "bitcoinsign.circle.fill"
        case PredictionType.ethereum.rawValue: return "e.circle.fill"
        case PredictionType.solana.rawValue: return "s.circle.fill"
        default: return "chart.bar.fill"
        }
    }

    private func tintForType(_ type: String) -> Color {
        switch type {
        case PredictionType.weather.rawValue: return Color(red: 0.25, green: 0.6, blue: 0.95)
        case PredictionType.bitcoin.rawValue, PredictionType.ethereum.rawValue, PredictionType.solana.rawValue: return Color(red: 0.9, green: 0.55, blue: 0.2)
        default: return .secondary
        }
    }
}

#Preview {
    NavigationStack {
        HistoryView()
            .environmentObject(AppDataStore.preview)
    }
}
