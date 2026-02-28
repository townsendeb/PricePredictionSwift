import SwiftUI

private enum AppTheme {
    static let accent = Color(red: 0.2, green: 0.6, blue: 0.9)
    static let weatherGradient = LinearGradient(colors: [Color(red: 0.4, green: 0.75, blue: 1), Color(red: 0.25, green: 0.6, blue: 0.95)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let cryptoGradient = LinearGradient(colors: [Color(red: 0.95, green: 0.7, blue: 0.3), Color(red: 0.9, green: 0.5, blue: 0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let cardCorner: CGFloat = 14
    static let cardPadding: CGFloat = 16
}

struct OverviewView: View {
    @EnvironmentObject var store: AppDataStore
    @State private var isRefreshing = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                Text("Current Predictions")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text("Weather")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical)

                if let msg = store.errorMessage {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title2)
                            .foregroundStyle(.orange)
                        Text(msg)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppTheme.cardPadding)
                    .background(.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCorner))
                }

                if let w = store.latestWeatherToday {
                    predictionCard(
                        title: "Today's high",
                        subtitle: "LA weather",
                        icon: "sun.max.fill",
                        gradient: AppTheme.weatherGradient
                    ) {
                        weatherSectionContent(w)
                    }
                }
                if let w = store.latestWeatherTomorrow {
                    predictionCard(
                        title: "Tomorrow's high",
                        subtitle: "LA weather",
                        icon: "cloud.sun.fill",
                        gradient: AppTheme.weatherGradient
                    ) {
                        weatherSectionContent(w)
                    }
                }
                
                Text("Crypto")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical)

                if let b = store.latestBitcoin {
                    predictionCard(title: "Bitcoin", subtitle: "Next hour", icon: "bitcoinsign.circle.fill", gradient: AppTheme.cryptoGradient) {
                        cryptoSectionContent(b)
                    }
                }
                if let e = store.latestEthereum {
                    predictionCard(title: "Ethereum", subtitle: "Next hour", icon: "e.circle.fill", gradient: AppTheme.cryptoGradient) {
                        cryptoSectionContent(e)
                    }
                }
                if let s = store.latestSolana {
                    predictionCard(title: "Solana", subtitle: "Next hour", icon: "s.circle.fill", gradient: AppTheme.cryptoGradient) {
                        cryptoSectionContent(s)
                    }
                }

                if store.latestWeatherToday == nil && store.latestWeatherTomorrow == nil && store.latestBitcoin == nil && store.latestEthereum == nil && store.latestSolana == nil && !store.isLoading {
                    VStack(spacing: 12) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 44))
                            .foregroundStyle(AppTheme.accent.opacity(0.7))
                        Text("No predictions yet")
                            .font(.headline)
                        Text("Pull to refresh to load predictions.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Overview")
        .refreshable {
            isRefreshing = true
            await store.refreshAll()
            isRefreshing = false
        }
        .overlay {
            if store.isLoading && !isRefreshing {
                ZStack {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(.white)
                }
            }
        }
    }

    private func predictionCard<Content: View>(
        title: String,
        subtitle: String,
        icon: String,
        gradient: LinearGradient,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.95))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
            }
            .padding(.horizontal, AppTheme.cardPadding)
            .padding(.top, AppTheme.cardPadding)
            content()
                .padding(.horizontal, AppTheme.cardPadding)
                .padding(.bottom, AppTheme.cardPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(gradient.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCorner))
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
    }

    private func weatherSectionContent(_ p: Prediction) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(p.predictedValue, specifier: "%.0f")°")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            if let updated = p.lastUpdated {
                Text("Updated \(updated)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            if let explanation = p.explanation, !explanation.isEmpty {
                Text(explanation)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    private func cryptoSectionContent(_ p: Prediction) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("$\(p.predictedValue, specifier: "%.2f")")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            if let updated = p.lastUpdated {
                Text("Updated \(updated)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            if let explanation = p.explanation, !explanation.isEmpty {
                Text(explanation)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }
}

#Preview {
    NavigationStack {
        OverviewView()
            .environmentObject(AppDataStore.preview)
    }
}
