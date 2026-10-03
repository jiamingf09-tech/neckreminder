import Foundation

/// What else was going on while the user produced no input. All of it is observable on
/// macOS without reading screen content, audio or keystrokes.
public enum CallKind: String, Codable, Equatable {
    case none
    /// Microphone in use, no camera, no app keeping the display on: a phone / voice call.
    /// You don't need to look at the screen for that.
    case voice
    /// Microphone plus a meeting app keeping the display on (camera off, maybe screen sharing).
    case meeting
    /// Camera in use: a video call.
    case video
}

public struct PresenceContext: Codable, Equatable {
    /// Frontmost app's bundle identifier and name.
    public var appID: String?
    public var appName: String?
    /// A GUI app keeps the display awake (windowed or full-screen video, slideshow, call).
    public var videoPlaying: Bool
    /// A small always-on-top video window (picture in picture) is on screen.
    public var pictureInPicture: Bool
    /// Sound is playing but there is no video signal (music, podcast).
    public var audioOnly: Bool
    public var call: CallKind
    /// The frontmost app covers a whole display (presentation, full-screen video).
    public var frontmostFullscreen: Bool
    /// Share of the last ~5 minutes with key presses (0…1). Typing → writing; low → reading.
    public var recentTyping: Double
    /// Share of the last ~5 minutes with any input (0…1).
    public var recentInput: Double

    public init(appID: String? = nil, appName: String? = nil, videoPlaying: Bool = false,
                pictureInPicture: Bool = false, audioOnly: Bool = false, call: CallKind = .none,
                frontmostFullscreen: Bool = false, recentTyping: Double = 0, recentInput: Double = 0) {
        self.appID = appID
        self.appName = appName
        self.videoPlaying = videoPlaying
        self.pictureInPicture = pictureInPicture
        self.audioOnly = audioOnly
        self.call = call
        self.frontmostFullscreen = frontmostFullscreen
        self.recentTyping = recentTyping
        self.recentInput = recentInput
    }

    /// Merge what was seen during a silence: any video / call during it counts.
    public func merged(with other: PresenceContext) -> PresenceContext {
        var c = self
        c.videoPlaying = videoPlaying || other.videoPlaying
        c.pictureInPicture = pictureInPicture || other.pictureInPicture
        c.audioOnly = (audioOnly || other.audioOnly) && !c.videoPlaying && !c.pictureInPicture
        c.frontmostFullscreen = frontmostFullscreen || other.frontmostFullscreen
        let rank: [CallKind: Int] = [.none: 0, .voice: 1, .meeting: 2, .video: 3]
        if (rank[other.call] ?? 0) > (rank[call] ?? 0) { c.call = other.call }
        return c
    }
}

public enum PresenceLabel: String, Codable, Equatable {
    case present, away
}

public enum LabelSource: String, Codable, Equatable {
    /// The user answered the question or corrected the review timeline.
    case user
    /// The user reacted to the "still there?" hint by moving the mouse.
    case probe
    /// Inferred without asking (screen locked → away, continued scrolling → present…).
    case implicit

    var weight: Double {
        switch self {
        case .user: return 1.0
        case .probe: return 0.6
        case .implicit: return 0.35
        }
    }
}

/// One silence, what the context was, and (once known) whether the user was there.
public struct GapEpisode: Codable, Identifiable, Equatable {
    public var id: UUID
    public var gap: GapInfo
    public var context: PresenceContext
    public var label: PresenceLabel?
    public var source: LabelSource?
    /// Model probability that the user was present for the whole gap, before any answer.
    public var predicted: Double
    /// The question could not be shown at the time (presentation, relax session…).
    public var awaitingReview: Bool

    public init(id: UUID = UUID(), gap: GapInfo, context: PresenceContext, label: PresenceLabel? = nil,
                source: LabelSource? = nil, predicted: Double, awaitingReview: Bool = false) {
        self.id = id
        self.gap = gap
        self.context = context
        self.label = label
        self.source = source
        self.predicted = predicted
        self.awaitingReview = awaitingReview
    }

    /// What the tracker did, unless the user said otherwise.
    public var effectivePresent: Bool {
        if let label { return label == .present }
        return gap.countedAsPresent
    }
}

/// A small logistic-regression model of "is the user still at the computer after `t`
/// seconds without input, in this context?".
///
/// * It starts from a prior that reproduces the user's settings exactly (reading grace,
///   media grace), so before any feedback it behaves like the plain rules.
/// * Feedback moves *deltas* away from that prior, with L2 regularisation pulling them back,
///   so a handful of answers nudges it and many answers can change it a lot.
/// * Every app gets its own bias term: "no input for 10 minutes in PowerPoint" can mean
///   something different from the same silence in Finder.
/// * The model is refitted from the stored episodes (a few hundred at most), so it is
///   deterministic and changing a setting just changes the prior.
public struct PresenceModel: Equatable {
    public static let featureCount = 11
    /// Coefficient of log(t/60). Negative: the longer the silence, the less likely present.
    static let timeWeight = -2.0

    public var readingGrace: TimeInterval
    public var mediaGrace: TimeInterval
    public var minGrace: TimeInterval = 60
    public var maxGrace: TimeInterval = 60 * 60

