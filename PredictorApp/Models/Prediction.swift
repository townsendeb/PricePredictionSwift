import Foundation

// MARK: - Prediction & Learning shared types

/// Canonical prediction types (weather + crypto). Use rawValue for storage/API.
enum PredictionType: String, CaseIterable {
    case weather
    case bitcoin
    case ethereum
    case solana

    static var cryptoTypes: [PredictionType] { [.bitcoin, .ethereum, .solana] }

    var displayLabel: String {
        switch self {
        case .weather: return "LA Weather"
        case .bitcoin: return "Bitcoin"
        case .ethereum: return "Ethereum"
        case .solana: return "Solana"
        }
    }
}

/// Crypto target slots (EST). Use rawValue for storage.
enum TargetSlot: String, CaseIterable {
    case am10 = "10am"
    case pm5 = "5pm"

    var displayLabel: String { rawValue + " EST" }
}

/// Shared date formatting for predictions and learnings.
enum DateFormatting {
    static func relativeString(fromISO iso: String) -> String? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: d, relativeTo: Date())
        }
        return nil
    }
}

// MARK: - Prediction (data model)

struct Prediction: Identifiable, Codable {
    var id: String
    var type: String
    var predictedAt: String?
    var targetTime: String?
    var predictedValue: Double
    var explanation: String?
    var actualValue: Double?
    var passed: Bool?
    var errorMagnitude: Double?
    var createdAt: String?
    var supersedesId: String?
    var revision: Int?
    /// For crypto: "10am" | "5pm" (EST); nil for weather.
    var targetSlot: String?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case predictedAt = "predicted_at"
        case targetTime = "target_time"
        case predictedValue = "predicted_value"
        case explanation
        case actualValue = "actual_value"
        case passed
        case errorMagnitude = "error_magnitude"
        case createdAt = "created_at"
        case supersedesId = "supersedes_id"
        case revision
        case targetSlot = "target_slot"
    }

    var typeLabel: String {
        PredictionType(rawValue: type)?.displayLabel ?? type
    }

    var isCrypto: Bool {
        PredictionType.cryptoTypes.contains(where: { $0.rawValue == type })
    }

    /// e.g. "10am EST" or "5pm EST" for crypto slots; nil for weather.
    var targetSlotLabel: String? {
        TargetSlot(rawValue: targetSlot ?? "")?.displayLabel
    }

    /// When we have an actual (set once after target time passes): "low" (actual > predicted), "high" (actual < predicted), or "on target". Nil if no actual.
    var predictionDirectionLabel: String? {
        guard let actual = actualValue else { return nil }
        let diff = actual - predictedValue
        let tolerance = isCrypto ? max(0.01, predictedValue * 0.0001) : 0.5
        if abs(diff) < tolerance { return "On target" }
        return diff > 0 ? "Prediction was low" : "Prediction was high"
    }

    var lastUpdated: String? {
        (createdAt ?? predictedAt).flatMap { DateFormatting.relativeString(fromISO: $0) }
    }

    // MARK: - Previews
    static let previewWeather = Prediction(
        id: "preview-w1",
        type: PredictionType.weather.rawValue,
        predictedAt: nil,
        targetTime: nil,
        predictedValue: 72,
        explanation: "Clear skies; historical average for this period.",
        actualValue: nil,
        passed: nil,
        errorMagnitude: nil,
        createdAt: ISO8601DateFormatter().string(from: Date()),
        supersedesId: nil,
        revision: nil,
        targetSlot: nil
    )
    static let previewBitcoin = Prediction(
        id: "preview-b1",
        type: PredictionType.bitcoin.rawValue,
        predictedAt: nil,
        targetTime: nil,
        predictedValue: 97250.50,
        explanation: "Short-term momentum and volume support.",
        actualValue: nil,
        passed: nil,
        errorMagnitude: nil,
        createdAt: ISO8601DateFormatter().string(from: Date()),
        supersedesId: nil,
        revision: nil,
        targetSlot: TargetSlot.am10.rawValue
    )
    static let previewWithActual = Prediction(
        id: "preview-w2",
        type: PredictionType.weather.rawValue,
        predictedAt: nil,
        targetTime: nil,
        predictedValue: 68,
        explanation: nil,
        actualValue: 70,
        passed: true,
        errorMagnitude: 2.0,
        createdAt: ISO8601DateFormatter().string(from: Date()),
        supersedesId: nil,
        revision: nil,
        targetSlot: nil
    )
    static let previewEthereum = Prediction(
        id: "preview-e1",
        type: PredictionType.ethereum.rawValue,
        predictedAt: nil,
        targetTime: nil,
        predictedValue: 3450.25,
        explanation: "10am EST estimate from current price.",
        actualValue: nil,
        passed: nil,
        errorMagnitude: nil,
        createdAt: ISO8601DateFormatter().string(from: Date()),
        supersedesId: nil,
        revision: nil,
        targetSlot: TargetSlot.am10.rawValue
    )
    static let previewSolana = Prediction(
        id: "preview-s1",
        type: PredictionType.solana.rawValue,
        predictedAt: nil,
        targetTime: nil,
        predictedValue: 198.50,
        explanation: "5pm EST estimate from current price.",
        actualValue: nil,
        passed: nil,
        errorMagnitude: nil,
        createdAt: ISO8601DateFormatter().string(from: Date()),
        supersedesId: nil,
        revision: nil,
        targetSlot: TargetSlot.pm5.rawValue
    )
    static var previewList: [Prediction] { [previewWeather, previewBitcoin, previewEthereum, previewSolana, previewWithActual] }
}

// MARK: - Calendar (LA timezone for weather target dates)

extension Calendar {
    static var la: Calendar {
        var cal = Calendar.current
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? TimeZone(secondsFromGMT: -8 * 3600)!
        return cal
    }

    func dateISOString(for date: Date) -> String {
        String(format: "%04d-%02d-%02d", component(.year, from: date), component(.month, from: date), component(.day, from: date))
    }

    func tomorrowISOString() -> String {
        let now = Date()
        guard let tomorrow = date(byAdding: .day, value: 1, to: now) else { return dateISOString(for: now) }
        return dateISOString(for: tomorrow)
    }
}
