import Foundation

/// Reads usage from user-supplied values stored in AppPreferences.
final class ManualDataSource: UsageDataSource {
    let name = "Manual"

    private let prefsManager: PreferencesManager

    init(prefsManager: PreferencesManager = .shared) {
        self.prefsManager = prefsManager
    }

    func fetch() async throws -> UsageData {
        let p = prefsManager.preferences
        let total = p.manualPlan == .custom
            ? p.manualCustomTokens
            : p.manualPlan.approximateWindowTokens

        return UsageData(
            usedTokens: p.manualUsedTokens,
            totalTokens: total,
            resetDate: p.manualResetDate,
            lastUpdated: Date(),
            dataSource: .manual
        )
    }
}
