import Foundation

/// Decides whether a Bluetooth headset disconnected because its wearer walked out of range.
///
/// macOS does not tell apps *why* a device disconnected. The signal strength in the
/// minute before the disconnect does: walking away shows a steady decline into the
/// noise floor before the link times out, while putting AirPods back in the case,
/// switching them to the iPhone or disconnecting by hand drops a strong link abruptly.
public enum ProximityAnalyzer {
    public struct Reading: Equatable {
        public var date: Date
        public var rssi: Int
        public init(date: Date, rssi: Int) {
            self.date = date
            self.rssi = rssi
        }
    }

    /// Weakest signal right before the disconnect for it to count as "out of range".
    public static let farThreshold = -72
    /// Minimum decline from the earlier baseline.
    public static let minimumDrop = 10

    /// When the user started walking away, or nil if the disconnect looks deliberate.
    public static func walkAwayStart(_ readings: [Reading], disconnectedAt: Date) -> Date? {
        let window = readings
            .filter { disconnectedAt.timeIntervalSince($0.date) <= 120 && $0.date <= disconnectedAt }
            .sorted { $0.date < $1.date }
        guard window.count >= 4, let last = window.last,
              disconnectedAt.timeIntervalSince(last.date) <= 20 else { return nil }

        let recent = window.suffix(3).map(\.rssi)
        let recentLevel = recent.reduce(0, +) / recent.count
        guard recentLevel <= farThreshold else { return nil }

        let early = window.prefix(max(2, window.count / 3)).map(\.rssi).sorted()
        let baseline = early[early.count / 2]
        guard baseline - recentLevel >= minimumDrop else { return nil }

        // Start of the decline: the earliest reading after which every reading stays
        // clearly below the baseline.
        var start = last.date
        for reading in window.reversed() {
            if reading.rssi <= baseline - 6 { start = reading.date } else { break }
        }
        return start
    }
}
