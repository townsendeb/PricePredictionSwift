import Foundation
import SwiftUI

@MainActor
final class AppDataStore: ObservableObject {
    static let shared = AppDataStore()

    @Published var predictions: [Prediction] = []
    @Published var learnings: [Learning] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let store = LocalStore()
    private let fetcher = DataFetcher()
    private var predictor: PredictorService { PredictorService(store: store) }

    init() {
        loadFromLocalStore()
    }

    private var todayISO: String { Calendar.la.dateISOString(for: Date()) }
    private var tomorrowISO: String { Calendar.la.tomorrowISOString() }

    var latestWeatherToday: Prediction? { store.getWeatherPredictionForTargetDate(todayISO) }
    var latestWeatherTomorrow: Prediction? { store.getWeatherPredictionForTargetDate(tomorrowISO) }

    func latestCrypto(type: PredictionType, slot: TargetSlot) -> Prediction? {
        predictions.first { $0.type == type.rawValue && $0.targetSlot == slot.rawValue }
    }

    var latestBitcoin10am: Prediction? { latestCrypto(type: .bitcoin, slot: .am10) }
    var latestBitcoin5pm: Prediction? { latestCrypto(type: .bitcoin, slot: .pm5) }
    var latestEthereum10am: Prediction? { latestCrypto(type: .ethereum, slot: .am10) }
    var latestEthereum5pm: Prediction? { latestCrypto(type: .ethereum, slot: .pm5) }
    var latestSolana10am: Prediction? { latestCrypto(type: .solana, slot: .am10) }
    var latestSolana5pm: Prediction? { latestCrypto(type: .solana, slot: .pm5) }

    /// Load predictions and learnings from SQLite (no network).
    func loadFromLocalStore() {
        predictions = store.getPredictions(orderByCreatedAtDescLimit: 50)
        learnings = store.getLearnings(limit: 100)
    }

    /// Manual refresh: fetch APIs, predict, verify/retrain, then reload from store.
    func refreshAll() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let weatherTask = fetcher.fetchWeather()
            async let cryptoTask = fetcher.fetchCrypto()
            let (weatherResult, cryptoResult) = try await (weatherTask, cryptoTask)

            let pred = predictor
            pred.predictWeather(weatherResult: weatherResult)
            for cryptoType in PredictionType.cryptoTypes {
                let price: Double? = switch cryptoType {
                case .bitcoin: cryptoResult.bitcoin
                case .ethereum: cryptoResult.ethereum
                case .solana: cryptoResult.solana
                case .weather: nil
                }
                pred.predictCrypto(type: cryptoType.rawValue, currentPrice: price)
            }
            pred.verifyAndRetrain(weatherResult: weatherResult, cryptoResult: cryptoResult)

            loadFromLocalStore()
        } catch {
            errorMessage = error.localizedDescription
            loadFromLocalStore()
        }
    }

    // MARK: - Previews

    static var preview: AppDataStore {
        let s = AppDataStore()
        s.predictions = Prediction.previewList
        s.learnings = Learning.previewList
        return s
    }
}
