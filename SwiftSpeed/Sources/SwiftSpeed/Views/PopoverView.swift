import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @StateObject private var speedTester = SpeedTester()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TestResultView(
                state: speedTester.state,
                history: speedTester.downloadHistory,
                peak: speedTester.peakSpeed
            )
            .contentShape(Rectangle())
            .onTapGesture { startTest() }
            .help("Click to run a new test")

            TestSummaryView(state: speedTester.state)
                .font(.system(.caption, design: .monospaced))

            Divider()

            HStack {
                HStack(spacing: 5) {
                    Circle()
                        .fill(networkMonitor.isConnected ? Color.mint : Color.secondary)
                        .frame(width: 5, height: 5)
                    Text(networkMonitor.activeInterface)
                }

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 280)
        .onAppear {
            networkMonitor.start()
            if case .idle = speedTester.state {
                startTest()
            }
        }
    }

    /// Starts a fresh test — from a tap on the result area, or automatically
    /// when the popover first opens. No-op while a test is already running.
    private func startTest() {
        guard !speedTester.isRunning else { return }
        Task { await speedTester.runTest(isConnected: networkMonitor.isConnected) }
    }
}

#Preview {
    PopoverView()
        .environmentObject(NetworkMonitor())
}