    public private(set) var delta: [Double] = Array(repeating: 0, count: featureCount)
    public private(set) var appBias: [String: Double] = [:]
    public private(set) var trainedExamples = 0

    public init(readingGrace: TimeInterval, mediaGrace: TimeInterval) {
        self.readingGrace = max(60, readingGrace)
        self.mediaGrace = mediaGrace
    }

    // MARK: Features

    static func features(_ c: PresenceContext, t: TimeInterval) -> [Double] {
        [
            1,
            log(max(t, 30) / 60),
            c.videoPlaying ? 1 : 0,
            c.pictureInPicture ? 1 : 0,
            c.audioOnly ? 1 : 0,
            c.call == .video ? 1 : 0,
            c.call == .meeting ? 1 : 0,
            c.call == .voice ? 1 : 0,
            c.frontmostFullscreen ? 1 : 0,
            c.recentTyping,
            c.recentInput,
        ]
    }

    /// Weights that turn the user's settings into the same decisions the plain rules make.
    var prior: [Double] {
        let wt = Self.timeWeight
        let bias = -wt * log(readingGrace / 60)
        let mediaOffset = mediaGrace > readingGrace ? -wt * log(mediaGrace / 60) - bias : 0
        let videoCallOffset = mediaGrace > 0 ? -wt * log(max(mediaGrace, 45 * 60) / 60) - bias : 0
        return [
            bias,
            wt,
            mediaOffset,          // video playing
            mediaOffset,          // picture in picture
            0,                    // audio only: like reading
            videoCallOffset,      // video call
            mediaOffset,          // meeting with the camera off
            -0.3,                 // voice call: no need to look at the screen
            0.5,                  // full-screen front app
            0,                    // recent typing (learned)
            0,                    // recent input (learned)
        ]
    }

    var weights: [Double] {
        var w = zip(prior, delta).map { $0 + $1 }
        w[1] = min(w[1], -0.5) // time must keep lowering the probability
        return w
    }

    // MARK: Inference

    func logit(_ c: PresenceContext, t: TimeInterval) -> Double {
        let x = Self.features(c, t: t)
        var z = zip(weights, x).reduce(0) { $0 + $1.0 * $1.1 }
        if let app = c.appID { z += appBias[app] ?? 0 }
        return z
    }

    /// Probability the user is still at the computer after `t` seconds without input.
    public func probabilityPresent(_ c: PresenceContext, after t: TimeInterval) -> Double {
        1 / (1 + exp(-logit(c, t: t)))
    }

    /// Silence length at which the probability falls to `p` (clamped to min/max grace).
    public func silence(at p: Double, _ c: PresenceContext) -> TimeInterval {
        let target = log(p / (1 - p))
        let w = weights
        let zWithoutTime = logit(c, t: 60) // log(60/60) = 0, so this excludes the time term
        let logT = (target - zWithoutTime) / w[1]
        return min(maxGrace, max(minGrace, 60 * exp(logT)))
    }

    /// The grace period: after this long without input the user is considered away.
    public func grace(_ c: PresenceContext) -> TimeInterval { silence(at: 0.5, c) }

    // MARK: Training

    public mutating func fit(_ episodes: [GapEpisode], epochs: Int = 40) {
        delta = Array(repeating: 0, count: Self.featureCount)
        appBias = [:]
        var examples: [(PresenceContext, TimeInterval, Double, Double)] = []
        for e in episodes {
            guard let label = e.label, let source = e.source else { continue }
            let w = source.weight
            let t = e.gap.duration
            if label == .present {
                examples.append((e.context, t, 1, w))
                examples.append((e.context, t / 2, 1, w * 0.5))
            } else {
                examples.append((e.context, t, 0, w))
            }
        }
        trainedExamples = examples.count
        guard !examples.isEmpty else { return }

        let lr = 0.05
        let l2 = 0.02
        let l2App = 0.01
        let base = prior
        for _ in 0..<epochs {
            for (c, t, y, w) in examples {
                let x = Self.features(c, t: t)
                var z = 0.0
                for i in 0..<Self.featureCount { z += (base[i] + delta[i]) * x[i] }
                if let app = c.appID { z += appBias[app] ?? 0 }
                let p = 1 / (1 + exp(-z))
                let g = (y - p) * w
                // The time coefficient stays fixed: learning shifts *where* the threshold
                // is for a context, not how quickly confidence decays.
                for i in 0..<Self.featureCount where i != 1 {
                    delta[i] += lr * (g * x[i] - l2 * delta[i])
                }
                if let app = c.appID {
                    let b = appBias[app] ?? 0
                    appBias[app] = b + lr * (g - l2App * b)
                }
            }
        }
    }

    /// Share of user-labelled episodes the model (at the time) got right.
    public static func accuracy(_ episodes: [GapEpisode]) -> (correct: Int, total: Int) {
        let answered = episodes.filter { $0.source == .user && $0.label != nil }
        let correct = answered.filter { ($0.predicted >= 0.5) == ($0.label == .present) }.count
        return (correct, answered.count)
    }
}
