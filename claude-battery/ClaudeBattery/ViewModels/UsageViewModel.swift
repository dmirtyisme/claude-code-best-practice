import Foundation
import Combine

@MainActor
final class UsageViewModel: ObservableObject {

    @Published private(set) var usageData: UsageData?
    @Published private(set) var burnRate: BurnRate = .normal
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading: Bool = false

    private var burnCalculator = BurnRateCalculator()
    private var refreshTimer: AnyCancellable?
    private var prefsCancellable: AnyCancellable?
    private let prefsManager: PreferencesManager

    init(prefsManager: PreferencesManager = .shared) {
        self.prefsManager = prefsManager
        subscribeToPrefs()
        Task { await refresh() }
    }

    // MARK: - Menu bar label

    var menuBarTitle: String {
        guard let data = usageData else { return "⏳" }
        let prefs = prefsManager.preferences
        let mode = effectiveDisplayMode(prefs: prefs, data: data)

        switch mode {
        case .percentage:
            return "\(data.status.emoji) \(Int(data.usagePercent * 100))%"
        case .countdown:
            return "⏳ \(data.resetCountdownString)"
        case .compact:
            return data.status.emoji
        case .smart:
            // Should not reach here after effectiveDisplayMode resolves it
            return "\(data.status.emoji) \(Int(data.usagePercent * 100))%"
        }
    }

    private func effectiveDisplayMode(prefs: AppPreferences, data: UsageData) -> DisplayMode {
        if prefs.displayMode != .smart { return prefs.displayMode }
        // Smart mode: show countdown when high usage or near reset, else percentage
        return data.usagePercent >= 0.70 || data.timeUntilReset < 3600 ? .countdown : .percentage
    }

    // MARK: - Refresh

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        let source = makeDataSource()
        do {
            var data = try await source.fetch()

            // For Claude Code source, overlay the plan token limit from prefs
            if prefsManager.preferences.dataSource == .claudeCode {
                let planTokens = prefsManager.preferences.effectiveTotalTokens
                data = UsageData(
                    usedTokens: data.usedTokens,
                    totalTokens: planTokens,
                    resetDate: data.resetDate,
                    lastUpdated: data.lastUpdated
                )
            }

            burnCalculator.record(tokens: data.usedTokens)
            burnRate = burnCalculator.burnRate(currentUsed: data.usedTokens)
            usageData = data
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
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
        case .claudeCode:
            return ClaudeCodeDataSource(projectsPath: p.claudeCodePath)
        case .manual:
            return ManualDataSource(prefsManager: prefsManager)
        }
    }
}
