import Foundation

public enum ExerciseCategory: String, CaseIterable, Codable {
    case breathing, neck, shoulders, upperBack, extras

    public var title: String {
        switch self {
        case .breathing: return tr("呼吸与放松", "Breathing")
        case .neck: return tr("颈部", "Neck")
        case .shoulders: return tr("肩部", "Shoulders")
        case .upperBack: return tr("上背与胸椎", "Upper back")
        case .extras: return tr("眼睛、手腕与走动", "Eyes, wrists & moving")
        }
    }
}

/// What an exercise does in a session; used to assemble varied routines.
public enum ExerciseRole: String, Codable, CaseIterable, Hashable {
    case warmup, neckMobility, neckStretch, neckStrength, shoulder, upperBack, finish, movement, calm
}

public struct Exercise: Identifiable, Hashable {
    public let id: String
    public let symbol: String
    public let category: ExerciseCategory
    public let name: LText
    public let summary: LText
    public let howTo: [LText]
    public let dosage: LText
    public let caution: LText?
    /// Done once per side; routines split it into a left and a right step.
    public let bilateral: Bool
    public let needsStanding: Bool
    public let youtubeQuery: String
    public var roles: Set<ExerciseRole>
    /// Suggested duration when practised on its own (per side if bilateral).
    public var defaultSeconds: Int
    /// Created by the user.
    public var isCustom: Bool

    public init(id: String, symbol: String, category: ExerciseCategory, name: LText, summary: LText,
                howTo: [LText], dosage: LText, caution: LText?, bilateral: Bool, needsStanding: Bool,
                youtubeQuery: String, roles: Set<ExerciseRole> = [], defaultSeconds: Int? = nil,
                isCustom: Bool = false) {
        self.id = id
        self.symbol = symbol
        self.category = category
        self.name = name
        self.summary = summary
        self.howTo = howTo
        self.dosage = dosage
        self.caution = caution
        self.bilateral = bilateral
        self.needsStanding = needsStanding
        self.youtubeQuery = youtubeQuery
        self.roles = roles
        self.defaultSeconds = defaultSeconds ?? (bilateral ? 30 : 45)
        self.isCustom = isCustom
    }

    public var youtubeURL: URL { youtubeSearchURL(youtubeQuery) }
}

public enum Side: String, Hashable {
    case left, right
    public var label: String {
        switch self {
        case .left: return tr("左侧", "Left side")
        case .right: return tr("右侧", "Right side")
        }
    }
}

public struct RoutineStep: Identifiable, Hashable {
    public let id: Int
    public let exercise: Exercise
    public let seconds: Int
    public let side: Side?

    public var title: String {
        if let side { return "\(exercise.name.text) · \(side.label)" }
        return exercise.name.text
    }
}

public struct Routine: Identifiable, Hashable {
    /// Stable identity ("classic-5", "mix-10-…", "custom-<uuid>", "single-chinTuck").
    public let key: String
    /// Nominal length in minutes (0 for single exercises / custom routines).
    public let minutes: Int
    public let title: LText
    public let subtitle: LText
    public let steps: [RoutineStep]

    public init(key: String, minutes: Int, title: LText, subtitle: LText, steps: [RoutineStep]) {
        self.key = key
        self.minutes = minutes
        self.title = title
        self.subtitle = subtitle
        self.steps = steps
    }

    public var id: String { key }
    public var totalSeconds: Int { steps.reduce(0) { $0 + $1.seconds } }

    /// Total including the preparation pause before every exercise.
    public func totalSeconds(withPreparation prep: Int) -> Int { totalSeconds + prep * steps.count }
}

public func youtubeSearchURL(_ query: String) -> URL {
    var c = URLComponents(string: "https://www.youtube.com/results")!
    c.queryItems = [URLQueryItem(name: "search_query", value: query)]
    return c.url!
}

/// Neck-relief exercise library and timed routines.
///
/// The selection follows what physiotherapists commonly prescribe for desk-related neck
/// pain (deep neck flexor work, upper-trap / levator stretches, scapular retraction,
/// thoracic extension, chest opening) and what the popular "neck pain relief" videos on
/// YouTube are built around. Every exercise links to a YouTube search so you can watch a
/// demonstration.
public enum ExerciseLibrary {
    /// Built-in exercises with their roles.
    public static let all: [Exercise] = base.map { e in
        var e = e
        e.roles = roles[e.id] ?? []
        if let seconds = defaultSeconds[e.id] { e.defaultSeconds = seconds }
        return e
    }

    static let roles: [String: Set<ExerciseRole>] = [
        "breathing": [.warmup, .calm, .finish],
        "chinTuck": [.neckStrength],
        "semicircle": [.warmup, .neckMobility],
        "sideBend": [.neckStretch],
        "levator": [.neckStretch],
        "rotation": [.neckMobility],
        "flexion": [.neckStretch],
        "isometric": [.neckStrength],
        "shrugs": [.shoulder, .warmup],
        "shoulderRolls": [.shoulder, .warmup],
        "scapSqueeze": [.upperBack],
        "chestStretch": [.upperBack],
        "thoracicExt": [.upperBack],
        "wallAngels": [.upperBack],
        "catCow": [.upperBack, .warmup],
        "sideReach": [.shoulder],
        "wristStretch": [.finish],
        "eyeRest": [.finish],
        "walk": [.movement],
        "scalene": [.neckStretch],
        "suboccipital": [.neckStretch, .neckMobility],
        "nods": [.neckStrength],
        "resistedRotation": [.neckStrength],
        "lookUp": [.neckMobility],
        "depression": [.shoulder],
        "crossBody": [.shoulder],
        "armCircles": [.shoulder, .warmup],
        "overheadStretch": [.shoulder, .warmup],
        "wRaise": [.upperBack],
        "yRaise": [.upperBack],
        "thoracicRotation": [.upperBack],
        "hugStretch": [.upperBack],
        "seatedTwist": [.upperBack],
        "fingerStretch": [.finish],
        "eyeMovement": [.finish],
        "jawRelax": [.calm, .finish],
        "standingExtension": [.movement],
        "marching": [.movement, .warmup],
    ]

    static let defaultSeconds: [String: Int] = [
        "breathing": 60, "walk": 120, "marching": 60, "isometric": 60, "eyeRest": 40,
    ]

