import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var prefsManager: PreferencesManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Claude Battery — Settings")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.return)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    dataSourceSection
                    Divider()
                    displaySection
                    Divider()
                    manualModeSection
                    Divider()
                    behaviourSection
                }
                .padding(16)
            }
        }
        .frame(width: 420, height: 560)
    }

    // MARK: - Data Source

    private var dataSourceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Data Source")

            ForEach(DataSourceType.allCases) { source in
                dataSourceRow(source)
            }

            if prefsManager.preferences.dataSource == .claudeCode {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Projects path")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("~/.claude/projects", text: claudeCodePathBinding)
                        .textFieldStyle(.roundedBorder)
                        .font(.callout.monospaced())
                }
            }

            Text("Plan (used to estimate limit for Claude Code mode)")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)

            Picker("Plan", selection: manualPlanBinding) {
                ForEach(ClaudePlan.allCases) { plan in
                    Text(plan.displayName).tag(plan)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            if prefsManager.preferences.manualPlan == .custom {
                HStack {
                    Text("Custom limit (tokens)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    TextField("1000000", value: customTokensBinding, formatter: NumberFormatter())
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private func dataSourceRow(_ source: DataSourceType) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: prefsManager.preferences.dataSource == source
                  ? "checkmark.circle.fill" : "circle")
                .foregroundColor(prefsManager.preferences.dataSource == source ? .accentColor : .secondary)
                .font(.body)
                .onTapGesture {
                    prefsManager.update { $0.dataSource = source }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(source.displayName)
                    .font(.callout.bold())
                Text(source.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            prefsManager.update { $0.dataSource = source }
        }
    }

    // MARK: - Display Mode

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Menu Bar Display")
            ForEach(DisplayMode.allCases) { mode in
                HStack {
                    Image(systemName: prefsManager.preferences.displayMode == mode
                          ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(prefsManager.preferences.displayMode == mode ? .accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(mode.displayName).font(.callout)
                        Text(mode.example)
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    prefsManager.update { $0.displayMode = mode }
                }
            }
        }
    }

    // MARK: - Manual Mode

    private var manualModeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Manual Usage Override")
            Text("Set your current token usage manually. Only used when Data Source is set to Manual.")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Text("Used tokens")
                    .font(.callout)
                Spacer()
                TextField("0", value: manualUsedBinding, formatter: NumberFormatter())
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .multilineTextAlignment(.trailing)
            }

            HStack {
                Text("Reset date/time")
                    .font(.callout)
                Spacer()
                DatePicker("", selection: manualResetDateBinding, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
            }
        }
    }

    // MARK: - Behaviour

    private var behaviourSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Behaviour")

            HStack {
                Text("Refresh interval")
                    .font(.callout)
                Spacer()
                Picker("", selection: refreshIntervalBinding) {
                    Text("30s").tag(30.0)
                    Text("1m").tag(60.0)
                    Text("2m").tag(120.0)
                    Text("5m").tag(300.0)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 180)
            }

            Toggle("Show prompt estimates", isOn: showEstimatesBinding)
                .font(.callout)

            Toggle("Launch at login", isOn: launchAtLoginBinding)
                .font(.callout)
                .onChange(of: prefsManager.preferences.launchAtLogin) { newValue in
                    setLaunchAtLogin(newValue)
                }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.bold())
    }

    // MARK: - Bindings

    private var claudeCodePathBinding: Binding<String> {
        Binding(
            get: { prefsManager.preferences.claudeCodePath },
            set: { newValue in prefsManager.update { $0.claudeCodePath = newValue } }
        )
    }

    private var manualPlanBinding: Binding<ClaudePlan> {
        Binding(
            get: { prefsManager.preferences.manualPlan },
            set: { newValue in prefsManager.update { $0.manualPlan = newValue } }
        )
    }

    private var customTokensBinding: Binding<Int> {
        Binding(
            get: { prefsManager.preferences.manualCustomTokens },
            set: { newValue in prefsManager.update { $0.manualCustomTokens = newValue } }
        )
    }

    private var manualUsedBinding: Binding<Int> {
        Binding(
            get: { prefsManager.preferences.manualUsedTokens },
            set: { newValue in prefsManager.update { $0.manualUsedTokens = newValue } }
        )
    }

    private var manualResetDateBinding: Binding<Date> {
        Binding(
            get: { prefsManager.preferences.manualResetDate },
            set: { newValue in prefsManager.update { $0.manualResetDate = newValue } }
        )
    }

    private var refreshIntervalBinding: Binding<Double> {
        Binding(
            get: { prefsManager.preferences.refreshInterval },
            set: { newValue in prefsManager.update { $0.refreshInterval = newValue } }
        )
    }

    private var showEstimatesBinding: Binding<Bool> {
        Binding(
            get: { prefsManager.preferences.showPromptEstimates },
            set: { newValue in prefsManager.update { $0.showPromptEstimates = newValue } }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { prefsManager.preferences.launchAtLogin },
            set: { newValue in prefsManager.update { $0.launchAtLogin = newValue } }
        )
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        // SMAppService requires macOS 13+; handled in AppDelegate for full implementation
        // Placeholder — register via SMAppService.mainApp in AppDelegate
    }
}
