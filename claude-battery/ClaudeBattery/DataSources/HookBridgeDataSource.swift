import Foundation

// MARK: - Bridge file schema

/// Mirrors the JSON written by ~/.claude/statusline-bridge.sh
private struct UsageStateFile: Decodable {
    struct Window: Decodable {
        let used_percentage: Double
        let resets_at: TimeInterval   // Unix epoch seconds
    }
    let five_hour: Window?
    let seven_day: Window?
    let updated_at: TimeInterval      // Unix epoch seconds
}

// MARK: - Data source

/// Reads usage data from the statusLine bridge file written by Claude Code hooks.
///
/// The bridge script is installed at ~/.claude/statusline-bridge.sh and configured
/// in ~/.claude/settings.json as:
///   { "statusLine": { "type": "command", "command": "~/.claude/statusline-bridge.sh" } }
///
/// The file is updated after every API call Claude Code makes, containing the exact
/// same used_percentage value Claude Code displays in its own usage bar, sourced from
/// the anthropic-ratelimit-unified-* HTTP response headers.
final class HookBridgeDataSource: UsageDataSource {
    let name = "Claude Code Hook Bridge"

    static let bridgeFilePath = "~/.claude/usage-state.json"
    static let bridgeScriptPath = "~/.claude/statusline-bridge.sh"

    // Data is considered stale after this many seconds — show "offline" state
    static let staleThresholdSeconds: TimeInterval = 3600

    private let stateFilePath: String

    init(stateFilePath: String = HookBridgeDataSource.bridgeFilePath) {
        self.stateFilePath = (stateFilePath as NSString).expandingTildeInPath
    }

    func fetch() async throws -> UsageData {
        guard FileManager.default.fileExists(atPath: stateFilePath) else {
            throw HookBridgeError.bridgeFileNotFound
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: stateFilePath))
        let state = try JSONDecoder().decode(UsageStateFile.self, from: data)

        let updatedAt = Date(timeIntervalSince1970: state.updated_at)
        let staleness = -updatedAt.timeIntervalSinceNow

        if staleness > Self.staleThresholdSeconds {
            throw HookBridgeError.staleData(ageSeconds: Int(staleness))
        }

        // Prefer five_hour; fall back to seven_day
        guard let window = state.five_hour ?? state.seven_day else {
            throw HookBridgeError.noWindowData
        }

        let resetDate = Date(timeIntervalSince1970: window.resets_at)

