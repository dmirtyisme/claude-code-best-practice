# Claude Battery

A minimal macOS menu bar app that shows Claude usage directly in the top menu bar — like a battery indicator for your AI.

```
🟢 72%     ⏳ 3h 42m     🔴 Low
```

## Architecture

```
ClaudeBattery/
├── ClaudeBatteryApp.swift          # @main entry, NSApplicationDelegateAdaptor
├── AppDelegate.swift               # NSApp setup, launch-at-login
├── MenuBarManager.swift            # NSStatusItem, NSPopover, live title updates
│
├── Models/
│   ├── UsageData.swift             # Core value types: UsageData, UsageStatus, BurnRate
│   └── AppPreferences.swift        # DataSourceType, DisplayMode, ClaudePlan enums
│
├── DataSources/
│   ├── DataSourceProtocol.swift    # UsageDataSource protocol
│   ├── ClaudeCodeDataSource.swift  # Parses ~/.claude/projects/**/*.jsonl
│   └── ManualDataSource.swift      # Reads from AppPreferences (manual mode)
│
├── ViewModels/
│   └── UsageViewModel.swift        # @MainActor ObservableObject, refresh timer, burn rate
│
├── Views/
│   ├── PopoverView.swift           # Main popover: usage, reset, burn rate, estimates
│   ├── UsageGaugeView.swift        # Horizontal progress bar with status color
│   └── SettingsView.swift          # Data source, display mode, manual input
│
└── Persistence/
    └── PreferencesManager.swift    # UserDefaults wrapper, @Published preferences
```

## Data Sources

### Claude Code (Local) — Recommended
Reads `~/.claude/projects/**/*.jsonl` — the same files Claude Code writes every session.
Each assistant message records `input_tokens`, `output_tokens`, and `costUSD`.
The app aggregates tokens within a configurable rolling window (default: 5 hours,
matching Claude Code's rate-limit window).

**Limitation:** Claude does not expose plan-level quotas locally. The app uses approximate
token budgets per plan (Pro ≈ 80K/5h, Max 5x ≈ 400K/5h) as the denominator.
These are estimates — treat the percentage as directionally correct, not exact.

### Manual Mode
You enter your plan, token limit, current usage, and reset time.
Works offline, fully accurate when you update it.

## Building

Requirements:
- Xcode 15+
- macOS 13.0 deployment target

Steps:
1. Open Xcode → File → New → Project → macOS → App
2. Product Name: `ClaudeBattery`, Bundle ID: `com.yourname.claude-battery`
3. Interface: SwiftUI, Life Cycle: AppKit App Delegate
4. Add all `.swift` files from `ClaudeBattery/` to the target
5. In `Info.plist`: set `LSUIElement = YES` (hides Dock icon)
6. In Signing & Capabilities: **disable App Sandbox** (required to read `~/.claude/`)
7. Set deployment target to macOS 13.0
8. Build and Run (⌘R)

## Roadmap

| Phase | Feature |
|---|---|
| MVP | Claude Code JSONL parsing + Manual mode + Popover UI |
| v1.1 | Notifications at 80% / 95% usage |
| v1.2 | Weekly/daily burn charts (SwiftUI Charts) |
| v1.3 | Claude web usage via browser extension bridge |
| v2.0 | Multiple account support |

## Privacy

- Reads only local files under `~/.claude/`
- No network requests
- No telemetry
- No credentials stored

## Known Limitations

1. **No official API**: Anthropic does not provide a public usage API. Plan limits
   are approximated from public plan descriptions.
2. **Token window ambiguity**: Claude Code rate limits are rolling windows, not
   calendar month limits. The 5-hour window is an approximation.
3. **App Sandbox disabled**: Required to read `~/.claude/`. Not suitable for
   App Store distribution without entitlement changes.
