import Foundation

extension Double {
    /// `self` in bytes/s → human-readable string in bits/s (bps/Kbps/Mbps/Gbps).
    var formattedSpeed: String {
        let bitsPerSecond = self * 8
        switch bitsPerSecond {
        case ..<1_000:
            return String(format: "%.0f bps", bitsPerSecond)
        case ..<1_000_000:
            return String(format: "%.1f Kbps", bitsPerSecond / 1_000)
        case ..<1_000_000_000:
            return String(format: "%.1f Mbps", bitsPerSecond / 1_000_000)
        default:
            return String(format: "%.2f Gbps", bitsPerSecond / 1_000_000_000)
        }
    }
}
