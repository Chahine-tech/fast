import Foundation

@MainActor
final class SpeedTester: ObservableObject {
    enum TestState: Equatable {
        case idle
        case testingDownload(progress: Double, currentSpeed: Double)
        case testingUpload(progress: Double, currentSpeed: Double)
        case completed(download: Double, upload: Double, ping: Double)
        case failed(String)
    }

    @Published private(set) var state: TestState = .idle

    // Live samples of the current/last download test, driving the sparkline —
    // this is the *test's own* throughput over time, not a separate passive
    // traffic monitor (mixing those two was the source of a lot of confusion).
    @Published private(set) var downloadHistory: [Double] = []
    @Published private(set) var peakSpeed: Double = 0

    private let historyLimit = 40

    // MenuBarExtra(.window) can re-trigger onAppear more than once per open,
    // which was firing two concurrent runTest() calls that stomped on each
    // other's state (one test's results overwriting the other's mid-flight).
    private var isTestActive = false

    var isRunning: Bool {
        switch state {
        case .testingDownload, .testingUpload: return true
        default: return false
        }
    }

    // A single TCP stream rarely saturates a fast connection (TCP slow-start,
    // window scaling limits). Real speed test tools use several parallel
    // streams — we mirror that with 4 concurrent transfers, summed together.
    private let parallelStreams = 4
    private let downloadByteCount = 80_000_000  // 80 MB total, 20 MB/stream
    private let uploadByteCount = 40_000_000    // 40 MB total, 10 MB/stream

    func runTest() async {
        guard !isTestActive else { return }
        isTestActive = true
        defer { isTestActive = false }

        downloadHistory = []
        peakSpeed = 0
        state = .testingDownload(progress: 0, currentSpeed: 0)

        async let pingResult = measurePing()
        let downloadSpeed = await measureDownload()

        guard !isFailed else { return }

        state = .testingUpload(progress: 0, currentSpeed: 0)
        let uploadSpeed = await measureUpload()

        guard !isFailed else { return }

        let ping = await pingResult
        state = .completed(download: downloadSpeed, upload: uploadSpeed, ping: ping)
    }

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    private func measurePing() async -> Double {
        let url = URL(string: "https://speed.cloudflare.com/cdn-cgi/trace")!
        let start = Date()
        _ = try? await URLSession.shared.data(from: url)
        return Date().timeIntervalSince(start) * 1000
    }

    private func measureDownload() async -> Double {
        let streamByteCount = downloadByteCount / parallelStreams
        let url = URL(string: "https://speed.cloudflare.com/__down?bytes=\(streamByteCount)")!
        let aggregator = TransferAggregator()
        let overallStart = Date()

        do {
            let streamTotals = try await withThrowingTaskGroup(of: Int.self) { group in
                for index in 0..<parallelStreams {
                    group.addTask {
                        try await TransferMeter.download(url: url) { bytes, _ in
                            Task {
                                let (total, speed) = await aggregator.record(index: index, bytes: bytes)
                                await MainActor.run { [weak self] in
                                    guard let self else { return }
                                    let progress = min(Double(total) / Double(self.downloadByteCount), 1.0)
                                    self.state = .testingDownload(progress: progress, currentSpeed: speed)
                                    self.downloadHistory.append(speed)
                                    if self.downloadHistory.count > self.historyLimit {
                                        self.downloadHistory.removeFirst()
                                    }
                                    self.peakSpeed = max(self.peakSpeed, speed)
                                }
                            }
                        }
                    }
                }
                var totals: [Int] = []
                for try await bytes in group { totals.append(bytes) }
                return totals
            }
            // The live progress/aggregator above is only for on-screen feedback;
            // the authoritative total comes from the task group's own return
            // values, which are guaranteed to reflect every byte actually
            // transferred (see TransferMeter's final-progress-report fix).
            let elapsed = max(Date().timeIntervalSince(overallStart), 0.001)
            return Double(streamTotals.reduce(0, +)) / elapsed
        } catch {
            state = .failed(error.localizedDescription)
            return 0
        }
    }

    private func measureUpload() async -> Double {
        let streamByteCount = uploadByteCount / parallelStreams
        let url = URL(string: "https://speed.cloudflare.com/__up")!
        let payload = Data(count: streamByteCount)
        let aggregator = TransferAggregator()
        let overallStart = Date()

        do {
            let streamTotals = try await withThrowingTaskGroup(of: Int.self) { group in
                for index in 0..<parallelStreams {
                    group.addTask {
                        try await TransferMeter.upload(url: url, data: payload) { bytes, _ in
                            Task {
                                let (total, speed) = await aggregator.record(index: index, bytes: bytes)
                                await MainActor.run { [weak self] in
                                    guard let self else { return }
                                    let progress = min(Double(total) / Double(self.uploadByteCount), 1.0)
                                    self.state = .testingUpload(progress: progress, currentSpeed: speed)
                                }
                            }
                        }
                    }
                }
                var totals: [Int] = []
                for try await bytes in group { totals.append(bytes) }
                return totals
            }
            let elapsed = max(Date().timeIntervalSince(overallStart), 0.001)
            return Double(streamTotals.reduce(0, +)) / elapsed
        } catch {
            state = .failed(error.localizedDescription)
            return 0
        }
    }
}

/// Combines the per-stream byte counts of several parallel transfers into a
/// live aggregate reading for on-screen progress. Not used for the final
/// number (see the task-group-based totals in measureDownload/measureUpload).
private actor TransferAggregator {
    private var bytesByStream: [Int: Int] = [:]
    private let startDate = Date()

    func record(index: Int, bytes: Int) -> (totalBytes: Int, speed: Double) {
        bytesByStream[index] = bytes
        let total = bytesByStream.values.reduce(0, +)
        let elapsed = max(Date().timeIntervalSince(startDate), 0.001)
        return (total, Double(total) / elapsed)
    }
}