        return UsageData(
            usedTokens: Int(window.used_percentage * 1000),  // Synthetic — we only have %
            totalTokens: 100_000,                             // Synthetic denominator
            resetDate: resetDate,
            lastUpdated: updatedAt,
            usedPercentageOverride: window.used_percentage / 100.0,
            dataSource: state.five_hour != nil ? .fiveHour : .sevenDay
        )
    }

    // MARK: - Setup helpers

    /// True when the bridge SCRIPT is installed — does not imply data has been received yet.
    var isBridgeInstalled: Bool {
        let scriptPath = (Self.bridgeScriptPath as NSString).expandingTildeInPath
        return FileManager.default.fileExists(atPath: scriptPath)
    }

    var currentBridgeStatus: BridgeStatus {
        let scriptPath = (Self.bridgeScriptPath as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            return .notInstalled
        }
        guard FileManager.default.fileExists(atPath: stateFilePath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: stateFilePath)),
              let state = try? JSONDecoder().decode(UsageStateFile.self, from: data) else {
            return .waitingForData
        }
        let age = Int(-Date(timeIntervalSince1970: state.updated_at).timeIntervalSinceNow)
        return age > Int(Self.staleThresholdSeconds) ? .stale(ageSeconds: age) : .connected
    }

    static func installBridgeScript() throws {
        let claudeDir = ("~/.claude" as NSString).expandingTildeInPath
        try FileManager.default.createDirectory(atPath: claudeDir, withIntermediateDirectories: true)
        let scriptPath = (bridgeScriptPath as NSString).expandingTildeInPath
        let script = bridgeScriptContent
        try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)

        // Make executable
        var attrs = try FileManager.default.attributesOfItem(atPath: scriptPath)
        attrs[.posixPermissions] = 0o755
        try FileManager.default.setAttributes(attrs, ofItemAtPath: scriptPath)
    }

    static func addToClaudeSettings() throws {
        let settingsPath = ("~/.claude/settings.json" as NSString).expandingTildeInPath
        let settingsURL = URL(fileURLWithPath: settingsPath)

        var settings: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: settingsPath),
           let data = try? Data(contentsOf: settingsURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = existing
        }

        // Only add statusLine if not already configured
        if settings["statusLine"] == nil {
            settings["statusLine"] = ["type": "command", "command": "~/.claude/statusline-bridge.sh"]
        }

        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsURL)
    }

    // MARK: - Bridge script content

    static let bridgeScriptContent = """
    #!/bin/bash
    # Claude Battery bridge — writes rate limit state from Claude Code to a local file.
    # Installed at: ~/.claude/statusline-bridge.sh
    # Configured in ~/.claude/settings.json under "statusLine".

    input=$(cat)
    state_file="$HOME/.claude/usage-state.json"

    five_pct=$(echo "$input"   | jq -r '.rate_limits.five_hour.used_percentage // empty')
    five_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
    seven_pct=$(echo "$input"  | jq -r '.rate_limits.seven_day.used_percentage // empty')
    seven_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

    if [ -n "$five_pct" ] || [ -n "$seven_pct" ]; then
      now=$(date +%s)
      jq -n \\
        --argjson five_pct "${five_pct:-null}" \\
        --argjson five_reset "${five_reset:-null}" \\
        --argjson seven_pct "${seven_pct:-null}" \\
        --argjson seven_reset "${seven_reset:-null}" \\
        --argjson updated "$now" \\
        '{
          five_hour: (if $five_pct != null then {used_percentage: $five_pct, resets_at: $five_reset} else null end),
          seven_day: (if $seven_pct != null then {used_percentage: $seven_pct, resets_at: $seven_reset} else null end),
          updated_at: $updated
        }' > "$state_file"
    fi

    # Emit for Claude Code's own status line display
    if [ -n "$five_pct" ]; then
      printf "%.0f%%" "$five_pct"
    elif [ -n "$seven_pct" ]; then
      printf "7d:%.0f%%" "$seven_pct"
    fi
    """
}

// MARK: - Bridge status

enum BridgeStatus: Equatable {
    case notInstalled       // Script file not present — show onboarding
    case waitingForData     // Script installed, state file not yet written
    case connected          // State file present and fresh
    case stale(ageSeconds: Int)  // State file present but older than staleThreshold

    var isInstalled: Bool { self != .notInstalled }

    var statusLabel: String {
        switch self {
        case .notInstalled:   return "Not installed"
        case .waitingForData: return "Waiting for data"
        case .connected:      return "Connected"
        case .stale(let age):
            let h = age / 3600; let m = (age % 3600) / 60
            return h > 0 ? "Stale (\(h)h \(m)m)" : "Stale (\(m)m)"
        }
    }
}

// MARK: - Errors

enum HookBridgeError: LocalizedError {
    case bridgeFileNotFound
    case staleData(ageSeconds: Int)
    case noWindowData

    var errorDescription: String? {
        switch self {
        case .bridgeFileNotFound:
            return "Bridge file not found. Set up Claude Battery in Settings to install the hook."
        case .staleData(let age):
            let hours = age / 3600
            let mins = (age % 3600) / 60
            if hours > 0 { return "Data is \(hours)h \(mins)m old. Start a Claude Code session to refresh." }
            return "Data is \(mins)m old. Start a Claude Code session to refresh."
        case .noWindowData:
            return "No rate limit data available yet. Make one request in Claude Code to populate the data."
        }
    }
}
