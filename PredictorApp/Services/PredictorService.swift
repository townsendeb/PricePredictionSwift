import Foundation

/// Runs prediction logic using simple fallback (forecast / current price); writes to LocalStore.
struct PredictorService {
    private let store: LocalStore
    private let fetcher = DataFetcher()

    init(store: LocalStore) {
        self.store = store
    }

    // MARK: - Weather

    private static let la = TimeZone(identifier: "America/Los_Angeles") ?? TimeZone(secondsFromGMT: -8 * 3600)!

    /// Predict today's and tomorrow's LA high; insert only if we don't already have a prediction for that date. Store target_time in UTC for correct querying.
    func predictWeather(weatherResult: DataFetcher.WeatherResult) {
        var calendar = Calendar.current
        calendar.timeZone = Self.la
        let now = Date()
        let todayISO = Calendar.la.dateISOString(for: now)
        let tomorrowISO = Calendar.la.tomorrowISOString()
        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now
        let todayEnd = calendar.date(byAdding: .second, value: -1, to: tomorrowStart) ?? todayStart
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")!

        let recent = getRecentWeatherTemps(limit: 7)

        // Today's high: only insert if no prediction for end-of-today slot yet. Always use todayActualHigh (or today-only fallbacks); never use tomorrowHigh.
        if store.getWeatherPredictionForTodayHigh(todayISO) == nil {
            let todayPredicted: Double
            let todayExplanation: String
            if let todayHigh = weatherResult.todayActualHigh {
                todayPredicted = todayHigh
                todayExplanation = "Forecast for today's high: \(Int(todayPredicted))°F."
            } else if !recent.isEmpty {
                let avg = recent.reduce(0, +) / Double(recent.count)
                todayPredicted = avg
                todayExplanation = "Today's high from recent average \(Int(avg))°F (no today forecast)."
            } else {
                todayPredicted = 70
                todayExplanation = "Today's high default 70°F."
            }
            let todayRounded = (todayPredicted * 10).rounded() / 10
            _ = store.insertPrediction(
                type: PredictionType.weather.rawValue,
                targetTime: formatter.string(from: todayEnd),
                predictedValue: todayRounded,
                explanation: todayExplanation,
                supersedesId: nil,
                revision: 0
            )
        }

        // Tomorrow's high: only insert if no prediction for start-of-tomorrow slot yet. Always use tomorrowHigh (or tomorrow-only fallbacks); never use todayActualHigh.
        if store.getWeatherPredictionForTomorrowHigh(tomorrowISO) == nil {
            let tomorrowPredicted: Double
            let tomorrowExplanation: String
            if let tomorrowHigh = weatherResult.tomorrowHigh, recent.isEmpty {
                tomorrowPredicted = tomorrowHigh
                tomorrowExplanation = "Forecast for tomorrow's high: \(Int(tomorrowPredicted))°F."
            } else if !recent.isEmpty {
                let avg = recent.reduce(0, +) / Double(recent.count)
                tomorrowPredicted = weatherResult.tomorrowHigh ?? avg
                tomorrowExplanation = "Based on recent highs and forecast; predicting \(Int(tomorrowPredicted))°F for tomorrow's high."
            } else {
                tomorrowPredicted = weatherResult.tomorrowHigh ?? 70
                tomorrowExplanation = "Initial prediction for tomorrow: \(Int(tomorrowPredicted))°F from forecast."
            }
            let tomorrowRounded = (tomorrowPredicted * 10).rounded() / 10
            _ = store.insertPrediction(
                type: PredictionType.weather.rawValue,
                targetTime: formatter.string(from: tomorrowStart),
                predictedValue: tomorrowRounded,
                explanation: tomorrowExplanation,
                supersedesId: nil,
                revision: 0
            )
        }
    }

    private func getRecentWeatherTemps(limit: Int) -> [Double] {
        let rows = store.getPredictionsWithActuals(type: PredictionType.weather.rawValue, limit: limit)
        let values = rows.compactMap { r -> Double? in
            if let a = r.actualValue { return a }
            return r.predictedValue
        }
        return Array(values.suffix(limit))
    }

    // MARK: - Crypto (Bitcoin, Ethereum, Solana) — next hour

