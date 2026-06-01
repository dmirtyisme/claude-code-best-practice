import SwiftUI

/// Horizontal progress bar with color-coded status
struct UsageGaugeView: View {
    let percent: Double   // 0.0–1.0
    let status: UsageStatus

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .frame(height: 8)

                RoundedRectangle(cornerRadius: 4)
                    .fill(barColor)
                    .frame(width: max(4, geo.size.width * clampedPercent), height: 8)
                    .animation(.easeInOut(duration: 0.4), value: percent)
            }
        }
        .frame(height: 8)
        .overlay(
            HStack {
                Spacer()
                Text("\(Int(clampedPercent * 100))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
                    .offset(y: -12)
            }
        )
        .padding(.top, 12)
    }

    private var clampedPercent: Double { min(1.0, max(0, percent)) }

    private var barColor: Color {
        switch status {
        case .safe:     return .green
        case .medium:   return .orange
        case .critical: return .red
        case .depleted: return .gray
        }
    }
}

// MARK: - Preview helper

#if DEBUG
struct UsageGaugeView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            UsageGaugeView(percent: 0.3, status: .safe)
            UsageGaugeView(percent: 0.75, status: .medium)
            UsageGaugeView(percent: 0.92, status: .critical)
        }
        .padding()
        .frame(width: 250)
    }
}
#endif
