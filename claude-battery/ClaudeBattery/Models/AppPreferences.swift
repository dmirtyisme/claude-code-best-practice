import Foundation

enum DataSourceType: String, CaseIterable, Identifiable {
    case claudeCode = "claudeCode"
    case manual     = "manual"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code (Local)"
        case .manual:     return "Manual"
        }
    }

    var description: String {
        switch self {
        case .claudeCode:
            return "Reads token usage from ~/.claude/projects JSONL files. Shows today's consumption."
        case .manual:
            return "You enter your plan limit, current usage, and reset time manually."
        }
    }
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
    var dataSource: DataSourceType = .claudeCode
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