    /// Next full hour (e.g. 6:55 → 7:00).
    private static func nextFullHour(after now: Date) -> Date {
        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        let hour = cal.component(.hour, from: now)
        let startOfHour = cal.date(bySettingHour: hour, minute: 0, second: 0, of: now) ?? now
        return cal.date(byAdding: .hour, value: 1, to: startOfHour) ?? now.addingTimeInterval(3600)
    }

    /// Predict price at the next full hour using current price + simple trend from recent history (so it can differ from current).
    func predictCrypto(type: String, currentPrice: Double?) {
        guard let current = currentPrice else { return }
        let now = Date()
        let target = Self.nextFullHour(after: now)
        let formatter = ISO8601DateFormatter()
        let recent = getRecentCryptoPrices(type: type, limit: 24, currentPrice: current)

        // Estimate next-hour move from recent prices (newest first). Use last observed change, capped at ±2% of current.
        var predicted = current
        if recent.count >= 2 {
            let lastChange = recent[0] - recent[1]
            let cap = current * 0.02
            let cappedChange = max(-cap, min(cap, lastChange))
            predicted = current + cappedChange
        }

        let rounded = (predicted * 100).rounded() / 100
        let diff = rounded - current
        let explanation: String
        if abs(diff) < 0.01 {
            explanation = "Next hour: same as current (no recent trend)."
        } else if diff > 0 {
            explanation = "Next hour: +$\(String(format: "%.2f", diff)) from current (upward trend)."
        } else {
            explanation = "Next hour: -$\(String(format: "%.2f", -diff)) from current (downward trend)."
        }
        _ = store.insertPrediction(
            type: type,
            targetTime: formatter.string(from: target),
            predictedValue: rounded,
            explanation: explanation,
            supersedesId: nil,
            revision: 0,
            targetSlot: nil
        )
    }

    private func getRecentCryptoPrices(type: String, limit: Int, currentPrice: Double? = nil) -> [Double] {
        let rows = store.getPredictionsByType(type: type, limit: limit)
        var values = rows.compactMap { r -> Double? in
            if let a = r.actualValue { return a }
            return r.predictedValue
        }
        if let cur = currentPrice {
            values = [cur] + values
        }
        return Array(values.suffix(limit))
    }

    // MARK: - Verify and retrain (simple: update actuals)

    /// Update past predictions with actuals where possible.
    func verifyAndRetrain(weatherResult: DataFetcher.WeatherResult, cryptoResult: DataFetcher.CryptoResult) {
        let now = Date()

        for cryptoType in PredictionType.cryptoTypes {
            let current: Double? = switch cryptoType {
            case .bitcoin: cryptoResult.bitcoin
            case .ethereum: cryptoResult.ethereum
            case .solana: cryptoResult.solana
            case .weather: nil
            }
            guard let current = current else { continue }
            let preds = store.getPredictionsForVerification(type: cryptoType.rawValue, limit: 10)
            for p in preds {
                guard let targetStr = p.targetTime else { continue }
                guard let target = ISO8601DateFormatter().date(from: targetStr.replacingOccurrences(of: "Z", with: "+00:00")) ?? ISO8601DateFormatter().date(from: targetStr) else { continue }
                if now.timeIntervalSince(target) > 30 * 60 {
                    let predVal = p.predictedValue
                    let err = abs(current - predVal)
                    let passed = predVal > 0 && err < predVal * 0.02
                    store.updatePredictionActual(id: p.id, actualValue: current, passed: passed, errorMagnitude: err)
                }
            }
        }

        // Weather: verify only when the prediction's target time (end of that day) has passed, so we don't mark "correct" before the day has ended.
        if let todayHigh = weatherResult.todayActualHigh {
            let todayISO = Calendar.la.dateISOString(for: now)
            guard let wPred = store.getWeatherPredictionForTodayHigh(todayISO), wPred.actualValue == nil,
                  let targetStr = wPred.targetTime else { return }
            guard let target = ISO8601DateFormatter().date(from: targetStr.replacingOccurrences(of: "Z", with: "+00:00")) ?? ISO8601DateFormatter().date(from: targetStr) else { return }
            guard now > target else { return }
            let predVal = wPred.predictedValue
            let err = abs(todayHigh - predVal)
            let passed = err < 3
            store.updatePredictionActual(id: wPred.id, actualValue: todayHigh, passed: passed, errorMagnitude: err)
        }
    }
}
