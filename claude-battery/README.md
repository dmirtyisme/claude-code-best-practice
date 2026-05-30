# Claude Battery

A macOS menu bar app that shows your real Claude usage — the exact same percentage Claude Code shows in its own usage bar.

```
🟡 72%     ⏳ 3h 42m     🔴 High
```

---

## What it does

Claude Battery reads the rate-limit data that Claude Code already receives from Anthropic's API after every request, and displays it in your menu bar near the clock. When you're in a heavy coding session, you can glance up and see exactly how much of your 5-hour rolling window you've consumed — no guessing, no estimation.

The number shown matches Claude Code's own internal limiter bar precisely, because it comes from the same Anthropic API response headers.

---

## Why statusLine is the primary source

Claude Code's binary already receives `anthropic-ratelimit-unified-five_hour-utilization` and `anthropic-ratelimit-unified-five_hour-reset` response headers with every API call. It exposes these to external tools (VS Code extension, JetBrains extension, and any custom script) through the **statusLine** mechanism: a shell command configured in `~/.claude/settings.json` that receives a JSON payload containing:

```json
{
  "rate_limits": {
    "five_hour": { "used_percentage": 72.5, "resets_at": 1780200000 },
    "seven_day":  { "used_percentage": 45.0, "resets_at": 1780800000 }
  }
}
```

Claude Battery installs a small bridge script at `~/.claude/statusline-bridge.sh` that captures this payload and writes `~/.claude/usage-state.json`. The app polls that file.

**Alternative approaches and why they don't work:**

| Approach | Problem |
|---|---|
| JSONL token aggregation (`~/.claude/projects/**/*.jsonl`) | Gives consumption history but NOT plan utilization %. Anthropic does not expose plan limits locally, so any "X% of plan" computed from tokens is fabricated. |
| Manual entry | Always works but requires the user to keep it updated. Useful as a fallback. |
| Scraping Claude web UI | Requires credentials storage and brittle DOM parsing. |

---

## Data accuracy

| Field | Source | Accuracy |
|---|---|---|
| `used_percentage` (5h window) | Anthropic API response header | **Exact** — same number Claude Code shows |
| `used_percentage` (7-day window) | Anthropic API response header | **Exact** |
| `resets_at` | Anthropic API response header | **Exact** |
| JSONL token counts | `~/.claude/projects/**/*.jsonl` | Exact for consumption, not for plan % |
| Manual entry | User-supplied | As accurate as user input |

The UI shows a green `✓ 5h window` badge for exact data and an orange `⚠ ~Estimate` badge for JSONL-derived data.

---

## Setup (one-time)

1. Build and run Claude Battery (see **Building** below).
2. Click the menu bar icon — the **Setup** screen appears automatically.
3. Click **Install Bridge**. Claude Battery will:
   - Write `~/.claude/statusline-bridge.sh` (the hook script)
   - Add a `statusLine` entry to `~/.claude/settings.json`
4. Make **one request** in Claude Code. The bridge script runs automatically and writes `~/.claude/usage-state.json`.
5. Claude Battery reads the file and shows your real usage.

The app checks for the bridge script on every refresh. If `~/.claude/statusline-bridge.sh` exists, setup is complete; if `~/.claude/usage-state.json` doesn't exist yet, the app shows "Waiting for Claude Code usage data" until you make a request.

### What gets installed

```
~/.claude/statusline-bridge.sh   # Shell script (chmod 755)
~/.claude/settings.json          # Modified to add "statusLine" key (existing settings preserved)
~/.claude/usage-state.json       # Written by the script after each Claude Code request
```

### Manual setup (without the GUI)

