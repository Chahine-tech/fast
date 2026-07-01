import SwiftUI

/// The live/last download reading — big monospace number on its own line
/// (so it never gets squeezed by the sparkline), moving-dots sparkline +
/// peak below it, styled after the `fast` CLI's own live display.
struct TestResultView: View {
    let state: SpeedTester.TestState
    let history: [Double]
    let peak: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(primarySpeed.formattedSpeed)
                .font(.system(.title, design: .monospaced, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if !history.isEmpty {
                SpeedSparklineView(history: history, peak: peak)
            }
        }
    }

    private var primarySpeed: Double {
        switch state {
        case .idle: return 0
        case .testingDownload(_, let speed): return speed
        case .testingUpload: return peak
        case .completed(let download, _, _): return download
        case .failed: return 0
        }
    }
}

/// Upload/ping + status line, shown once a full test has completed.
struct TestSummaryView: View {
    let state: SpeedTester.TestState

    var body: some View {
        switch state {
        case .idle:
            Text("Ready")
                .foregroundStyle(.tertiary)

        case .testingDownload:
            Text("Testing download…")
                .foregroundStyle(.secondary)

        case .testingUpload(_, let speed):
            Text("↑ \(speed.formattedSpeed)  ·  testing upload…")
                .foregroundStyle(.secondary)

        case .completed(_, let upload, let ping):
            Text("↑ \(upload.formattedSpeed)  ·  ↕ \(Int(ping)) ms")
                .foregroundStyle(.secondary)

        case .failed(let message):
            Text(message)
                .foregroundStyle(.red)
        }
    }
}
