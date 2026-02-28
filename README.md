# PredictorApp

A native **Swift/SwiftUI** app for **macOS, iPhone, and iPad** that predicts **LA weather** (today’s and tomorrow’s high) and **crypto prices** (Bitcoin, Ethereum, Solana at 10am and 5pm EST). All logic runs in the app; data is stored locally in SQLite. No backend, no cloud, no Python—just open the project in Xcode and run.

**Fork-friendly:** The predictor logic, data fetchers, and storage are clearly separated so you can tweak models, add assets, or change APIs without touching the rest of the app.

---

## Features

- **Weather**
  - Predictions for **today’s high** and **tomorrow’s high** (LA area).
  - Uses [weather.gov](https://forecast.weather.gov/) MapClick API; today uses the “today” forecast/observation, tomorrow uses the “tomorrow” forecast so the two numbers stay distinct.
- **Crypto (BTC, ETH, SOL)**
  - Predictions for **10:00 AM EST** and **5:00 PM EST** each day.
  - Time-based logic: each target uses “hours until” that time and optional **historical drift** (from same-day 10am→5pm actuals when available).
  - Prices from [CoinGecko](https://www.coingecko.com/) (single request for all three).
- **History**
  - Past predictions with actuals; **high/low** vs actual (e.g. “Prediction was low” when actual > predicted).
  - Filter by type (Weather, BTC, ETH, SOL).
- **Learnings**
  - Placeholder list for future “tidbits” from verification/retrain (stored in SQLite).
- **Storage & refresh**
  - **SQLite** in Application Support; no server or API keys required.
  - **Manual refresh:** pull to refresh on Overview.
  - **Auto refresh:** when the app becomes active (e.g. opening from background), it runs a refresh once.

---

## Getting started

1. **Clone the repo**
   ```bash
   git clone https://github.com/YOUR_USERNAME/PredictorApp.git
   cd PredictorApp
   ```

2. **Open in Xcode**
   - Open `PredictorApp.xcodeproj`.
   - Select the **PredictorApp Mac** or **PredictorApp iOS** scheme.
   - Run (⌘R).

3. **Use the app**
   - **Overview:** Pull to refresh to fetch data, run predictions, and save to local SQLite.
   - **History:** View past predictions and actuals; filter by type.
   - **Learnings:** View stored learnings (if any).
   - **Settings:** Short description of local-only storage.

No accounts, API keys, or external services are required. The app uses public APIs (weather.gov and CoinGecko) with no auth.

---

## Project structure

```
PredictorApp/
├── PredictorAppApp.swift    # App entry; injects AppDataStore; auto-refresh on activate
├── ContentView.swift        # Root navigation + tab (Overview, History, Learnings, Settings)
├── Models/
│   ├── Prediction.swift     # Prediction + PredictionType, TargetSlot, DateFormatting, Calendar.la
│   └── Learning.swift       # Learning (tidbit) model
├── Services/
│   ├── AppDataStore.swift   # ObservableObject: predictions, learnings, refreshAll(), latest* accessors
│   ├── DataFetcher.swift    # weather.gov + CoinGecko; returns WeatherResult, CryptoResult
│   ├── LocalStore.swift     # SQLite: predictions, learnings, migrations
│   └── PredictorService.swift # Prediction logic: weather (today/tomorrow), crypto (10am/5pm), verify
└── Views/
    ├── OverviewView.swift   # Weather + crypto sections; pull-to-refresh
    ├── HistoryView.swift    # Filterable list with actuals and high/low
    ├── LearningsView.swift  # List of learnings by type
    └── SettingsView.swift   # Short info text
```

- **Models:** Data types and shared enums/formatting. No network or persistence.
- **Services:** Fetching (DataFetcher), persistence (LocalStore), prediction and verification (PredictorService), and app state (AppDataStore).
- **Views:** SwiftUI only; bind to `AppDataStore`.

---

## How predictions work (so you can tweak them)

- **Weather**
  - **Today’s high:** `weatherResult.todayActualHigh` (weather.gov “today” high or observation), with fallbacks (recent average or default).
  - **Tomorrow’s high:** `weatherResult.tomorrowHigh` and optional blend with recent actuals from SQLite.
  - Target times: end-of-today (LA) for today, start-of-tomorrow (LA) for tomorrow.
- **Crypto (each of BTC, ETH, SOL)**
  - **10am and 5pm EST:** Next occurrence of 10:00 and 17:00 in `America/New_York` from “now.”
  - **Hourly drift (optional):** From `getPredictionsWithActuals`: same calendar day (EST) 10am vs 5pm actuals → `(5pm - 10am) / 10am / 7`, averaged and capped at ±1% per hour.
  - **Prediction:** `currentPrice * (1 + drift)^hoursUntilTarget` for 10am and 5pm (rounded to 2 decimals). So 10am and 5pm differ by time horizon and, when available, historical drift.
- **Verification**
  - **Weather:** Prediction whose target date is “today” (LA) is updated with `todayActualHigh` when you refresh after the day is in progress.
  - **Crypto:** Predictions whose `target_time` is more than 30 minutes in the past get `actual_value` set from the current price at refresh time. Each prediction is only updated once (no repeated overwrites).

All of this lives in `PredictorService` and `DataFetcher`; you can replace or extend the logic there (e.g. different formulas, more slots, or other data sources) without changing the rest of the app.

---

## Data sources

| Data        | Source | Auth |
|------------|--------|------|
| LA weather | [weather.gov MapClick](https://forecast.weather.gov/MapClick.php?lat=34.0522&lon=-118.2437&unit=0&lg=english&FcstType=json) | None |
| BTC/ETH/SOL| [CoinGecko simple/price](https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum,solana&vs_currencies=usd) | None |

URLs are in `DataFetcher.swift`. You can point to different endpoints or add API keys there if you fork.

---

## Customization ideas (fork & tweak)

- **Prediction logic:** Change formulas in `PredictorService` (e.g. different drift, more time slots, or simple ML in Swift).
- **Assets:** Add more cryptos or locations by extending `PredictionType`, `DataFetcher`, and the Overview/History filters.
- **Storage:** Schema and migrations are in `LocalStore`; you can add tables or columns and keep using the same `Prediction`/`Learning` models with Codable/snake_case.
- **UI:** Views read from `AppDataStore`; you can add screens, change layout, or plug in charts without touching services.

---

## Requirements

- **Xcode** (current stable recommended)
- **macOS** and/or **iOS** (schemes for both)
- No Python, no backend, no Supabase or other services

---

## License

This project is open source under the **MIT License**. See [LICENSE](LICENSE) for the full text. You can use, copy, modify, merge, publish, distribute, and sell copies, with minimal restrictions. Fork and tweak the predictor to your heart’s content.
