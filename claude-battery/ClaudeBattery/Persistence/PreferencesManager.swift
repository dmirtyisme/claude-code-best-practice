import Foundation

final class PreferencesManager: ObservableObject {
    static let shared = PreferencesManager()

    private let defaults = UserDefaults.standard
    private enum Key: String {
        case dataSource, displayMode, refreshInterval, launchAtLogin
        case showPromptEstimates, manualPlan, manualCustomTokens
        case manualUsedTokens, manualResetDate, claudeCodePath
    }

    @Published var preferences = AppPreferences() {
        didSet { save() }
    }

    private init() {
        load()
    }

    private func load() {
        var p = AppPreferences()

        if let raw = defaults.string(forKey: Key.dataSource.rawValue),
           let v = DataSourceType(rawValue: raw) { p.dataSource = v }

        if let raw = defaults.string(forKey: Key.displayMode.rawValue),
           let v = DisplayMode(rawValue: raw) { p.displayMode = v }

        let interval = defaults.double(forKey: Key.refreshInterval.rawValue)
        if interval > 0 { p.refreshInterval = interval }

        p.launchAtLogin = defaults.bool(forKey: Key.launchAtLogin.rawValue)

        let showEstimates = defaults.object(forKey: Key.showPromptEstimates.rawValue)
        p.showPromptEstimates = showEstimates.map { ($0 as? Bool) ?? true } ?? true

        if let raw = defaults.string(forKey: Key.manualPlan.rawValue),
           let v = ClaudePlan(rawValue: raw) { p.manualPlan = v }

        let customTokens = defaults.integer(forKey: Key.manualCustomTokens.rawValue)
        if customTokens > 0 { p.manualCustomTokens = customTokens }

        let usedTokens = defaults.integer(forKey: Key.manualUsedTokens.rawValue)
        if usedTokens >= 0 { p.manualUsedTokens = usedTokens }

        if let resetDate = defaults.object(forKey: Key.manualResetDate.rawValue) as? Date {
            p.manualResetDate = resetDate
        }

        if let path = defaults.string(forKey: Key.claudeCodePath.rawValue) {
            p.claudeCodePath = path
        }

        preferences = p
    }

    private func save() {
        let p = preferences
        defaults.set(p.dataSource.rawValue, forKey: Key.dataSource.rawValue)
        defaults.set(p.displayMode.rawValue, forKey: Key.displayMode.rawValue)
        defaults.set(p.refreshInterval, forKey: Key.refreshInterval.rawValue)
        defaults.set(p.launchAtLogin, forKey: Key.launchAtLogin.rawValue)
        defaults.set(p.showPromptEstimates, forKey: Key.showPromptEstimates.rawValue)
        defaults.set(p.manualPlan.rawValue, forKey: Key.manualPlan.rawValue)
        defaults.set(p.manualCustomTokens, forKey: Key.manualCustomTokens.rawValue)
        defaults.set(p.manualUsedTokens, forKey: Key.manualUsedTokens.rawValue)
        defaults.set(p.manualResetDate, forKey: Key.manualResetDate.rawValue)
        defaults.set(p.claudeCodePath, forKey: Key.claudeCodePath.rawValue)
    }

    // Convenience mutators to avoid full-struct replacement at call sites
    func update(_ block: (inout AppPreferences) -> Void) {
        var p = preferences
        block(&p)
        preferences = p
    }
}
