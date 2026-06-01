import Foundation

// MARK: - JSONL record shapes (only fields we need)

private struct AssistantMessage: Decodable {
    let type: String
    let message: MessageBody?
    let timestamp: String?
}

private struct MessageBody: Decodable {
    let role: String?
    let usage: TokenUsage?
    let costUSD: Double?
}

private struct TokenUsage: Decodable {
    let input_tokens: Int?
    let output_tokens: Int?
    let cache_creation_input_tokens: Int?
    let cache_read_input_tokens: Int?
}

// MARK: - Data source

final class ClaudeCodeDataSource: UsageDataSource {
    let name = "Claude Code (Local)"

    private let projectsPath: String
    private let windowHours: Double = 5.0   // Claude Code uses ~5-hour rolling windows

    init(projectsPath: String = "~/.claude/projects") {
        self.projectsPath = (projectsPath as NSString).expandingTildeInPath
    }

    func fetch() async throws -> UsageData {
        let windowStart = Date().addingTimeInterval(-windowHours * 3600)
        let resetDate = windowStart.addingTimeInterval(windowHours * 3600 * 2) // estimate next window

        let (usedTokens, totalCost) = try await aggregateUsage(since: windowStart)

        // We don't know the plan limit, so we ask the caller's prefs for it
        // Here we return raw token count; ViewModel will overlay the plan limit
        return UsageData(
            usedTokens: usedTokens,
            totalTokens: 0,
            resetDate: resetDate,
            lastUpdated: Date(),
            dataSource: .localEstimate
        )
    }

    /// Returns (totalTokens, totalCostUSD) for all messages after `since`
    func aggregateUsage(since windowStart: Date) async throws -> (tokens: Int, costUSD: Double) {
        let projectsURL = URL(fileURLWithPath: projectsPath)
        let fm = FileManager.default

        guard fm.fileExists(atPath: projectsURL.path) else {
            throw DataSourceError.pathNotFound(projectsPath)
        }

        // Walk all .jsonl files under ~/.claude/projects/**/*.jsonl
        let enumerator = fm.enumerator(
            at: projectsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        var totalTokens = 0
        var totalCost = 0.0
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "jsonl" else { continue }

            // Skip files not modified recently (optimisation: skip files older than window)
            if let attrs = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
               let modDate = attrs.contentModificationDate,
               modDate < windowStart.addingTimeInterval(-3600) {
                continue
            }

            let (t, c) = try parseJSONL(at: fileURL, since: windowStart, formatter: isoFormatter)
            totalTokens += t
            totalCost += c
        }

        return (totalTokens, totalCost)
    }

    // MARK: - File parsing

    private func parseJSONL(
        at url: URL,
        since windowStart: Date,
        formatter: ISO8601DateFormatter
    ) throws -> (tokens: Int, costUSD: Double) {
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else { return (0, 0.0) }

        var tokens = 0
        var cost = 0.0
        let decoder = JSONDecoder()

        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = line.data(using: .utf8),
                  let record = try? decoder.decode(AssistantMessage.self, from: lineData) else {
                continue
            }

            // Only count assistant messages (where usage is recorded)
            guard record.type == "assistant",
                  let message = record.message,
                  message.role == "assistant" else { continue }

            // Filter by timestamp when available
            if let ts = record.timestamp, let date = formatter.date(from: ts) {
                guard date >= windowStart else { continue }
            }

            if let usage = message.usage {
                tokens += (usage.input_tokens ?? 0)
                    + (usage.output_tokens ?? 0)
                    + (usage.cache_creation_input_tokens ?? 0)
            }

            cost += message.costUSD ?? 0.0
        }

        return (tokens, cost)
    }
}

// MARK: - Errors

enum DataSourceError: LocalizedError {
    case pathNotFound(String)
    case parseFailure(String)
    case noDataAvailable

    var errorDescription: String? {
        switch self {
        case .pathNotFound(let path): return "Path not found: \(path)"
        case .parseFailure(let msg):  return "Parse failure: \(msg)"
        case .noDataAvailable:        return "No data available yet. Start a Claude Code session first."
        }
    }
}
