import Foundation

// MARK: - Core domain models

enum UsageStatus {
    case safe       // < 70%
    case medium     // 70–90%
    case critical   // 90–95%
    case depleted   // > 95%

    var label: String {
        switch self {
        case .safe: return "Safe"
        case .medium: return "Medium"
        case .critical: return "Critical"
        case .depleted: return "Depleted"
        }
    }

    var emoji: String {
        switch self {
        case .safe: return "🟢"
        case .medium: return "🟡"
        case .critical: return "🔴"
        case .depleted: return "⛔"
        }
    }

    var colorHex: String {
        switch self {
        case .safe: return "#34C759"
        case .medium: return "#FF9500"
        case .critical: return "#FF3B30"
        case .depleted: return "#8E8E93"
        }
    }
}

enum BurnRate {
    case low
    case normal
    case high

    var label: String {
        switch self {
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        }
    }

    var emoji: String {
        switch self {
        case .low: return "🐢"
        case .normal: return "⚡"
        case .high: return "🔥"
        }
    }
}

struct PromptEstimates {
    let smallRemaining: Int   // ~5k tokens
    let mediumRemaining: Int  // ~25k tokens
    let largeRemaining: Int   // ~100k tokens

    static let smallTokens  = 5_000
    static let mediumTokens = 25_000
    static let largeTokens  = 100_000

    init(remainingTokens: Int) {
        smallRemaining  = remainingTokens / Self.smallTokens
        mediumRemaining = remainingTokens / Self.mediumTokens
        largeRemaining  = remainingTokens / Self.largeTokens
    }
}

struct UsageData {
    let usedTokens: Int
    let totalTokens: Int
    let resetDate: Date
    let lastUpdated: Date

    var remainingTokens: Int { max(0, totalTokens - usedTokens) }
    var usagePercent: Double { totalTokens > 0 ? Double(usedTokens) / Double(totalTokens) : 0.0 }

    var status: UsageStatus {
        switch usagePercent {
        case ..<0.70: return .safe
        case 0.70..<0.90: return .medium
        case 0.90..<0.95: return .critical
        default: return .depleted
        }
    }

    var timeUntilReset: TimeInterval { max(0, resetDate.timeIntervalSinceNow) }

    var promptEstimates: PromptEstimates { PromptEstimates(remainingTokens: remainingTokens) }

    var resetCountdownString: String {
        let seconds = Int(timeUntilReset)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    // Placeholder with manual plan defaults
    static func placeholder(planTokens: Int = 1_000_000) -> UsageData {
        UsageData(
            usedTokens: 0,
            totalTokens: planTokens,
            resetDate: Calendar.current.date(byAdding: .hour, value: 5, to: Date())!,
            lastUpdated: Date()
        )
    }
}

// MARK: - Burn rate computed over a snapshot window

struct BurnRateCalculator {
    private var snapshots: [(date: Date, tokens: Int)] = []
    private let windowSeconds: Double = 3600 // 1 hour

    mutating func record(tokens: Int, at date: Date = Date()) {
        snapshots.append((date, tokens))
        // Prune old snapshots
        let cutoff = date.addingTimeInterval(-windowSeconds * 3)
        snapshots.removeAll { $0.date < cutoff }
    }

    func burnRate(currentUsed: Int) -> BurnRate {
        guard snapshots.count >= 2,
              let earliest = snapshots.first else { return .normal }

        let elapsed = Date().timeIntervalSince(earliest.date)
        guard elapsed > 0 else { return .normal }

        let tokenDelta = currentUsed - earliest.tokens
        let tokensPerHour = Double(tokenDelta) / (elapsed / 3600)

        switch tokensPerHour {
        case ..<10_000: return .low
        case 10_000..<50_000: return .normal
        default: return .high
        }
    }
}
