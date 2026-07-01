import Foundation

/// Measures an HTTP transfer (download/upload) by tracking progress via
/// URLSession delegates — more reliable than iterating `URLSession.bytes`
/// byte by byte, which is far too slow to measure real throughput.
///
/// Returns the final byte count transferred, not a speed: the caller (which
/// knows the true start time across all parallel streams) should compute the
/// aggregate speed itself. Reporting live progress through a fire-and-forget
/// `Task` (as `SpeedTester` does) is fine for on-screen feedback, but it's
/// racy for the *final* number — this final byte count is the deterministic
/// source of truth for that.
enum TransferMeter {
    static func download(
        url: URL,
        progress: @escaping @Sendable (_ bytesTransferred: Int, _ speed: Double) -> Void
    ) async throws -> Int {
        let delegate = DownloadMeterDelegate(progress: progress)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        return try await withCheckedThrowingContinuation { continuation in
            delegate.completion = { result in continuation.resume(with: result) }
            session.dataTask(with: url).resume()
        }
    }

    static func upload(
        url: URL,
        data: Data,
        progress: @escaping @Sendable (_ bytesTransferred: Int, _ speed: Double) -> Void
    ) async throws -> Int {
        let delegate = UploadMeterDelegate(progress: progress)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        return try await withCheckedThrowingContinuation { continuation in
            delegate.completion = { result in continuation.resume(with: result) }
            session.uploadTask(with: request, from: data).resume()
        }
    }
}

private let progressInterval: TimeInterval = 0.15

struct HTTPStatusError: LocalizedError {
    let statusCode: Int
    var errorDescription: String? {
        statusCode == 429
            ? "Rate limited (429) — too many test requests, try again shortly."
            : "Server returned HTTP \(statusCode)."
    }
}

private final class DownloadMeterDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let progress: @Sendable (Int, Double) -> Void
    var completion: ((Result<Int, Error>) -> Void)?

    private var receivedBytes = 0
    private var startDate: Date?
    private var lastUpdate = Date()
    // Cancelling the task from didReceive(response:) makes didCompleteWithError
    // fire again right after — without this guard, `completion` (and the
    // checked continuation behind it) gets resumed twice, which is a fatal
    // "continuation misuse" crash.
    private var didComplete = false

    init(progress: @escaping @Sendable (Int, Double) -> Void) {
        self.progress = progress
    }

    private func complete(_ result: Result<Int, Error>) {
        guard !didComplete else { return }
        didComplete = true
        completion?(result)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        // A non-2xx response (e.g. 429 rate-limited) would otherwise just be
        // counted as "downloaded bytes" — a tiny error page reported as a
        // real, absurdly-slow result instead of a clear failure.
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            complete(.failure(HTTPStatusError(statusCode: http.statusCode)))
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if startDate == nil {
            startDate = Date()
            lastUpdate = startDate!
        }
        receivedBytes += data.count

        let now = Date()
        guard let start = startDate, now.timeIntervalSince(lastUpdate) > progressInterval else { return }
        let elapsed = now.timeIntervalSince(start)
        let speed = elapsed > 0 ? Double(receivedBytes) / elapsed : 0
        progress(receivedBytes, speed)
        lastUpdate = now
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            complete(.failure(error))
            return
        }
        let elapsed = startDate.map { Date().timeIntervalSince($0) } ?? 0
        let speed = elapsed > 0 ? Double(receivedBytes) / elapsed : 0
        // Always report the true final byte count, even if the transfer
        // finished faster than progressInterval and never triggered a
        // periodic update from didReceive.
        progress(receivedBytes, speed)
        complete(.success(receivedBytes))
    }
}

private final class UploadMeterDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let progress: @Sendable (Int, Double) -> Void
    var completion: ((Result<Int, Error>) -> Void)?

    private var startDate: Date?
    private var lastUpdate = Date()
    private var didComplete = false

    init(progress: @escaping @Sendable (Int, Double) -> Void) {
        self.progress = progress
    }

    private func complete(_ result: Result<Int, Error>) {
        guard !didComplete else { return }
        didComplete = true
        completion?(result)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        if startDate == nil {
            startDate = Date()
            lastUpdate = startDate!
        }

        let now = Date()
        guard let start = startDate, now.timeIntervalSince(lastUpdate) > progressInterval else { return }
        let elapsed = now.timeIntervalSince(start)
        let speed = elapsed > 0 ? Double(totalBytesSent) / elapsed : 0
        progress(Int(totalBytesSent), speed)
        lastUpdate = now
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            complete(.failure(error))
            return
        }
        let bytesSent = Int(task.countOfBytesSent)
        let elapsed = startDate.map { Date().timeIntervalSince($0) } ?? 0
        let speed = elapsed > 0 ? Double(bytesSent) / elapsed : 0
        // Same reasoning as the download side: guarantee a final progress
        // report so a fast upload stream isn't silently dropped from the total.
        progress(bytesSent, speed)
        complete(.success(bytesSent))
    }
}
