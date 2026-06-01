import Foundation

protocol UsageDataSource {
    /// Fetch the current usage snapshot. Throws if data is unavailable.
    func fetch() async throws -> UsageData
    /// Human-readable name for diagnostics/UI.
    var name: String { get }
}
