import Foundation

/// Builds varied routines so it isn't always the same handful of exercises.
///
/// Each length has a template — a sequence of slots like "warm-up 30 s, neck stretch 50 s,
/// upper back 40 s…" — designed by the same logic as the classic routines (warm up, mobilise,
/// stretch, strengthen, open the upper back, finish calmly). Every slot is filled with a
/// matching exercise, preferring the ones done least recently, with a little randomness so
/// two sessions in a row differ. Lengths stay exact.
public enum RoutineGenerator {
    public struct Slot: Equatable {
        public var role: ExerciseRole
        /// Total seconds (split over both sides for bilateral exercises).
        public var seconds: Int
        public var standingAllowed: Bool

        public init(_ role: ExerciseRole, _ seconds: Int, standing: Bool = false) {
            self.role = role
            self.seconds = seconds
            self.standingAllowed = standing
        }
    }

    public static let lengths = [2, 5, 10, 15, 30]

    public static func template(minutes: Int) -> [Slot] {
        switch minutes {
        case 2:
            return [Slot(.neckStrength, 30), Slot(.neckStretch, 40), Slot(.shoulder, 20), Slot(.upperBack, 30)]
        case 5:
            return [Slot(.warmup, 30), Slot(.neckStrength, 40), Slot(.neckStretch, 50), Slot(.neckStretch, 50),
                    Slot(.neckMobility, 30), Slot(.shoulder, 30), Slot(.upperBack, 40), Slot(.finish, 30)]
        case 10:
            return [Slot(.warmup, 40), Slot(.neckMobility, 30), Slot(.neckStrength, 50), Slot(.neckStretch, 60),
                    Slot(.neckStretch, 60), Slot(.neckStrength, 60), Slot(.shoulder, 40), Slot(.upperBack, 50),
                    Slot(.upperBack, 50, standing: true), Slot(.upperBack, 50), Slot(.shoulder, 50, standing: true),
                    Slot(.finish, 60)]
        case 15:
            return [Slot(.warmup, 60, standing: true), Slot(.neckMobility, 40), Slot(.neckStrength, 60),
                    Slot(.neckStretch, 60), Slot(.neckStretch, 60), Slot(.neckStretch, 60), Slot(.neckStrength, 80),
                    Slot(.neckMobility, 40), Slot(.shoulder, 40), Slot(.shoulder, 40, standing: true),
                    Slot(.upperBack, 60), Slot(.upperBack, 60, standing: true), Slot(.upperBack, 60),
                    Slot(.upperBack, 60), Slot(.finish, 60), Slot(.finish, 60)]
        case 30:
            return [Slot(.movement, 180, standing: true), Slot(.warmup, 90, standing: true), Slot(.neckMobility, 60),
                    Slot(.neckStrength, 90), Slot(.neckStretch, 90), Slot(.neckStretch, 90), Slot(.neckStretch, 90),
                    Slot(.neckStrength, 120), Slot(.neckMobility, 60), Slot(.neckStretch, 60),
                    Slot(.shoulder, 60), Slot(.shoulder, 60, standing: true),
                    Slot(.upperBack, 90), Slot(.upperBack, 90, standing: true), Slot(.upperBack, 90),
                    Slot(.upperBack, 90, standing: true), Slot(.shoulder, 60), Slot(.upperBack, 90),
                    Slot(.finish, 120), Slot(.finish, 60), Slot(.calm, 60)]
        default:
            return template(minutes: 5)
        }
    }

    static let titles: [Int: LText] = [
        2: LText("快速重启", "Quick reset"),
        5: LText("颈肩放松", "Neck & shoulders"),
        10: LText("深度舒展", "Deep stretch"),
        15: LText("全面放松", "Full release"),
        30: LText("完整恢复", "Complete recovery"),
    ]

    /// - Parameters:
    ///   - pool: exercises to choose from (built-in library by default).
    ///   - lastDone: when each exercise id was last practised; older or never → preferred.
    ///   - seed: different seeds give different (but deterministic) picks.
    public static func generate(minutes: Int, pool: [Exercise] = ExerciseLibrary.all,
                                lastDone: [String: Date] = [:], seed: UInt64, now: Date = Date()) -> Routine {
        var rng = SplitMix64(seed: seed &+ UInt64(minutes))
        var used = Set<String>()
        var items: [(Exercise, Int)] = []

        for slot in template(minutes: minutes) {
            func eligible(_ e: Exercise, strictRole: Bool) -> Bool {
                guard !used.contains(e.id), !e.isCustom else { return false }
                if strictRole && !e.roles.contains(slot.role) { return false }
                if e.needsStanding && !slot.standingAllowed { return false }
                if e.bilateral && (slot.seconds % 2 != 0 || slot.seconds < 40) { return false }
                return true
            }
            var candidates = pool.filter { eligible($0, strictRole: true) }
            if candidates.isEmpty { candidates = pool.filter { eligible($0, strictRole: false) && !$0.roles.isEmpty } }
            guard !candidates.isEmpty else { continue }

            // Score: days since last done (capped; never done counts as two weeks) + noise.
            let scored = candidates.map { e -> (Exercise, Double) in
                let days = lastDone[e.id].map { now.timeIntervalSince($0) / 86_400 } ?? 14
                return (e, min(days, 14) + rng.nextUnit() * 3)
            }
            let pick = scored.max { $0.1 < $1.1 }!.0
            used.insert(pick.id)
            items.append((pick, pick.bilateral ? slot.seconds / 2 : slot.seconds))
        }

        return ExerciseLibrary.makeRoutine(
            key: "mix-\(minutes)-\(seed)",
            minutes: minutes,
            title: titles[minutes] ?? LText("推荐组合", "Suggested mix"),
            subtitle: LText("每次组合不同，优先安排最近没做过的动作。", "A different mix every time, favouring what you haven't done lately."),
            items: items)
    }
}

/// Small deterministic RNG (reproducible tests, varied sessions).
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func nextUnit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