```bash
# 1. Create the bridge script
cat > ~/.claude/statusline-bridge.sh << 'EOF'
#!/bin/bash
input=$(cat)
state_file="$HOME/.claude/usage-state.json"
five_pct=$(echo "$input"   | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
seven_pct=$(echo "$input"  | jq -r '.rate_limits.seven_day.used_percentage // empty')
seven_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
if [ -n "$five_pct" ] || [ -n "$seven_pct" ]; then
  now=$(date +%s)
  jq -n \
    --argjson five_pct "${five_pct:-null}"     \
    --argjson five_reset "${five_reset:-null}" \
    --argjson seven_pct "${seven_pct:-null}"   \
    --argjson seven_reset "${seven_reset:-null}" \
    --argjson updated "$now" \
    '{five_hour:(if $five_pct!=null then {used_percentage:$five_pct,resets_at:$five_reset} else null end),seven_day:(if $seven_pct!=null then {used_percentage:$seven_pct,resets_at:$seven_reset} else null end),updated_at:$updated}' > "$state_file"
fi
EOF
chmod 755 ~/.claude/statusline-bridge.sh

# 2. Add to Claude Code settings (preserves existing settings)
jq '. + {"statusLine": {"type": "command", "command": "~/.claude/statusline-bridge.sh"}}' \
  ~/.claude/settings.json > /tmp/settings_tmp.json && mv /tmp/settings_tmp.json ~/.claude/settings.json
```

**Requirement:** `jq` must be installed (`brew install jq`).

---

## Architecture

```
ClaudeBattery/
├── ClaudeBatteryApp.swift          # @main entry, NSApplicationDelegateAdaptor
├── AppDelegate.swift               # NSApp setup, launch-at-login
├── MenuBarManager.swift            # NSStatusItem, NSPopover, live title updates
│
├── Models/
│   ├── UsageData.swift             # Core value types: UsageData, UsageStatus, BurnRate, BurnRateCalculator
│   └── AppPreferences.swift        # DataSourceType, DisplayMode, ClaudePlan enums
│
├── DataSources/
│   ├── DataSourceProtocol.swift    # UsageDataSource protocol
│   ├── HookBridgeDataSource.swift  # Primary: reads ~/.claude/usage-state.json (exact %)
│   ├── ClaudeCodeDataSource.swift  # Secondary: parses ~/.claude/projects/**/*.jsonl (token analytics)
│   └── ManualDataSource.swift      # Fallback: reads from AppPreferences (user-entered)
│
├── ViewModels/
│   └── UsageViewModel.swift        # @MainActor ObservableObject, BridgeStatus, refresh timer
│
├── Views/
│   ├── PopoverView.swift           # Main popover with bridge-status-aware routing
│   ├── OnboardingView.swift        # First-run setup flow for bridge installation
│   ├── UsageGaugeView.swift        # Horizontal progress bar with status colour
│   └── SettingsView.swift          # Data source, display mode, manual input
│
└── Persistence/
    └── PreferencesManager.swift    # UserDefaults wrapper, @Published preferences
```

### Bridge status state machine

```
.notInstalled  ──[Install Bridge]──▶  .waitingForData  ──[first API call]──▶  .connected
                                                                                    │
                                                                                    ▼
                                                              .stale(ageSeconds)  ◀──── (no Claude Code activity > 1h)
```

---

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

---

## Known limitations

1. **Data goes stale when Claude Code is idle.** The bridge script only runs when Claude Code makes an API call. If you haven't used Claude Code for over an hour, the app shows a stale indicator. This is by design — showing old data honestly is better than showing a fake estimate.

2. **`jq` required.** The bridge script uses `jq` to parse JSON. Install via `brew install jq`.

3. **No plan total exposed.** Anthropic does not expose the plan's absolute token limit in the headers — only the utilization percentage and reset time. The app therefore shows `72%` and `28% remaining`, never `576K / 800K tokens`. This is intentional.

4. **App Sandbox disabled.** Required to read `~/.claude/`. Not suitable for App Store distribution without entitlement changes.

5. **macOS 13+ only.** Uses `SMAppService` for launch-at-login.

---

## Privacy

- Reads only local files under `~/.claude/`
- No network requests
- No telemetry
- No credentials stored
- The bridge script writes only to `~/.claude/usage-state.json` — nothing else
