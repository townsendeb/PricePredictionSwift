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
            Picker("Model", selection: $filterModel) {
                Text("All").tag(Self.filterAll)
                Text("Weather").tag(PredictionType.weather.rawValue)
                Text("BTC").tag(PredictionType.bitcoin.rawValue)
                Text("ETH").tag(PredictionType.ethereum.rawValue)
                Text("SOL").tag(PredictionType.solana.rawValue)
            }
            .pickerStyle(.menu)
            .listRowInsets(EdgeInsets())

            ForEach(filteredLearnings) { learning in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(learning.modelLabel)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let date = learning.learnedAtFormatted {
                            Text(date)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(learning.tidbit)
                        .font(.subheadline)
                }
                .padding(.vertical, 6)
            }
        }
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
