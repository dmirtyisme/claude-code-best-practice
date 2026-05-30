import Foundation

enum DataSourceType: String, CaseIterable, Identifiable {
    /// Primary: reads the exact used_percentage from the Anthropic API response headers
    /// via a statusLine bridge hook installed in ~/.claude/settings.json.
    case hookBridge  = "hookBridge"

    /// Secondary analytics: aggregates token counts from ~/.claude/projects JSONL.
    /// Shows consumption history but NOT plan utilization percentage.
    case claudeCode  = "claudeCode"

    /// Fallback: user manually enters current usage and reset time.
    case manual      = "manual"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hookBridge: return "Claude Code (Real-time)"
        case .claudeCode: return "Local Analytics (Estimated)"
        case .manual:     return "Manual"
        }
    }

    var description: String {
        switch self {
        case .hookBridge:
            return "Reads the exact usage % from Claude Code — the same number shown in Claude's own limiter bar. Requires one-time hook setup."
        case .claudeCode:
            return "Aggregates tokens from ~/.claude project files. Shows consumption and burn rate but cannot show accurate plan limit %."
        case .manual:
            return "You enter your plan limit, current usage, and reset time. Always works, even offline."
        }
    }

    var isExactSource: Bool { self == .hookBridge || self == .manual }
}

enum DisplayMode: String, CaseIterable, Identifiable {
    case percentage     = "percentage"
    case countdown      = "countdown"
    case compact        = "compact"
    case smart          = "smart"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .percentage: return "Percentage"
        case .countdown:  return "Reset Countdown"
        case .compact:    return "Compact Status"
        case .smart:      return "Smart (Auto)"
        }
    }

    var example: String {
        switch self {
        case .percentage: return "🧠 72%"
        case .countdown:  return "⏳ 3h 42m"
        case .compact:    return "🟢"
        case .smart:      return "Auto-selects"
        }
    }
}

enum ClaudePlan: String, CaseIterable, Identifiable {
    case free    = "free"
    case pro     = "pro"
    case max5    = "max5"
    case max20   = "max20"
    case custom  = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .free:   return "Free"
        case .pro:    return "Pro"
        case .max5:   return "Max (5x)"
        case .max20:  return "Max (20x)"
        case .custom: return "Custom"
        }
    }

    // Approximate monthly token limits (very rough — Anthropic does not publish exact numbers)
    var approximateMonthlyTokens: Int {
        switch self {
        case .free:   return 100_000
        case .pro:    return 1_000_000
        case .max5:   return 5_000_000
        case .max20:  return 20_000_000
        case .custom: return 0
        }
    }

    // Approximate 5-hour rolling window tokens (Claude Code uses rolling windows)
    var approximateWindowTokens: Int {
        switch self {
        case .free:   return 10_000
        case .pro:    return 80_000
        case .max5:   return 400_000
        case .max20:  return 1_600_000
        case .custom: return 0
        }
    }
}

struct AppPreferences {
    var dataSource: DataSourceType = .hookBridge
    var displayMode: DisplayMode   = .smart
    var refreshInterval: TimeInterval = 60
    var launchAtLogin: Bool        = false
    var showPromptEstimates: Bool  = true

    // Manual mode settings
    var manualPlan: ClaudePlan     = .pro
    var manualCustomTokens: Int    = 1_000_000
    var manualUsedTokens: Int      = 0
    var manualResetDate: Date      = Date().addingTimeInterval(5 * 3600)

    // Claude Code mode settings
    var claudeCodePath: String = "~/.claude/projects"

    var effectiveTotalTokens: Int {
        if dataSource == .manual {
            return manualPlan == .custom ? manualCustomTokens : manualPlan.approximateWindowTokens
        }
        return manualPlan.approximateWindowTokens
    }
}