    static let base: [Exercise] = [
        Exercise(
            id: "breathing", symbol: "wind", category: .breathing,
            name: LText("腹式呼吸", "Belly breathing"),
            summary: LText("放松颈肩的第一步。浅快的胸式呼吸会让颈部辅助呼吸肌一直处于紧张状态。",
                           "Step one for a tense neck. Shallow chest breathing keeps your neck's accessory breathing muscles working all day."),
            howTo: [
                LText("坐直，双脚平放，一只手放在腹部。", "Sit tall, feet flat, one hand on your belly."),
                LText("用鼻子吸气约 4 秒，让腹部鼓起，肩膀保持不动。", "Breathe in through the nose for ~4 s; let the belly rise, keep the shoulders still."),
                LText("用嘴缓慢呼气约 6 秒，感受肩膀自然下沉。", "Breathe out slowly for ~6 s and feel the shoulders sink."),
                LText("重复，把注意力放在长长的呼气上。", "Repeat, focusing on the long exhale."),
            ],
            dosage: LText("5–8 次慢呼吸", "5–8 slow breaths"),
            caution: nil, bilateral: false, needsStanding: false,
            youtubeQuery: "diaphragmatic breathing for neck and shoulder tension"),

        Exercise(
            id: "chinTuck", symbol: "person.fill.viewfinder", category: .neck,
            name: LText("收下巴（颈部后缩）", "Chin tucks"),
            summary: LText("对抗“头前伸 / 乌龟颈”最经典的动作，激活深层颈屈肌。几乎所有颈痛视频都会从它开始。",
                           "The classic fix for forward-head posture; it switches on the deep neck flexors. Nearly every neck-pain video starts here."),
            howTo: [
                LText("坐直或站直，眼睛平视前方。", "Sit or stand tall, eyes level."),
                LText("下巴水平向后平移，像做出“双下巴”，不要低头也不要仰头。", "Glide your chin straight back, making a double chin — don't nod down or tilt up."),
                LText("感觉后颈被拉长，保持 3–5 秒。", "Feel the back of the neck lengthen; hold 3–5 s."),
                LText("放松回原位再重复。可以用一根手指轻抵下巴引导方向。", "Release and repeat. A finger on the chin can guide the direction."),
            ],
            dosage: LText("8–10 次，每次保持 3–5 秒", "8–10 reps, hold 3–5 s"),
            caution: LText("幅度不需要很大，不应该有疼痛。", "Small movement; it should never hurt."),
            bilateral: false, needsStanding: false,
            youtubeQuery: "chin tuck exercise forward head posture"),

        Exercise(
            id: "semicircle", symbol: "arrow.triangle.2.circlepath", category: .neck,
            name: LText("颈部半圆环绕", "Neck half circles"),
            summary: LText("温和的热身。只在胸前画半圆，避免向后仰头绕大圈挤压颈椎。",
                           "A gentle warm-up. Only the front half — skip full backward circles that compress the neck."),
            howTo: [
                LText("头慢慢倒向右肩。", "Let your head tip slowly towards the right shoulder."),
                LText("下巴沿胸前划半圆，滚到左肩。", "Roll the chin across the chest to the left shoulder."),
                LText("再慢慢滚回右肩。", "Roll back to the right."),
                LText("动作缓慢，配合呼吸。", "Move slowly, with your breath."),
            ],
            dosage: LText("来回 5–6 次", "5–6 times each way"),
            caution: nil, bilateral: false, needsStanding: false,
            youtubeQuery: "neck half circles warm up"),

        Exercise(
            id: "sideBend", symbol: "arrow.left.and.right", category: .neck,
            name: LText("颈侧屈拉伸", "Side neck stretch"),
            summary: LText("放松斜方肌上束——从肩膀连到耳后、最容易发酸的那条肌肉。",
                           "Releases the upper trapezius — the muscle from your shoulder to behind your ear that always feels sore."),
            howTo: [
                LText("坐直，拉伸侧的手抓住椅子边缘或自然下垂，让这一侧肩膀下沉。", "Sit tall. On the side being stretched, hold the chair edge or let the arm hang so the shoulder drops."),
                LText("头慢慢向另一侧倾斜，耳朵靠近肩膀，鼻子保持朝前。", "Tilt your head away, ear towards the other shoulder, nose facing forward."),
                LText("可用另一只手轻放在头上，只增加一点重量，不要拉扯。", "Optionally rest the other hand on your head for a little weight — don't pull."),
                LText("在轻微拉伸感处保持，均匀呼吸。", "Hold at a mild stretch and breathe."),
            ],
            dosage: LText("每侧 20–30 秒", "20–30 s per side"),
            caution: LText("手臂出现麻木或刺痛时立即停止。", "Stop if you feel tingling or numbness down the arm."),
            bilateral: true, needsStanding: false,
            youtubeQuery: "upper trapezius stretch"),

        Exercise(
            id: "levator", symbol: "arrow.down.forward", category: .neck,
            name: LText("肩胛提肌拉伸", "Levator scapulae stretch"),
            summary: LText("针对肩胛骨内上角到颈部的紧绷点，长期低头看屏幕的人几乎都有。",
                           "Targets the knot between the top of the shoulder blade and the neck that screen-starers almost always have."),
            howTo: [
                LText("坐直，头向一侧转约 45°，然后低头，像用鼻子去看同侧腋下。", "Turn your head ~45° to one side, then look down as if your nose points into that armpit."),
                LText("同侧手轻放在后脑，借手臂重量稍微加深。", "Rest the same-side hand on the back of your head to deepen slightly."),
                LText("另一只手抓住椅子，让肩膀下沉。", "Hold the chair with the other hand to keep that shoulder down."),
                LText("保持并缓慢呼吸。", "Hold and breathe slowly."),
            ],
            dosage: LText("每侧 20–30 秒", "20–30 s per side"),
            caution: nil, bilateral: true, needsStanding: false,
            youtubeQuery: "levator scapulae stretch"),

        Exercise(
            id: "rotation", symbol: "arrow.left.arrow.right", category: .neck,
            name: LText("颈部旋转", "Neck rotations"),
            summary: LText("盯着同一块屏幕会让转头变得僵硬，这个动作恢复颈部转动幅度。",
                           "Staring at one screen stiffens rotation; this restores it."),
            howTo: [
                LText("先做一次收下巴，保持头部中立。", "Start with a small chin tuck, head neutral."),
                LText("慢慢向左转头，看向肩膀后方，停 2–3 秒。", "Turn slowly to look over your left shoulder; pause 2–3 s."),
                LText("回到中间，再向右。", "Come back to centre, then go right."),
                LText("肩膀不动，只转头。", "Only the head turns — shoulders stay square."),
            ],
            dosage: LText("左右各 5 次", "5 each side"),
            caution: nil, bilateral: false, needsStanding: false,
            youtubeQuery: "neck rotation stretch"),

        Exercise(
            id: "flexion", symbol: "arrow.down", category: .neck,
            name: LText("低头拉伸", "Chin-to-chest stretch"),
            summary: LText("拉伸后颈到上背的整条肌肉链。", "Lengthens the chain from the back of the neck into the upper back."),
            howTo: [
                LText("坐直，慢慢低头让下巴靠近胸口。", "Sit tall and slowly lower your chin towards your chest."),
                LText("双手可交叉轻放在后脑，只用手臂的重量，不要往下压。", "You may clasp your hands behind your head — let their weight do it, don't press."),
                LText("感受后颈到背部的拉伸，均匀呼吸。", "Feel the stretch down the back of the neck and breathe."),
                LText("慢慢抬头回正。", "Lift your head slowly to finish."),
            ],
            dosage: LText("20–30 秒", "20–30 s"),
            caution: LText("已知有颈椎间盘问题时请非常轻柔，或直接跳过。", "Go very gently, or skip it, if you have a known disc problem."),
            bilateral: false, needsStanding: false,
            youtubeQuery: "chin to chest neck stretch"),

        Exercise(
            id: "isometric", symbol: "hand.raised", category: .neck,
            name: LText("颈部等长收缩", "Isometric neck holds"),
            summary: LText("关节不动、只用力对抗，强化颈部稳定肌群。物理治疗中最常用的颈部力量训练。",
                           "Strengthens the neck without moving it — a physiotherapy staple."),
            howTo: [
                LText("手掌贴住额头：头向前推、手挡住，头保持不动，用约 5 成力，保持 5 秒。", "Palm on forehead: push your head forward into the hand without moving, ~50% effort, 5 s."),
                LText("换到后脑：头向后推、手挡住。", "Hand behind the head: push back."),
                LText("再换左侧、右侧太阳穴各做一遍。", "Then the left and right temples."),
                LText("每个方向重复 3–5 次。", "3–5 reps in each direction."),
            ],
            dosage: LText("4 个方向 × 3–5 次，每次 5 秒", "4 directions × 3–5 reps × 5 s"),
            caution: LText("用力要温和，不要憋气。", "Moderate effort, keep breathing."),
            bilateral: false, needsStanding: false,
            youtubeQuery: "isometric neck strengthening exercises"),

        Exercise(
            id: "shrugs", symbol: "arrow.up.and.down", category: .shoulders,
            name: LText("耸肩放松", "Shrug and drop"),
            summary: LText("先收紧再彻底放松，让肩颈重新记住“放松”的感觉。", "Tense, then let go — reminds your shoulders what relaxed feels like."),
            howTo: [
                LText("吸气，把双肩尽量耸向耳朵，保持 2 秒。", "Breathe in and lift both shoulders towards your ears; hold 2 s."),
                LText("呼气，让肩膀完全落下。", "Breathe out and let them drop completely."),
                LText("注意放松后肩膀比之前更低。", "Notice they sit lower than before."),
            ],
            dosage: LText("10 次", "10 reps"),
            caution: nil, bilateral: false, needsStanding: false,
            youtubeQuery: "shoulder shrug release exercise"),

        Exercise(
            id: "shoulderRolls", symbol: "arrow.clockwise", category: .shoulders,
            name: LText("肩部绕环", "Shoulder rolls"),
            summary: LText("促进肩部血液循环，缓解久坐僵硬。", "Gets blood moving through stiff shoulders."),
            howTo: [
                LText("双臂自然下垂。", "Let your arms hang."),
                LText("肩膀向上、向后、向下画大圈。", "Draw big circles: up, back and down."),
                LText("向后 10 圈，再向前 5 圈。", "10 backwards, then 5 forwards."),
                LText("慢而完整。", "Slow and full range."),
            ],
            dosage: LText("向后 10 圈 + 向前 5 圈", "10 back + 5 forward"),
            caution: nil, bilateral: false, needsStanding: false,
            youtubeQuery: "shoulder rolls exercise"),

        Exercise(
            id: "scapSqueeze", symbol: "arrow.right.and.line.vertical.and.arrow.left", category: .upperBack,
            name: LText("夹肩胛", "Shoulder-blade squeeze"),
            summary: LText("唤醒久坐时被拉长、变弱的上背肌群，对抗含胸驼背。", "Wakes up the upper-back muscles that slouching switches off."),
            howTo: [
                LText("坐直，手臂放松或屈肘 90°。", "Sit tall, arms relaxed or elbows bent 90°."),
                LText("把肩胛骨向后、向下夹，像要夹住背后的一支笔。", "Squeeze the shoulder blades back and down, as if pinching a pencil."),
                LText("不要耸肩、不要挺肚子，保持 5 秒。", "Don't shrug or arch your lower back; hold 5 s."),
                LText("放松后重复。", "Release and repeat."),
            ],
            dosage: LText("10 次，每次 5 秒", "10 reps × 5 s"),
            caution: nil, bilateral: false, needsStanding: false,
            youtubeQuery: "scapular retraction exercise"),

        Exercise(
            id: "chestStretch", symbol: "door.left.hand.open", category: .upperBack,
            name: LText("门框扩胸拉伸", "Doorway chest stretch"),
            summary: LText("打开因长时间敲键盘而缩短的胸肌，让肩膀回到该在的位置。", "Opens the chest muscles that typing shortens, so your shoulders can sit back."),
            howTo: [
                LText("站在门框前，前臂贴住门框两侧，肘与肩同高。", "Stand in a doorway, forearms on the frame, elbows at shoulder height."),
                LText("一只脚向前迈一小步，身体缓慢前倾。", "Step one foot forward and lean in slowly."),
                LText("胸前有拉伸感即可，保持并呼吸。", "Stop at a gentle stretch across the chest; breathe."),
                LText("没有门框时：双手在背后十指相扣，向后下方伸展。", "No doorway? Clasp your hands behind your back and reach down and back."),
            ],
            dosage: LText("30 秒，1–2 次", "30 s, 1–2 times"),
            caution: nil, bilateral: false, needsStanding: true,
            youtubeQuery: "doorway chest stretch"),

        Exercise(
            id: "thoracicExt", symbol: "chair", category: .upperBack,
            name: LText("椅背胸椎伸展", "Chair-back extension"),
            summary: LText("上背僵硬弓起时，脖子只能代偿着往前探。这个动作把伸展还给胸椎。",
                           "When the upper back stiffens into a curve, the neck pokes forward to compensate. This gives extension back to the thoracic spine."),
            howTo: [
                LText("坐稳在有靠背的椅子上，靠背上缘大约在肩胛骨下方。", "Sit on a chair whose backrest reaches just below your shoulder blades."),
                LText("双手抱在脑后支撑头部，肘部打开。", "Support your head with your hands, elbows wide."),
                LText("吸气，以椅背为支点向后伸展上背，眼睛看斜上方。", "Breathe in and extend back over the backrest, eyes up and forward."),
                LText("呼气回正。", "Breathe out and come back up."),
            ],
            dosage: LText("6–8 次", "6–8 reps"),
            caution: LText("确认椅子稳固，不要靠着可能翻倒的椅子猛地后仰。", "Make sure the chair is stable; never lean hard on one that can tip."),
            bilateral: false, needsStanding: false,
            youtubeQuery: "thoracic extension over chair desk stretch"),

        Exercise(
            id: "wallAngels", symbol: "figure.arms.open", category: .upperBack,
            name: LText("靠墙天使", "Wall angels"),
            summary: LText("同时训练姿势与肩部活动度，纠正圆肩的经典动作。", "Posture and shoulder mobility in one move; a staple for rounded shoulders."),
            howTo: [
                LText("背靠墙站，脚跟离墙一脚距离，后脑、上背、臀部贴墙。", "Stand with your back to a wall, heels a foot away; head, upper back and hips touch the wall."),
                LText("手臂举成“W”形，手背和肘尽量贴墙。", "Raise your arms into a W, backs of hands and elbows towards the wall."),
                LText("缓慢向上滑成“Y”形，再滑回“W”。", "Slide slowly up into a Y, then back to W."),
                LText("保持收下巴，腰不要离墙太多。", "Keep the chin tucked and the lower back close to the wall."),
            ],
            dosage: LText("8–10 次", "8–10 reps"),
            caution: nil, bilateral: false, needsStanding: true,
            youtubeQuery: "wall angels exercise posture"),

        Exercise(
            id: "catCow", symbol: "figure.flexibility", category: .upperBack,
            name: LText("坐姿猫牛式", "Seated cat-cow"),
            summary: LText("让整条脊柱轮流屈伸，缓解久坐的僵硬感。", "Moves the whole spine through flexion and extension."),
            howTo: [
                LText("坐在椅子前半部分，双手放在膝盖上。", "Sit near the front of your chair, hands on knees."),
                LText("吸气：挺胸、骨盆前倾、目视斜上方（牛式）。", "Inhale: chest forward, pelvis tilts, eyes up (cow)."),
                LText("呼气：弓背含胸、低头、肚脐内收（猫式）。", "Exhale: round the back, chin down, belly in (cat)."),
                LText("跟随呼吸慢慢交替。", "Flow slowly with your breath."),
            ],
            dosage: LText("8–10 个呼吸循环", "8–10 breaths"),
            caution: nil, bilateral: false, needsStanding: false,
            youtubeQuery: "seated cat cow stretch"),

        Exercise(
            id: "sideReach", symbol: "arrow.up.left", category: .shoulders,
            name: LText("坐姿侧身伸展", "Overhead side reach"),
            summary: LText("拉伸身体侧面与背阔肌，让肩膀更舒展。", "Stretches the side body and lats so the shoulders open up."),
            howTo: [
                LText("坐直，一侧手臂举过头顶。", "Sit tall and reach one arm overhead."),
                LText("身体向对侧弯曲，像被拉向斜上方。", "Lean to the opposite side, as if pulled up and over."),
                LText("两侧坐骨都压在椅子上，保持呼吸。", "Keep both sit bones on the chair; breathe."),
            ],
            dosage: LText("每侧 20–30 秒", "20–30 s per side"),
            caution: nil, bilateral: true, needsStanding: false,
            youtubeQuery: "seated overhead side stretch"),

        Exercise(
            id: "wristStretch", symbol: "hand.point.up.left", category: .extras,
            name: LText("手腕前臂拉伸", "Wrist & forearm stretch"),
            summary: LText("键盘鼠标用户的附加放松，预防手腕与前臂劳损。", "A bonus for keyboard-and-mouse hands."),
            howTo: [
                LText("一侧手臂向前伸直，掌心朝前、手指朝上。", "Straighten one arm in front, palm out, fingers up."),
                LText("另一只手把手指轻轻拉向身体，保持 10–15 秒。", "Gently pull the fingers back with the other hand; 10–15 s."),
                LText("翻转掌心朝下，把手背轻压向身体。", "Flip the palm down and gently press the back of the hand towards you."),
                LText("动作轻柔。", "Keep it gentle."),
            ],
            dosage: LText("每侧 20–30 秒", "20–30 s per side"),
            caution: nil, bilateral: true, needsStanding: false,
            youtubeQuery: "wrist and forearm stretch for desk workers"),

        Exercise(
            id: "eyeRest", symbol: "eye", category: .extras,
            name: LText("远眺护眼（20-20-20）", "Eye break (20-20-20)"),
            summary: LText("眼睛疲劳会让人不自觉地把头往前探。看远处，眼睛和脖子一起放松。",
                           "Tired eyes make you crane towards the screen. Look far away and both relax."),
            howTo: [
                LText("看向 6 米（20 英尺）以外的物体，比如窗外。", "Look at something at least 6 m (20 ft) away, e.g. out of a window."),
                LText("保持 20 秒以上，慢慢眨眼。", "Hold for 20 s or more, blinking slowly."),
                LText("双手搓热，轻轻捂住闭着的眼睛。", "Rub your palms warm and cup them over closed eyes."),
                LText("再睁眼看远处。", "Open your eyes to the distance again."),
            ],
            dosage: LText("20 秒以上", "20 s or more"),
            caution: nil, bilateral: false, needsStanding: false,
            youtubeQuery: "20 20 20 rule eye exercises"),

        Exercise(
            id: "walk", symbol: "figure.walk", category: .extras,
            name: LText("起身走动、喝水", "Stand up, walk, drink"),
            summary: LText("最好的姿势永远是“下一个姿势”。离开屏幕走一走。", "The best posture is your next posture. Step away from the screen."),
            howTo: [
                LText("站起来，离开屏幕。", "Stand up and step away from the screen."),
                LText("倒杯水，或者在楼道里走一圈。", "Fetch some water or walk a lap."),
                LText("走路时手臂自然摆动，肩膀放松。", "Let your arms swing and shoulders relax."),
                LText("回来时顺便检查一下显示器高度和坐姿。", "On the way back, check your screen height and chair."),
            ],
            dosage: LText("1–5 分钟", "1–5 min"),
            caution: nil, bilateral: false, needsStanding: true,
            youtubeQuery: "desk break walking stretch routine"),

        // MARK: More neck work

        Exercise(
            id: "scalene", symbol: "arrow.up.backward", category: .neck,
            name: LText("斜角肌拉伸", "Scalene stretch"),
            summary: LText("拉伸颈部前侧到锁骨的斜角肌，长时间探头、浅呼吸的人常常很紧。",
                           "Stretches the scalenes at the front-side of the neck — tight in anyone who pokes their head forward or breathes shallowly."),
            howTo: [
                LText("坐直，拉伸侧的手抓住椅子边缘，让肩膀下沉。", "Sit tall and hold the chair edge on the side being stretched so the shoulder drops."),
                LText("头向另一侧倾斜，再微微向后上方看。", "Tilt your head away, then look slightly up and back."),
                LText("颈部前侧有拉伸感即可，保持并缓慢呼吸。", "Stop at a gentle stretch in the front of the neck and breathe slowly."),
            ],
            dosage: LText("每侧 20–30 秒", "20–30 s per side"),
            caution: LText("动作要轻；出现头晕立即回正。", "Keep it gentle; come back to neutral if you feel dizzy."),
            bilateral: true, needsStanding: false,
            youtubeQuery: "scalene stretch neck"),

        Exercise(
            id: "suboccipital", symbol: "hand.point.up", category: .neck,
            name: LText("枕下肌放松", "Suboccipital release"),
            summary: LText("后脑勺下方的小肌肉和紧张性头痛、盯屏幕时下巴前伸都有关。",
                           "The small muscles under the back of the skull are linked to tension headaches and a jutting chin."),
            howTo: [
                LText("双手指尖放在后脑勺下方、颈椎两侧的凹陷处。", "Place your fingertips in the hollows at the base of the skull."),
                LText("轻轻按住，做很小幅度的“点头”，像在说“是”。", "Press lightly and make tiny nods, as if saying “yes”."),
                LText("再配合几次收下巴，感受后脑下方被拉长。", "Add a few chin tucks and feel the base of the skull lengthen."),
            ],
            dosage: LText("30–60 秒", "30–60 s"),
            caution: nil, bilateral: false, needsStanding: false,
            youtubeQuery: "suboccipital release self massage"),

        Exercise(
            id: "nods", symbol: "arrow.down.circle", category: .neck,
            name: LText("深层点头", "Deep neck flexor nods"),
            summary: LText("物理治疗常用的深层颈屈肌训练，比收下巴更细致，帮助头部回到正确位置。",
                           "A physio staple for the deep neck flexors — subtler than a chin tuck, it helps the head sit back where it belongs."),
            howTo: [
                LText("坐直或靠墙站，后脑轻贴椅背或墙。", "Sit tall or stand with the back of your head lightly against the chair or wall."),
                LText("下巴微微向喉咙方向点一下，幅度只有一两厘米。", "Nod the chin slightly towards your throat — just a centimetre or two."),
                LText("保持 3 秒，颈部前侧的大肌肉不要绷紧。", "Hold 3 s without tensing the big muscles at the front of the neck."),
                LText("放松后重复。", "Release and repeat."),
            ],
            dosage: LText("10 次，每次 3 秒", "10 reps × 3 s"),
            caution: nil, bilateral: false, needsStanding: false,
            youtubeQuery: "deep neck flexor chin nod exercise"),

        Exercise(
            id: "resistedRotation", symbol: "arrow.triangle.turn.up.right.circle", category: .neck,
            name: LText("旋转等长抗阻", "Isometric rotation"),
            summary: LText("头不动，只用力对抗转头，强化负责转头的肌群。",
                           "Strengthens the rotators without moving the head."),
            howTo: [
                LText("手掌贴在一侧太阳穴略靠前的位置。", "Place your palm on the side of your head, slightly in front of the temple."),
                LText("试着把头往手的方向转，用手挡住，头保持不动。", "Try to turn your head into the hand while the hand stops it — no movement."),
                LText("用约 3–5 成力，保持 5 秒，放松。", "Use 30–50% effort, hold 5 s, relax."),
                LText("重复 5 次。", "Repeat 5 times."),
            ],
            dosage: LText("每侧 5 次 × 5 秒", "5 reps × 5 s per side"),
            caution: LText("用力温和，不要憋气。", "Moderate effort, keep breathing."),
            bilateral: true, needsStanding: false,
            youtubeQuery: "isometric neck rotation exercise"),

        Exercise(
            id: "lookUp", symbol: "arrow.up", category: .neck,
            name: LText("抬头望天", "Gentle look-up"),
            summary: LText("长时间低头之后，温和地反方向活动一下颈椎。", "After hours looking down, gently move the other way."),
            howTo: [
                LText("先做一次收下巴。", "Start with a chin tuck."),
                LText("慢慢抬头看向天花板，嘴巴可以微微张开放松下颌。", "Slowly look up to the ceiling; let your mouth open slightly to relax the jaw."),
                LText("停 2 秒，再慢慢回到平视。", "Pause 2 s, then slowly come back to level."),
            ],
            dosage: LText("6–8 次", "6–8 reps"),
            caution: LText("只在舒适范围内；出现头晕、手臂麻木请停止。", "Comfortable range only; stop if dizzy or if your arm tingles."),
            bilateral: false, needsStanding: false,
            youtubeQuery: "gentle neck extension stretch"),

        // MARK: More shoulders

        Exercise(
            id: "depression", symbol: "arrow.down.to.line", category: .shoulders,
            name: LText("肩膀下沉", "Shoulder depression"),
            summary: LText("耸肩的反向动作：把肩膀从耳朵旁边拿开，让脖子变长。", "The opposite of a shrug: move your shoulders away from your ears and let the neck lengthen."),
            howTo: [
                LText("坐直，手臂自然下垂。", "Sit tall, arms by your sides."),
                LText("把双肩向下、稍向后压，想象脖子变长。", "Draw both shoulders down and slightly back, as if making your neck longer."),
                LText("保持 5 秒，放松。", "Hold 5 s, relax."),
            ],
            dosage: LText("10 次", "10 reps"),
            caution: nil, bilateral: false, needsStanding: false,
            youtubeQuery: "scapular depression exercise"),

        Exercise(
            id: "crossBody", symbol: "arrow.left.to.line", category: .shoulders,
            name: LText("手臂横拉", "Cross-body shoulder stretch"),
            summary: LText("拉伸肩膀后侧，敲键盘、握鼠标的一侧往往更紧。", "Stretches the back of the shoulder — usually tighter on the mouse side."),
            howTo: [
                LText("一侧手臂伸直横过胸前。", "Bring one straight arm across your chest."),
                LText("另一只手在肘部上方轻轻往身体方向带。", "With the other hand, gently draw it in just above the elbow."),
                LText("肩膀不要耸起，保持并呼吸。", "Keep the shoulder down; hold and breathe."),
            ],
            dosage: LText("每侧 20–30 秒", "20–30 s per side"),
            caution: nil, bilateral: true, needsStanding: false,
            youtubeQuery: "cross body shoulder stretch"),

        Exercise(
            id: "armCircles", symbol: "circle.dashed", category: .shoulders,
            name: LText("手臂画圈", "Arm circles"),
            summary: LText("让肩关节在各个方向都动一动，促进血液循环。", "Moves the shoulder joint in every direction and gets the blood flowing."),
            howTo: [
                LText("站立，双臂向两侧平举。", "Stand and raise both arms out to the sides."),
                LText("先画小圈，再逐渐变大，向前 10 圈。", "Draw small circles, growing bigger — 10 forwards."),
                LText("再向后 10 圈。", "Then 10 backwards."),
            ],
            dosage: LText("前后各 10 圈", "10 each way"),
            caution: nil, bilateral: false, needsStanding: true,
            youtubeQuery: "arm circles warm up"),

        Exercise(
            id: "overheadStretch", symbol: "arrow.up.to.line", category: .shoulders,
            name: LText("双手上举伸展", "Overhead reach"),
            summary: LText("把身体整个拉长，打开肩膀和胸廓。", "Lengthens the whole body and opens the shoulders and rib cage."),
            howTo: [
                LText("十指交叉，掌心向上推过头顶。", "Interlace your fingers and push your palms up overhead."),
                LText("手臂贴近耳朵，向上延伸，深吸一口气。", "Arms by your ears, reach up and take a deep breath."),
                LText("呼气时肩膀放松但手臂继续向上。", "As you exhale, relax the shoulders while still reaching up."),
            ],
            dosage: LText("20–30 秒", "20–30 s"),
            caution: nil, bilateral: false, needsStanding: false,
            youtubeQuery: "overhead reach stretch seated"),

        // MARK: More upper back

        Exercise(
            id: "wRaise", symbol: "w.circle", category: .upperBack,
            name: LText("W 字后夹", "W squeeze"),
            summary: LText("强化中下斜方肌，把含着的胸和肩拉回来。", "Strengthens the middle and lower traps to pull rounded shoulders back."),
            howTo: [
                LText("屈肘贴在身体两侧，掌心朝前，手臂成“W”形。", "Elbows bent by your sides, palms forward — arms in a W."),
                LText("肩胛骨向后下方夹，手肘稍微向后打开。", "Squeeze the shoulder blades back and down, opening the elbows slightly back."),
                LText("保持 3 秒，放松。不要耸肩。", "Hold 3 s, relax. Don't shrug."),
            ],
            dosage: LText("10–12 次", "10–12 reps"),
            caution: nil, bilateral: false, needsStanding: false,
            youtubeQuery: "W exercise posture scapular"),

        Exercise(
            id: "yRaise", symbol: "y.circle", category: .upperBack,
            name: LText("Y 字上举", "Y raise"),
            summary: LText("激活下斜方肌——圆肩和头前伸里最容易“偷懒”的肌肉。", "Wakes up the lower traps, the laziest muscle in rounded-shoulder posture."),
            howTo: [
                LText("身体稍微前倾，背部挺直。", "Lean slightly forward with a straight back."),
                LText("拇指朝上，双臂向斜上方举成“Y”形。", "Thumbs up, raise both arms diagonally into a Y."),
                LText("举到最高时肩胛骨向下收，停 2 秒，慢慢放下。", "At the top, draw the shoulder blades down, pause 2 s, lower slowly."),
            ],
            dosage: LText("8–10 次", "8–10 reps"),
            caution: nil, bilateral: false, needsStanding: false,
            youtubeQuery: "Y raise lower trap exercise"),

        Exercise(
            id: "thoracicRotation", symbol: "arrow.clockwise.circle", category: .upperBack,
            name: LText("坐姿胸椎旋转", "Seated thoracic rotation"),
            summary: LText("让上背转动起来，转头时颈部就不用独自扛下所有角度。", "Gets the upper back turning, so the neck doesn't have to do all the rotation."),
            howTo: [
                LText("坐直，双臂交叉抱在胸前。", "Sit tall with arms crossed over your chest."),
                LText("骨盆保持不动，上身慢慢转向一侧。", "Keep the hips still and slowly turn the upper body to one side."),
                LText("停 3 秒，回到中间，重复。", "Pause 3 s, return to centre, repeat."),
            ],
            dosage: LText("每侧 6 次", "6 per side"),
            caution: nil, bilateral: true, needsStanding: false,
            youtubeQuery: "seated thoracic rotation stretch"),

        Exercise(
            id: "hugStretch", symbol: "figure.cooldown", category: .upperBack,
            name: LText("抱肩拉伸", "Self-hug stretch"),
            summary: LText("拉开两块肩胛骨之间，久坐后那片酸胀的区域。", "Opens the space between the shoulder blades — that ache after long sitting."),
            howTo: [
                LText("双臂交叉抱住自己，手放在对侧肩胛骨上。", "Hug yourself, hands reaching for the opposite shoulder blades."),
                LText("低头含胸，背部向后拱起。", "Drop your chin and round your upper back."),
                LText("把气吸到背后，感觉肩胛骨被拉开。", "Breathe into your back and feel the blades spread."),
            ],
            dosage: LText("20–30 秒", "20–30 s"),
            caution: nil, bilateral: false, needsStanding: false,
            youtubeQuery: "upper back stretch hug yourself"),

        Exercise(
            id: "seatedTwist", symbol: "arrow.triangle.2.circlepath.circle", category: .upperBack,
            name: LText("坐姿脊柱扭转", "Seated spinal twist"),
            summary: LText("温和地扭转整条脊柱，释放久坐带来的僵硬。", "A gentle twist through the whole spine to undo long sitting."),
            howTo: [
                LText("坐直，右手放在左膝外侧，左手扶住椅背。", "Sit tall, right hand on the outside of your left knee, left hand on the backrest."),
                LText("吸气拉长脊柱，呼气时向左后方转。", "Inhale to lengthen, exhale to twist towards the back."),
                LText("头最后跟着转，保持并呼吸。", "Let the head follow last; hold and breathe."),
            ],
            dosage: LText("每侧 20–30 秒", "20–30 s per side"),
            caution: nil, bilateral: true, needsStanding: false,
            youtubeQuery: "seated spinal twist chair"),

        // MARK: More extras

        Exercise(
            id: "fingerStretch", symbol: "hand.raised.fingers.spread", category: .extras,
            name: LText("手指张合", "Finger spreads"),
            summary: LText("长时间打字后，让手指和手掌伸展一下。", "Undo hours of typing for your fingers and palms."),
            howTo: [
                LText("双手用力张开五指，保持 3 秒。", "Spread your fingers wide for 3 s."),
                LText("再慢慢握拳，保持 3 秒。", "Slowly make a fist for 3 s."),
                LText("重复，最后甩甩手放松。", "Repeat, then shake out your hands."),
            ],
            dosage: LText("10 次", "10 reps"),
            caution: nil, bilateral: false, needsStanding: false,
            youtubeQuery: "finger stretches for typing"),

        Exercise(
            id: "eyeMovement", symbol: "eye.circle", category: .extras,
            name: LText("眼球运动", "Eye movements"),
            summary: LText("盯着屏幕时眼睛几乎不动，活动一下眼外肌也能放松颈部。", "Eyes barely move while staring at a screen; moving them relaxes the neck too."),
            howTo: [
                LText("头保持不动，眼睛慢慢看向上、下、左、右。", "Keep your head still and slowly look up, down, left and right."),
                LText("再慢慢顺时针、逆时针各转几圈。", "Then a few slow circles each way."),
                LText("最后闭眼，用力眨几下。", "Finish by closing your eyes and blinking firmly a few times."),
            ],
            dosage: LText("30–45 秒", "30–45 s"),
            caution: nil, bilateral: false, needsStanding: false,
            youtubeQuery: "eye exercises for screen strain"),

        Exercise(
            id: "jawRelax", symbol: "mouth", category: .breathing,
            name: LText("下颌放松", "Jaw release"),
            summary: LText("专注时会不自觉咬紧牙，下颌紧张会一路传到颈部和头部。", "Concentration makes you clench; jaw tension travels into the neck and head."),
            howTo: [
                LText("上下牙分开，舌头轻轻放在上颚。", "Let your teeth part and rest the tongue on the roof of the mouth."),
                LText("用指腹在耳朵前方的咬肌上画小圈按揉。", "Massage small circles on the jaw muscles in front of your ears."),
                LText("慢慢张嘴、合嘴几次，配合呼气。", "Slowly open and close the mouth a few times with long exhales."),
            ],
            dosage: LText("30–60 秒", "30–60 s"),
            caution: nil, bilateral: false, needsStanding: false,
            youtubeQuery: "jaw tension release massage"),

        Exercise(
            id: "standingExtension", symbol: "figure.stand", category: .extras,
            name: LText("站立后仰", "Standing back bend"),
            summary: LText("久坐让身体一直向前弯，站起来轻轻向后伸展。", "Sitting bends you forward all day; stand up and gently extend back."),
            howTo: [
                LText("站立，双手扶在腰后。", "Stand with your hands on your lower back."),
                LText("髋部稍微向前推，上身慢慢向后仰。", "Push the hips slightly forward and slowly lean back."),
                LText("停 2 秒，回到直立。", "Pause 2 s and come back up."),
            ],
            dosage: LText("5–8 次", "5–8 reps"),
            caution: LText("只在舒适范围内；腰部不适请跳过。", "Comfortable range only; skip if your lower back complains."),
            bilateral: false, needsStanding: true,
            youtubeQuery: "standing back extension exercise"),

        Exercise(
            id: "marching", symbol: "figure.walk.motion", category: .extras,
            name: LText("原地踏步 + 提踵", "March & calf raises"),
            summary: LText("没地方走动时，原地动一动也能让全身血液流动起来。", "No space to walk? Moving on the spot gets the blood going too."),
            howTo: [
                LText("站立原地踏步，手臂自然摆动，30 秒。", "March on the spot for 30 s, arms swinging."),
                LText("再踮起脚尖、慢慢落下，重复 15 次。", "Then rise onto your toes and lower slowly, 15 times."),
                LText("保持呼吸顺畅，肩膀放松。", "Keep breathing and shoulders relaxed."),
            ],
            dosage: LText("1–2 分钟", "1–2 min"),
            caution: nil, bilateral: false, needsStanding: true,
            youtubeQuery: "desk break march in place calf raises"),
    ]

