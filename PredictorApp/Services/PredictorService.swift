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

    /// Predict today's and tomorrow's LA high; insert both. Today uses todayActualHigh, tomorrow uses tomorrowHigh (distinct).
    func predictWeather(weatherResult: DataFetcher.WeatherResult) {
        var calendar = Calendar.current
        calendar.timeZone = Self.la
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now
        let todayEnd = calendar.date(byAdding: .second, value: -1, to: tomorrowStart) ?? todayStart
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = Self.la

        let recent = getRecentWeatherTemps(limit: 7)

        // Today's high: use todayActualHigh only (so it differs from tomorrow)
        let todayPredicted: Double
        let todayExplanation: String
        if let todayHigh = weatherResult.todayActualHigh {
            todayPredicted = todayHigh
            todayExplanation = "Forecast for today: \(Int(todayPredicted))°F."
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

        // Tomorrow's high: use tomorrowHigh and optional recent blend
        let tomorrowPredicted: Double
        let tomorrowExplanation: String
        if let tomorrowHigh = weatherResult.tomorrowHigh, recent.isEmpty {
            tomorrowPredicted = tomorrowHigh
            tomorrowExplanation = "Forecast for tomorrow: \(Int(tomorrowPredicted))°F."
        } else if !recent.isEmpty {
            let avg = recent.reduce(0, +) / Double(recent.count)
            tomorrowPredicted = weatherResult.tomorrowHigh ?? avg
            tomorrowExplanation = "Based on recent highs and forecast; predicting \(Int(tomorrowPredicted))°F for tomorrow."
        } else {
            tomorrowPredicted = weatherResult.tomorrowHigh ?? 70
            tomorrowExplanation = "Initial prediction \(Int(tomorrowPredicted))°F from current forecast."
        }
        let tomorrowRounded = (tomorrowPredicted * 10).rounded() / 10
        let latestTomorrow = store.getLatestPredictions().first { $0.type == PredictionType.weather.rawValue }
        var supersedesId: String?
        var revision = 0
        if let prev = latestTomorrow, abs(tomorrowRounded - prev.predictedValue) > 2 {
            supersedesId = prev.id
            revision = (prev.revision ?? 0) + 1
        }
        _ = store.insertPrediction(
            type: PredictionType.weather.rawValue,
            targetTime: formatter.string(from: tomorrowStart),
            predictedValue: tomorrowRounded,
            explanation: tomorrowExplanation,
            supersedesId: supersedesId,
            revision: revision
        )
    }

    private func getRecentWeatherTemps(limit: Int) -> [Double] {
        let rows = store.getPredictionsWithActuals(type: PredictionType.weather.rawValue, limit: limit)
        let values = rows.compactMap { r -> Double? in
            if let a = r.actualValue { return a }
            return r.predictedValue
        }
        return Array(values.suffix(limit))
    }

    // MARK: - Crypto (Bitcoin, Ethereum, Solana) — 10am & 5pm EST

    private static let est = TimeZone(identifier: "America/New_York") ?? TimeZone(secondsFromGMT: -5 * 3600)!

    /// Next 10:00 AM EST (today or tomorrow).
    private static func next10amEST(after now: Date) -> Date {
        var cal = Calendar.current
        cal.timeZone = est
        let today = cal.startOfDay(for: now)
        guard var target = cal.date(bySettingHour: 10, minute: 0, second: 0, of: today) else { return now }
        if target <= now {
            guard let tomorrow = cal.date(byAdding: .day, value: 1, to: today) else { return target }
            target = cal.date(bySettingHour: 10, minute: 0, second: 0, of: tomorrow) ?? target
        }
        return target
    }

    /// Next 5:00 PM (17:00) EST (today or tomorrow).
    private static func next5pmEST(after now: Date) -> Date {
        var cal = Calendar.current
        cal.timeZone = est
        let today = cal.startOfDay(for: now)
        guard var target = cal.date(bySettingHour: 17, minute: 0, second: 0, of: today) else { return now }
        if target <= now {
            guard let tomorrow = cal.date(byAdding: .day, value: 1, to: today) else { return target }
            target = cal.date(bySettingHour: 17, minute: 0, second: 0, of: tomorrow) ?? target
        }
        return target
    }

    /// Estimated hourly drift from historical 10am/5pm same-day actuals. Capped at ±0.01. Returns 0 if no pairs.
    private func hourlyDriftForCrypto(type: String) -> Double {
        let rows = store.getPredictionsWithActuals(type: type, limit: 50)
        guard !rows.isEmpty else { return 0 }
        var cal = Calendar.current
        cal.timeZone = Self.est
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = Self.est
        struct DayKey: Hashable {
            let year: Int
            let month: Int
            let day: Int
        }
        var dayTo10am: [DayKey: Double] = [:]
        var dayTo5pm: [DayKey: Double] = [:]
        for p in rows {
            guard let actual = p.actualValue, let targetStr = p.targetTime else { continue }
            guard let date = formatter.date(from: targetStr.replacingOccurrences(of: "Z", with: "+00:00")) ?? formatter.date(from: targetStr) else { continue }
            let comps = cal.dateComponents([.year, .month, .day], from: date)
            guard let y = comps.year, let m = comps.month, let d = comps.day else { continue }
            let key = DayKey(year: y, month: m, day: d)
            switch p.targetSlot {
            case TargetSlot.am10.rawValue: dayTo10am[key] = actual
            case TargetSlot.pm5.rawValue: dayTo5pm[key] = actual
            default: break
            }
        }
        var drifts: [Double] = []
        for (key, am) in dayTo10am {
            guard let pm = dayTo5pm[key], am > 0 else { continue }
            let drift = (pm - am) / am / 7.0
            drifts.append(drift)
        }
        guard !drifts.isEmpty else { return 0 }
        let avg = drifts.reduce(0, +) / Double(drifts.count)
        return max(-0.01, min(0.01, avg))
    }

    /// Predict price at next 10am EST and next 5pm EST; values differ by time horizon and historical drift.
    func predictCrypto(type: String, currentPrice: Double?) {
        guard let current = currentPrice else { return }
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = Self.est
        let t10 = Self.next10amEST(after: now)
        let t5 = Self.next5pmEST(after: now)
        let hoursTo10am = max(0, t10.timeIntervalSince(now) / 3600)
        let hoursTo5pm = max(0, t5.timeIntervalSince(now) / 3600)
        let drift = hourlyDriftForCrypto(type: type)
        let pred10 = current * pow(1 + drift, hoursTo10am)
        let pred5 = current * pow(1 + drift, hoursTo5pm)
        let rounded10 = (pred10 * 100).rounded() / 100
        let rounded5 = (pred5 * 100).rounded() / 100
        let recent = getRecentCryptoPrices(type: type, limit: 24)
        let baseNote = recent.isEmpty ? "from current price" : "from current price and recent trend"
        _ = store.insertPrediction(
            type: type,
            targetTime: formatter.string(from: t10),
            predictedValue: rounded10,
            explanation: "10am EST in \(String(format: "%.1f", hoursTo10am))h: \(baseNote).",
            supersedesId: nil,
            revision: 0,
            targetSlot: TargetSlot.am10.rawValue
        )
        _ = store.insertPrediction(
            type: type,
            targetTime: formatter.string(from: t5),
            predictedValue: rounded5,
            explanation: "5pm EST in \(String(format: "%.1f", hoursTo5pm))h: \(baseNote).",
            supersedesId: nil,
            revision: 0,
            targetSlot: TargetSlot.pm5.rawValue
        )
    }

    private func getRecentCryptoPrices(type: String, limit: Int) -> [Double] {
        let rows = store.getPredictionsWithActuals(type: type, limit: limit)
        let values = rows.compactMap { r -> Double? in
            if let a = r.actualValue { return a }
            return r.predictedValue
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

        // Weather: verify today's weather prediction with today_actual_high
        if let todayHigh = weatherResult.todayActualHigh {
            let todayISO = Calendar.la.dateISOString(for: now)
            if let wPred = store.getWeatherPredictionForTargetDate(todayISO), wPred.actualValue == nil {
                let predVal = wPred.predictedValue
                let err = abs(todayHigh - predVal)
                let passed = err < 3
                store.updatePredictionActual(id: wPred.id, actualValue: todayHigh, passed: passed, errorMagnitude: err)
            }
        }
    }
}
