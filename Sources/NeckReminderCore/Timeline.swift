import Foundation

public enum SegmentKind: String, Codable, Equatable, CaseIterable {
    /// Using the computer (input).
    case active
    /// No input but counted as use (reading / watching).
    case passive
    /// Away from the computer.
    case away
    /// Doing a relax routine.
    case relax
}

public struct TimelineSegment: Codable, Equatable {
    public var start: Date
    public var end: Date
    public var kind: SegmentKind

    public init(start: Date, end: Date, kind: SegmentKind) {
        self.start = start
        self.end = end
        self.kind = kind
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// A day-by-day record of what the tracker believed, rewritable after the fact
/// (a silence first shown as "reading" becomes "away" once the grace runs out, or the user
/// corrects it in the review page).
public struct Timeline: Codable, Equatable {
    public private(set) var segments: [TimelineSegment] = []

    public init(segments: [TimelineSegment] = []) {
        self.segments = segments.sorted { $0.start < $1.start }
    }

    /// Mark `[from, to)` as `kind`, overwriting whatever was recorded there.
    public mutating func record(_ kind: SegmentKind, from: Date, to: Date) {
        guard to > from else { return }
        var result: [TimelineSegment] = []
        result.reserveCapacity(segments.count + 2)
        for s in segments {
            if s.end <= from || s.start >= to {
                result.append(s)
                continue
            }
            if s.start < from { result.append(TimelineSegment(start: s.start, end: from, kind: s.kind)) }
            if s.end > to { result.append(TimelineSegment(start: to, end: s.end, kind: s.kind)) }
        }
        result.append(TimelineSegment(start: from, end: to, kind: kind))
        result.sort { $0.start < $1.start }
        segments = Self.merged(result)
    }

    /// Merge touching (or nearly touching) segments of the same kind.
    static func merged(_ list: [TimelineSegment], tolerance: TimeInterval = 15) -> [TimelineSegment] {
        var out: [TimelineSegment] = []
        for s in list where s.duration > 0 {
            if var last = out.last, last.kind == s.kind, s.start.timeIntervalSince(last.end) <= tolerance {
                last.end = max(last.end, s.end)
                out[out.count - 1] = last
            } else {
                out.append(s)
            }
        }
        return out
    }

    /// Segments clipped to one day.
    public func segments(on day: Date, calendar: Calendar = .current) -> [TimelineSegment] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return segments.compactMap { s in
            guard s.end > start, s.start < end else { return nil }
            return TimelineSegment(start: max(s.start, start), end: min(s.end, end), kind: s.kind)
        }
    }

    public mutating func prune(before date: Date) {
        segments.removeAll { $0.end < date }
    }
}
