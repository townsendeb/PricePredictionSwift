import SwiftUI

struct LearningsView: View {
    @EnvironmentObject var store: AppDataStore
    @State private var filterModel: String = "all"

    private static let filterAll = "all"

    var filteredLearnings: [Learning] {
        guard filterModel != Self.filterAll, let type = PredictionType(rawValue: filterModel) else { return store.learnings }
        return store.learnings.filter { $0.modelType == type.rawValue }
    }

    var body: some View {
        List {
            Section {
                Picker("Model", selection: $filterModel) {
                    Text("All").tag(Self.filterAll)
                    Text("Weather").tag(PredictionType.weather.rawValue)
                    Text("BTC").tag(PredictionType.bitcoin.rawValue)
                    Text("ETH").tag(PredictionType.ethereum.rawValue)
                    Text("SOL").tag(PredictionType.solana.rawValue)
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.clear)

            ForEach(filteredLearnings) { learning in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lightbulb.fill")
                        .font(.title3)
                        .foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(learning.modelLabel)
                                .font(.subheadline.bold())
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let date = learning.learnedAtFormatted {
                                Text(date)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Text(learning.tidbit)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 8)
                .listRowBackground(Color(.secondarySystemGroupedBackground))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Learnings")
        .onAppear {
            store.loadFromLocalStore()
        }
    }
}

#Preview {
    NavigationStack {
        LearningsView()
            .environmentObject(AppDataStore.preview)
    }
}
