import SwiftUI

/// Shown when the hook bridge is not yet installed.
/// Walks the user through the one-time setup.
struct OnboardingView: View {
    @ObservedObject var viewModel: UsageViewModel
    @State private var isInstalling = false
    @State private var installError: String?
    @State private var installSuccess = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            explanation
            Divider()
            scriptPreview
            Divider()
            actionRow
        }
        .padding(20)
        .frame(width: 360)
    }

    // MARK: - Sub-views

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.accentColor)
                Text("Claude Battery Setup")
                    .font(.headline)
            }
            Text("One-time hook installation required")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How it works")
                .font(.subheadline.bold())

            VStack(alignment: .leading, spacing: 6) {
                stepRow(n: 1, text: "Installs a small shell script at ~/.claude/statusline-bridge.sh")
                stepRow(n: 2, text: "Registers it in ~/.claude/settings.json as a statusLine hook")
                stepRow(n: 3, text: "Claude Code writes your real usage % to ~/.claude/usage-state.json after each request")
                stepRow(n: 4, text: "Claude Battery reads that file — same number as Claude Code's own limiter bar")
            }

            Text("This uses Claude Code's official statusLine mechanism — the same one used by the VS Code and JetBrains extensions.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
    }

    private var scriptPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What gets installed")
                .font(.subheadline.bold())

            VStack(alignment: .leading, spacing: 2) {
                fileRow(icon: "doc.text", path: "~/.claude/statusline-bridge.sh",
                        note: "Captures rate limit JSON from Claude Code")
                fileRow(icon: "gearshape", path: "~/.claude/settings.json",
                        note: "Adds statusLine entry (existing settings preserved)")
            }
        }
    }

    private var actionRow: some View {
        VStack(spacing: 8) {
            if installSuccess {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Setup complete! Make one Claude Code request to populate data.")
                        .font(.callout)
                }
            } else {
                if let err = installError {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.leading)
                }

                HStack {
                    Button("Install Bridge") {
                        Task { await install() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isInstalling)

                    if isInstalling {
                        ProgressView().scaleEffect(0.7)
                    }

                    Spacer()

                    Button("Use Manual Mode Instead") {
                        PreferencesManager.shared.update { $0.dataSource = .manual }
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Helpers

    private func stepRow(n: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n)")
                .font(.caption.bold())
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(Color.accentColor)
                .clipShape(Circle())
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fileRow(icon: String, path: String, note: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(path)
                    .font(.caption.monospaced())
                Text(note)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func install() async {
        isInstalling = true
        installError = nil
        do {
            try await viewModel.installBridge()
            installSuccess = true
        } catch {
            installError = "Installation failed: \(error.localizedDescription)"
        }
        isInstalling = false
    }
}
