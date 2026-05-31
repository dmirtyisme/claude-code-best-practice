import AppKit
import Combine
import Foundation

@MainActor
final class UsageViewModel: ObservableObject {

    @Published private(set) var usageData: UsageData?
    @Published private(set) var burnRate: BurnRate = .normal
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var bridgeStatus: BridgeStatus = .notInstalled

    private var burnCalculator = BurnRateCalculator()
    private var refreshTimer: AnyCancellable?
    private var prefsCancellable: AnyCancellable?
    private let prefsManager: PreferencesManager

    init(prefsManager: PreferencesManager = .shared) {
        self.prefsManager = prefsManager
        bridgeStatus = HookBridgeDataSource().currentBridgeStatus
        subscribeToPrefs()
        Task { await refresh() }
    }

    // MARK: - Menu bar rendering

    /// Arc image representing current usage.
    var menuBarImage: NSImage {
        guard let data = usageData else { return ArcStatusImage.makeIdle() }
        return ArcStatusImage.make(percent: data.usagePercent, status: data.status)
    }

    /// Compact text label shown to the right of the arc.
    var menuBarAttributedLabel: NSAttributedString {
        guard let data = usageData else { return NSAttributedString() }
        let text = menuBarLabelText(for: data)
        guard !text.isEmpty else { return NSAttributedString() }
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: menuBarLabelColor(for: data.status)
        ])
    }

    /// Full detail tooltip shown on hover.
    var menuBarToolTip: String {
        guard let data = usageData else { return "Claude Battery — waiting for data" }
        let pct       = max(0, Int(data.usagePercent * 100))
        let remaining = max(0, 100 - pct)
        let countdown = formatCountdown(data.timeUntilReset)
        let updated   = relativeTime(data.lastUpdated)
        return "Used: \(pct)%\nRemaining: \(remaining)%\nResets in: \(countdown)\nLast updated: \(updated)"
    }

    // MARK: - Private menu bar helpers

    private func menuBarLabelText(for data: UsageData) -> String {
        let prefs = prefsManager.preferences
        let mode  = effectiveDisplayMode(prefs: prefs, data: data)
        let pct   = max(0, Int(data.usagePercent * 100))

        switch mode {
        case .percentage:
            return "\(pct)%"
        case .countdown:
            return formatCountdown(data.timeUntilReset)
        case .compact:
            return ""
        case .smart:
            let cd = formatCountdown(data.timeUntilReset)
            if data.usagePercent >= 0.70 || data.timeUntilReset < 3600 {
                return "\(pct)% \(cd)"
            }
            return "\(pct)%"
        }
    }

    private func menuBarLabelColor(for status: UsageStatus) -> NSColor {
        switch status {
        case .safe:                return .labelColor
        case .medium:              return .systemOrange
        case .critical, .depleted: return .systemRed
        }
    }

    /// H:MM format (hours and minutes).  e.g. "4:59", "0:42", "12:05"
    private func formatCountdown(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds) / 60)
        let hours   = totalMinutes / 60
        let minutes = totalMinutes % 60
        return String(format: "%d:%02d", hours, minutes)
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60   { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }

    private func effectiveDisplayMode(prefs: AppPreferences, data: UsageData) -> DisplayMode {
        if prefs.displayMode != .smart { return prefs.displayMode }
        return data.usagePercent >= 0.70 || data.timeUntilReset < 3600 ? .countdown : .percentage
    }

    // MARK: - Refresh

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        bridgeStatus = HookBridgeDataSource().currentBridgeStatus

        let source = makeDataSource()
        do {
            let data = try await source.fetch()
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
        bridgeStatus = .waitingForData
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
