import Foundation

/// Fetches LA weather (tomorrow high, today actual high) and crypto prices (BTC, ETH, SOL) from public APIs.
struct DataFetcher {
    static let weatherURL = URL(string: "https://forecast.weather.gov/MapClick.php?lat=34.0522&lon=-118.2437&unit=0&lg=english&FcstType=json")!
    static let cryptoURL = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum,solana&vs_currencies=usd")!

    struct WeatherResult {
        var tomorrowHigh: Double?
        var todayActualHigh: Double?
    }

    /// Bitcoin, Ethereum, and Solana current USD prices (from one CoinGecko call).
    struct CryptoResult {
        var bitcoin: Double?
        var ethereum: Double?
        var solana: Double?
    }

    /// 7-day price history for one coin (timestamp_ms, price) from CoinGecko market_chart.
    struct CryptoHistoryResult {
        let coinId: String
        let points: [(timestampMs: Int64, price: Double)]
    }

    /// Fetch LA weather; returns tomorrow's forecast high and today's actual (or forecast) high.
    func fetchWeather() async throws -> WeatherResult {
        let (data, _) = try await URLSession.shared.data(from: Self.weatherURL)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return WeatherResult()
        }
        let timeObj = json["time"] as? [String: Any]
        let dataObj = json["data"] as? [String: Any]
        let periodNames = (timeObj?["startPeriodName"] as? [String]) ?? (json["startPeriodName"] as? [String]) ?? []
        let tempLabels = (timeObj?["tempLabel"] as? [String]) ?? []
        let tempsRaw = (dataObj?["temperature"] ?? json["temperature"]) as? [Any] ?? []
        let temps: [Int] = tempsRaw.compactMap { v in
            if let i = v as? Int { return i }
            if let s = v as? String { return Int(s) }
            return nil
        }
        let la = TimeZone(identifier: "America/Los_Angeles") ?? TimeZone(secondsFromGMT: -8 * 3600)!
        var calendar = Calendar.current
        calendar.timeZone = la
        let now = Date()
        let localNow = now
        let tomorrowDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: localNow)) ?? localNow
        let todayWeekday = calendar.component(.weekday, from: localNow)
        let tomorrowWeekday = calendar.component(.weekday, from: tomorrowDate)
        let weekdayNames = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let todayStr = weekdayNames[todayWeekday].lowercased()
        let tomorrowStr = weekdayNames[tomorrowWeekday].lowercased()

        var tomorrowHigh: Double?
        var todayActual: Double?

        for (i, name) in periodNames.enumerated() {
            guard let t = temps[safe: i] else { continue }
            let label = (i < tempLabels.count ? tempLabels[i] : "")
            let labelLower = label.lowercased()
            let nameLower = name.lowercased()
            if tomorrowStr == nameLower || nameLower.contains(tomorrowStr), labelLower == "high" {
                if tomorrowHigh == nil { tomorrowHigh = Double(t) }
                else { tomorrowHigh = max(tomorrowHigh!, Double(t)) }
            }
            // API uses "Today"/"Tonight", not weekday name; also match weekday in case format varies.
            if (nameLower == "today" || todayStr == nameLower || nameLower.contains(todayStr)), labelLower == "high" {
                if todayActual == nil { todayActual = Double(t) }
                else { todayActual = max(todayActual!, Double(t)) }
            }
        }

        if todayActual == nil {
            let obs = (dataObj?["currentobservation"] ?? json["currentobservation"]) as? [String: Any]
            if let temp = obs?["Temp"] as? Int {
                todayActual = Double(temp)
            } else if let temp = obs?["Temp"] as? String, let v = Double(temp) {
                todayActual = v
            }
        }

        return WeatherResult(tomorrowHigh: tomorrowHigh, todayActualHigh: todayActual)
    }

    /// Fetch current Bitcoin, Ethereum, and Solana prices in USD (single CoinGecko request).
    func fetchCrypto() async throws -> CryptoResult {
        let (data, _) = try await URLSession.shared.data(from: Self.cryptoURL)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return CryptoResult()
        }
        func price(from key: String) -> Double? {
            guard let obj = json[key] as? [String: Any] else {
                if let v = json[key] as? Double { return v }
                if let v = json[key] as? Int { return Double(v) }
                return nil
            }
            if let usd = obj["usd"] as? Double { return usd }
            if let usd = obj["usd"] as? Int { return Double(usd) }
            return nil
        }
        return CryptoResult(
            bitcoin: price(from: "bitcoin"),
            ethereum: price(from: "ethereum"),
            solana: price(from: "solana")
        )
    }

    /// Fetch 7-day price history for one coin (CoinGecko market_chart; returns hourly points).
    static func marketChartURL(coinId: String, days: Int = 7) -> URL {
        URL(string: "https://api.coingecko.com/api/v3/coins/\(coinId)/market_chart?vs_currency=usd&days=\(days)")!
    }

    func fetchCryptoHistory(coinId: String, days: Int = 7) async throws -> CryptoHistoryResult {
        let url = Self.marketChartURL(coinId: coinId, days: days)
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pricesRaw = json["prices"] as? [[Any]] else {
            return CryptoHistoryResult(coinId: coinId, points: [])
        }
        let points: [(timestampMs: Int64, price: Double)] = pricesRaw.compactMap { pair in
            guard pair.count >= 2,
                  let tsNum = pair[0] as? NSNumber,
                  let pNum = pair[1] as? NSNumber else { return nil }
            return (timestampMs: tsNum.int64Value, price: pNum.doubleValue)
        }
        return CryptoHistoryResult(coinId: coinId, points: points)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
