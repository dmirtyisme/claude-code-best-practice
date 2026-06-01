import SwiftUI

struct PopoverView: View {
    @ObservedObject var viewModel: UsageViewModel
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if PreferencesManager.shared.preferences.dataSource == .hookBridge {
                switch viewModel.bridgeStatus {
                case .notInstalled:
                    OnboardingView(viewModel: viewModel)
                case .waitingForData:
                    waitingForDataView
                case .stale:
                    // Show stale data if available, otherwise show the error
                    if let data = viewModel.usageData {
                        content(data: data)
                    } else {
                        bridgeErrorView
                    }
                case .connected:
                    if let data = viewModel.usageData {
                        content(data: data)
                    } else if viewModel.isLoading {
                        loadingView
                    } else {
                        bridgeErrorView
                    }
                }
            } else if let data = viewModel.usageData {
                content(data: data)
            } else if viewModel.isLoading {
                loadingView
            } else {
                emptyStateView
            }

            Divider()
            footer
        }
        .frame(width: 280)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(PreferencesManager.shared)
        }
    }

    // MARK: - Sub-views

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.secondary)
                Text("Claude Battery")
                    .font(.headline)
            }
            Spacer()
            Button {
                Task { await viewModel.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Refresh now")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func content(data: UsageData) -> some View {
        VStack(spacing: 14) {
            usageSection(data: data)
            Divider().padding(.horizontal, 16)
            resetSection(data: data)
            Divider().padding(.horizontal, 16)
            burnSection(data: data)
            // Prompt estimates are only meaningful for local-estimate sources (JSONL analytics)
            // and manual mode — bridge data uses a synthetic 100K denominator.
            let showEstimates = PreferencesManager.shared.preferences.showPromptEstimates
                && data.dataSource != .fiveHour
                && data.dataSource != .sevenDay
            if showEstimates {
                Divider().padding(.horizontal, 16)
                estimatesSection(data: data)
            }
        }
        .padding(.vertical, 14)
    }

    private func usageSection(data: UsageData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("Usage")
                Spacer()
                HStack(spacing: 3) {
                    Image(systemName: data.isExact ? "checkmark.seal.fill" : "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundColor(data.isExact ? .green : .orange)
                    Text(data.isExact ? data.windowLabel : "~Estimate")
                        .font(.caption2)
                        .foregroundColor(data.isExact ? .green : .orange)
                }
                .padding(.trailing, 16)
            }
            UsageGaugeView(percent: data.usagePercent, status: data.status)
                .padding(.horizontal, 16)
            HStack {
                statRow(label: "Used", value: "\(Int(data.usagePercent * 100))%")
                Spacer()
                statRow(label: "Remaining", value: "\(100 - Int(data.usagePercent * 100))%")
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(data.status.label)
                        .font(.caption.bold())
                        .foregroundColor(statusColor(data.status))
                }
            }
            .padding(.horizontal, 16)

            if case .stale(let age) = viewModel.bridgeStatus {
                HStack(spacing: 4) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text("Data is \(staleAgeString(age)) old — start a Claude Code session to refresh")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func resetSection(data: UsageData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Reset")
            HStack {
                statRow(label: "In", value: data.resetCountdownString)
                Spacer()
                statRow(label: "At", value: resetTimeString(data.resetDate))
            }
            .padding(.horizontal, 16)
        }
    }

    private func burnSection(data: UsageData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Burn Rate")
            HStack {
                Text(viewModel.burnRate.emoji)
                Text(viewModel.burnRate.label)
                    .font(.callout.bold())
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 16)
        }
    }

    private func estimatesSection(data: UsageData) -> some View {
        let est = data.promptEstimates
        return VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Estimated Prompts Left")
            HStack(spacing: 16) {
                estimateChip(label: "Small", count: est.smallRemaining)
                estimateChip(label: "Medium", count: est.mediumRemaining)
                estimateChip(label: "Large", count: est.largeRemaining)
            }
            .padding(.horizontal, 16)
        }
    }

    private var waitingForDataView: some View {
        VStack(spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("Waiting for Claude Code usage data")
                .font(.callout.bold())
                .multilineTextAlignment(.center)
            Text("Make one request in Claude Code to populate the usage bar.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
    }

    private var bridgeErrorView: some View {
        VStack(spacing: 8) {
            Image(systemName: "questionmark.circle")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text(viewModel.errorMessage ?? "No data yet")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
    }

    private var loadingView: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading…")
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "questionmark.circle")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text(viewModel.errorMessage ?? "No data yet")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
    }

    private var footer: some View {
        HStack {
            if let data = viewModel.usageData {
                Text("Updated \(relativeTime(data.lastUpdated))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Settings") { showSettings = true }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.accentColor)
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.bold())
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
    }

    private func statRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.callout.monospacedDigit())
        }
    }

    private func estimateChip(label: String, count: Int) -> some View {
        VStack(spacing: 2) {
            Text("~\(count)")
                .font(.callout.bold().monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }

    private func statusColor(_ status: UsageStatus) -> Color {
        switch status {
        case .safe:     return .green
        case .medium:   return .orange
        case .critical: return .red
        case .depleted: return .gray
        }
    }

    private func staleAgeString(_ age: Int) -> String {
        let h = age / 3600; let m = (age % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func resetTimeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }
}