    public static func exercise(_ id: String) -> Exercise {
        guard let e = all.first(where: { $0.id == id }) else {
            preconditionFailure("Unknown exercise \(id)")
        }
        return e
    }

    /// Build a routine from (exercise, seconds). Bilateral exercises get the seconds per side.
    public static func makeRoutine(key: String, minutes: Int, title: LText, subtitle: LText,
                                   items: [(Exercise, Int)]) -> Routine {
        var steps: [RoutineStep] = []
        for (e, seconds) in items {
            if e.bilateral {
                steps.append(RoutineStep(id: steps.count, exercise: e, seconds: seconds, side: .left))
                steps.append(RoutineStep(id: steps.count, exercise: e, seconds: seconds, side: .right))
            } else {
                steps.append(RoutineStep(id: steps.count, exercise: e, seconds: seconds, side: nil))
            }
        }
        return Routine(key: key, minutes: minutes, title: title, subtitle: subtitle, steps: steps)
    }

    static func routine(minutes: Int, title: LText, subtitle: LText, _ items: [(String, Int)]) -> Routine {
        makeRoutine(key: "classic-\(minutes)", minutes: minutes, title: title, subtitle: subtitle,
                    items: items.map { (exercise($0.0), $0.1) })
    }

    /// Practise one exercise on its own.
    public static func single(_ e: Exercise, seconds: Int? = nil) -> Routine {
        makeRoutine(key: "single-\(e.id)", minutes: 0, title: e.name,
                    subtitle: LText("单个动作练习", "Single exercise"),
                    items: [(e, seconds ?? e.defaultSeconds)])
    }

