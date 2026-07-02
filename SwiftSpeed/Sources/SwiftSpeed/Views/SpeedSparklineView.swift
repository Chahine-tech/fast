import SwiftUI

/// Dot-matrix bar sparkline, closely modeled on the `fast` CLI's live display:
/// each sample is a 2-dot-wide column, filled bottom-up with rows proportional
/// to its value — a "block" texture rather than a single-pixel line.
struct SpeedSparklineView: View {
    let history: [Double]
    let peak: Double
    var tint: Color = .mint
    var showPeakLabel: Bool = true

    private let maxColumns = 16
    private let maxRows = 4
    private let dotSize: CGFloat = 3
    private let dotGap: CGFloat = 2
    private let columnGap: CGFloat = 3

    var body: some View {
        HStack(spacing: 10) {
            Canvas { context, size in
                guard !history.isEmpty else { return }
                let maxValue = max(history.max() ?? 1, 1)
                let samples = Array(history.suffix(maxColumns))
                let startIndex = maxColumns - samples.count
                // Derive the column pitch from the canvas's *actual* width so
                // columns always land inside the visible area, regardless of
                // how much space the popover ends up giving this view.
                let columnPitch = size.width / CGFloat(maxColumns)
                let dotWidth = min(dotSize, columnPitch * 0.4)
                let rowPitch = dotSize + dotGap

                for (offset, value) in samples.enumerated() {
                    let index = startIndex + offset
                    let columnX = CGFloat(index) * columnPitch
                    let normalized = min(value / maxValue, 1.0)
                    let filledRows = max(1, Int((normalized * Double(maxRows)).rounded()))

                    for row in 0..<filledRows {
                        let y = size.height - CGFloat(row + 1) * rowPitch
                        for col in 0..<2 {
                            let x = columnX + CGFloat(col) * (dotWidth + 1)
                            let rect = CGRect(x: x, y: y, width: dotWidth, height: dotWidth)
                            context.fill(Path(ellipseIn: rect), with: .color(tint.opacity(0.5 + 0.5 * normalized)))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .animation(.smooth(duration: 0.25), value: history)

            if showPeakLabel {
                Text("peak \(peak.formattedSpeed)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }
        }
    }
}

#Preview {
    SpeedSparklineView(history: (0..<16).map { _ in Double.random(in: 1_000_000...50_000_000) }, peak: 42_000_000)
        .padding()
        .frame(width: 280)
}
