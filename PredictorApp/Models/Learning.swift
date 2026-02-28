import Foundation

struct Learning: Identifiable, Decodable {
    var id: String
    var modelType: String
    var learnedAt: String?
    var tidbit: String
    var predictionId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case modelType = "model_type"
        case learnedAt = "learned_at"
        case tidbit
        case predictionId = "prediction_id"
    }

    var modelLabel: String {
        if modelType == PredictionType.weather.rawValue { return "Weather" }
        return PredictionType(rawValue: modelType)?.displayLabel ?? modelType
    }

    var learnedAtFormatted: String? {
        learnedAt.flatMap { DateFormatting.relativeString(fromISO: $0) }
    }

    // MARK: - Previews
    static let previewWeather = Learning(
        id: "preview-l1",
        modelType: PredictionType.weather.rawValue,
        learnedAt: ISO8601DateFormatter().string(from: Date()),
        tidbit: "Higher humidity often correlates with a 1–2 °F drop vs. dry days.",
        predictionId: nil
    )
    static let previewBitcoin = Learning(
        id: "preview-l2",
        modelType: PredictionType.bitcoin.rawValue,
        learnedAt: ISO8601DateFormatter().string(from: Date()),
        tidbit: "After a >2% hourly move, the next hour tends to mean-revert.",
        predictionId: nil
    )
    static let previewEthereum = Learning(
        id: "preview-l3",
        modelType: PredictionType.ethereum.rawValue,
        learnedAt: ISO8601DateFormatter().string(from: Date()),
        tidbit: "ETH often tracks BTC with a short lag.",
        predictionId: nil
    )
    static let previewSolana = Learning(
        id: "preview-l4",
        modelType: PredictionType.solana.rawValue,
        learnedAt: ISO8601DateFormatter().string(from: Date()),
        tidbit: "SOL volatility tends to be higher than BTC in the same window.",
        predictionId: nil
    )
    static var previewList: [Learning] { [previewWeather, previewBitcoin, previewEthereum, previewSolana] }
}