    /// Routines of 2 / 5 / 10 / 15 / 30 minutes. Each one sums exactly to its length.
    public static let routines: [Routine] = [
        routine(minutes: 2,
                title: LText("快速重启", "Quick reset"),
                subtitle: LText("坐着就能做，适合会议间隙。", "Seated, fits between meetings."),
                [("chinTuck", 30), ("sideBend", 20), ("shoulderRolls", 25), ("scapSqueeze", 25)]),
        routine(minutes: 5,
                title: LText("颈肩基础放松", "Neck & shoulder basics"),
                subtitle: LText("覆盖最核心的颈部动作，每天做几次最划算。", "The core neck moves — the best value if you do it a few times a day."),
                [("breathing", 30), ("chinTuck", 40), ("sideBend", 25), ("levator", 25),
                 ("rotation", 30), ("shoulderRolls", 30), ("scapSqueeze", 40), ("eyeRest", 30)]),
        routine(minutes: 10,
                title: LText("深度舒展", "Deep stretch"),
                subtitle: LText("加入力量与胸椎动作，从根上改善头前伸。", "Adds strength and upper-back work to tackle forward head posture."),
                [("breathing", 45), ("chinTuck", 45), ("semicircle", 30), ("sideBend", 30), ("levator", 30),
                 ("rotation", 40), ("isometric", 60), ("shoulderRolls", 30), ("scapSqueeze", 45),
                 ("chestStretch", 45), ("thoracicExt", 45), ("sideReach", 25), ("eyeRest", 45)]),
        routine(minutes: 15,
                title: LText("全面放松", "Full release"),
                subtitle: LText("颈、肩、上背、手腕、眼睛全覆盖。", "Neck, shoulders, upper back, wrists and eyes."),
                [("breathing", 60), ("chinTuck", 60), ("semicircle", 40), ("sideBend", 30), ("levator", 30),
                 ("flexion", 30), ("rotation", 45), ("isometric", 80), ("shrugs", 40), ("shoulderRolls", 40),
                 ("scapSqueeze", 60), ("wallAngels", 60), ("chestStretch", 60), ("thoracicExt", 60),
                 ("catCow", 60), ("wristStretch", 25), ("eyeRest", 35)]),
        routine(minutes: 30,
                title: LText("完整恢复", "Complete recovery"),
                subtitle: LText("先走动热身，再完整做一遍，最后平静收尾。适合午休或下班前。", "Walk to warm up, a full session, then a calm finish. Great at lunch or end of day."),
                [("walk", 180), ("breathing", 90), ("chinTuck", 90), ("semicircle", 60), ("sideBend", 45),
                 ("levator", 45), ("flexion", 45), ("rotation", 60), ("isometric", 120), ("shrugs", 60),
                 ("shoulderRolls", 60), ("scapSqueeze", 90), ("wallAngels", 90), ("chestStretch", 90),
                 ("thoracicExt", 90), ("catCow", 90), ("sideReach", 45), ("wristStretch", 30),
                 ("eyeRest", 120), ("walk", 75), ("breathing", 60)]),
    ]

