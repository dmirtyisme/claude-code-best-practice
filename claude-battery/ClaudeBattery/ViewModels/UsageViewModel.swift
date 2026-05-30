import Foundation
import Combine

@MainActor
final class UsageViewModel: ObservableObject {

    @Published private(set) var usageData: UsageData?
    @Published private(set) var burnRate: BurnRate = .normal
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isBridgeSetUp: Bool = false

    private var burnCalculator = BurnRateCalculator()
    private var refreshTimer: AnyCancellable?
    private var prefsCancellable: AnyCancellable?
    private let prefsManager: PreferencesManager

    init(prefsManager: PreferencesManager = .shared) {
        self.prefsManager = prefsManager
        isBridgeSetUp = HookBridgeDataSource().isBridgeInstalled
        subscribeToPrefs()
        Task { await refresh() }
    }

    // MARK: - Menu bar label

    var menuBarTitle: String {
        guard let data = usageData else { return "⏳" }
        if !isBridgeSetUp && prefsManager.preferences.dataSource == .hookBridge {
            return "⚙️"
        }
        let prefs = prefsManager.preferences
        return menuBarString(prefs: prefs, data: data)
    }

    private func menuBarString(prefs: AppPreferences, data: UsageData) -> String {
        let mode = effectiveDisplayMode(prefs: prefs, data: data)
        let pct = Int(data.usagePercent * 100)
        switch mode {
        case .percentage:
            return "\(data.status.emoji) \(pct)%"
        case .countdown:
            return "⏳ \(data.resetCountdownString)"
        case .compact:
            return data.status.emoji
        case .smart:
            return "\(data.status.emoji) \(pct)%"
        }
    }

    private func effectiveDisplayMode(prefs: AppPreferences, data: UsageData) -> DisplayMode {
        if prefs.displayMode != .smart { return prefs.displayMode }
        return data.usagePercent >= 0.70 || data.timeUntilReset < 3600 ? .countdown : .percentage
    }

    // MARK: - Refresh

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        isBridgeSetUp = HookBridgeDataSource().isBridgeInstalled

        let source = makeDataSource()
        do {
            let data = try await source.fetch()
            burnCalculator.record(tokens: Int(data.usagePercent * 1000))
            burnRate = burnCalculator.burnRateFromPercent(currentPercent: data.usagePercent)
            usageData = data
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Bridge setup

    func installBridge() async throws {
        try HookBridgeDataSource.installBridgeScript()
        try HookBridgeDataSource.addToClaudeSettings()
        isBridgeSetUp = true
        prefsManager.update { $0.dataSource = .hookBridge }
    }

    // MARK: - Timer management

    func startAutoRefresh() {
        let interval = prefsManager.preferences.refreshInterval
        refreshTimer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.refresh() }
            }
    }

    func stopAutoRefresh() {
        refreshTimer?.cancel()
        refreshTimer = nil
    }

    // MARK: - Preferences subscription

    private func subscribeToPrefs() {
        prefsCancellable = prefsManager.$preferences
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.stopAutoRefresh()
                self.startAutoRefresh()
                Task { await self.refresh() }
            }
    }

    // MARK: - Factory

    private func makeDataSource() -> any UsageDataSource {
        let p = prefsManager.preferences
        switch p.dataSource {
        case .hookBridge:
            return HookBridgeDataSource()
        case .claudeCode:
            return ClaudeCodeDataSource(projectsPath: p.claudeCodePath)
        case .manual:
            return ManualDataSource(prefsManager: prefsManager)
        }
    }
}

// MARK: - BurnRateCalculator extension for percentage-based tracking

extension BurnRateCalculator {
    mutating func burnRateFromPercent(currentPercent: Double) -> BurnRate {
        let syntheticTokens = Int(currentPercent * 1000)
        record(tokens: syntheticTokens)
        return burnRate(currentUsed: syntheticTokens)
    }
}