    public static func routine(minutes: Int) -> Routine {
        routines.first { $0.minutes == minutes } ?? routines[1]
    }

    public static let ergonomicTips: [LText] = [
        LText("屏幕上缘与眼睛平齐或略低，距离约一臂长。", "Top of the screen at or slightly below eye level, about an arm's length away."),
        LText("笔记本请配支架 + 外接键盘鼠标，避免长时间低头。", "Put a laptop on a stand and use an external keyboard and mouse so you aren't looking down for hours."),
        LText("双脚平放地面，膝盖约 90°，腰部有支撑。", "Feet flat, knees around 90°, lower back supported."),
        LText("键盘靠近身体，手肘贴近身侧约 90°，肩膀放松。", "Keyboard close, elbows by your sides at ~90°, shoulders relaxed."),
        LText("打电话用耳机，别用肩膀夹手机。", "Use a headset — never cradle the phone with your shoulder."),
        LText("20-20-20：每 20 分钟看 20 英尺（6 米）外 20 秒。", "20-20-20: every 20 minutes look 20 feet away for 20 seconds."),
        LText("多喝水——自然会让你更频繁地起身。", "Drink more water — you'll get up more often by necessity."),
    ]

    public static let safetyNote = LText(
        "本指南用于日常保健，不能替代医疗建议。所有动作都应在无痛范围内进行。出现手臂放射痛、麻木或无力，头晕、恶心，外伤后颈痛，或疼痛持续加重、夜间痛时，请停止练习并就医。",
        "This guide is for everyday wellbeing, not medical advice. Stay within a pain-free range. Stop and see a doctor if you get pain, numbness or weakness down the arm, dizziness or nausea, neck pain after an injury, or pain that keeps getting worse or wakes you at night.")

    /// Well-known YouTube creators whose neck-pain routines inspired this guide (links are searches).
    public static let videoReferences: [(title: LText, query: String)] = [
        (LText("Bob & Brad：颈痛缓解动作", "Bob & Brad — neck pain relief"), "Bob and Brad neck pain relief exercises"),
        (LText("Ask Doctor Jo：颈部拉伸", "Ask Doctor Jo — neck stretches"), "Ask Doctor Jo neck stretches"),
        (LText("Yoga With Adriene：肩颈瑜伽", "Yoga With Adriene — yoga for neck and shoulders"), "Yoga With Adriene yoga for neck and shoulder relief"),
        (LText("ATHLEAN-X：改善颈痛与头前伸", "ATHLEAN-X — fixing neck pain & forward head"), "Athlean-X fix neck pain forward head posture"),
        (LText("Tone and Tighten：颈痛拉伸", "Tone and Tighten — neck pain stretches"), "Tone and Tighten neck pain relief stretches"),
        (LText("中文：办公室颈椎操跟练", "Chinese: office neck routine follow-along"), "颈椎操 办公室 跟练"),
    ]
}
