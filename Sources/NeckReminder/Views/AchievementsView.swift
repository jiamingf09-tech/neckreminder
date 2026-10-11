import AppKit
import SwiftUI
import NeckReminderCore

enum TierStyle {
    static func gradient(_ tier: AchievementTier) -> AnyShapeStyle {
        switch tier {
        case .bronze:
            return AnyShapeStyle(LinearGradient(colors: [Color(red: 0.72, green: 0.42, blue: 0.20), Color(red: 0.96, green: 0.70, blue: 0.45)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
        case .silver:
            return AnyShapeStyle(LinearGradient(colors: [Color(red: 0.55, green: 0.60, blue: 0.68), Color(red: 0.90, green: 0.92, blue: 0.96)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
        case .gold:
            return AnyShapeStyle(LinearGradient(colors: [Color(red: 0.93, green: 0.62, blue: 0.05), Color(red: 1.0, green: 0.88, blue: 0.38)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
        case .legendary:
            return AnyShapeStyle(AngularGradient(colors: [.pink, .orange, .yellow, .green, .cyan, .blue, .purple, .pink],
                                                 center: .center))
        }
    }

    static func glow(_ tier: AchievementTier) -> Color {
        switch tier {
        case .bronze: return .orange
        case .silver: return .white
        case .gold: return .yellow
        case .legendary: return .purple
        }
    }
}

struct AchievementsView: View {
    @EnvironmentObject var achievements: AchievementStore
    @EnvironmentObject var content: ContentStore
    @State private var fireTrigger = 0
    @State private var fresh: Set<String> = []

    var body: some View {
        let ctx = achievements.context(content)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero(ctx)
                heatmap
                badges(ctx)
            }
            .padding(24)
        }
        .onAppear {
            let new = achievements.refresh(content: content)
            if !new.isEmpty {
                fresh = Set(new.map(\.id))
                fireTrigger += 1
            }
        }
    }

    // MARK: Hero

    private func hero(_ ctx: AchievementContext) -> some View {
        let log = ctx.log
        let level = Achievements.level(forXP: log.xp)
        let floor = Achievements.threshold(level)
        let next = Achievements.threshold(level + 1)
        let progress = Double(log.xp - floor) / Double(max(1, next - floor))
        let earned = Achievements.earned(ctx).count

        return ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.10, blue: 0.42),
                                              Color(red: 0.42, green: 0.18, blue: 0.62),
                                              Color(red: 0.88, green: 0.36, blue: 0.52)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            // Soft "stars".
            Canvas { context, size in
                // Fixed pseudo-random positions so the stars don't jump on every redraw.
                for i in 0..<40 {
                    let a = Double(i) * 12.9898, b = Double(i) * 78.233
                    let fx = abs(sin(a) * 43758.5453).truncatingRemainder(dividingBy: 1)
                    let fy = abs(sin(b) * 24634.6345).truncatingRemainder(dividingBy: 1)
                    let r = 0.6 + 1.2 * abs(sin(a + b)).truncatingRemainder(dividingBy: 1)
                    let rect = CGRect(x: fx * size.width, y: fy * size.height, width: r, height: r)
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.5)))
                }
            }
            .allowsHitTesting(false)

            HStack(spacing: 26) {
                ZStack {
                    ProgressRing(progress: progress, lineWidth: 12,
                                 gradient: LinearGradient(colors: [.yellow, .orange, .pink], startPoint: .top, endPoint: .bottom))
                    VStack(spacing: 0) {
                        Text("Lv.\(level)").scaledFont(30, weight: .heavy, design: .rounded)
                        Text("\(log.xp) XP").scaledFont(11, weight: .medium).opacity(0.8)
                    }
                }
                .frame(width: 130, height: 130)

                VStack(alignment: .leading, spacing: 10) {
                    Text(Achievements.levelTitle(level).text)
                        .scaledFont(28, weight: .bold, design: .rounded)
                    Text(tr("距离 Lv.\(level + 1) 还差 \(max(0, next - log.xp)) XP · 已解锁 \(earned)/\(Achievements.all.count) 个成就",
                            "\(max(0, next - log.xp)) XP to Lv.\(level + 1) · \(earned)/\(Achievements.all.count) achievements"))
                        .scaledFont(12.5)
                        .opacity(0.85)
                    HStack(spacing: 10) {
                        heroStat("checkmark.seal.fill", "\(log.completedSessions)", tr("次放松", "sessions"))
                        heroStat("clock.fill", formatMinutes(log.relaxSeconds), tr("累计", "total"))
                        heroStat("flame.fill", "\(log.currentStreak())", tr("天连续", "day streak"))
                        heroStat("bolt.fill", "\(log.timelyResponses)", tr("次及时", "on time"))
                    }
                    Button {
                        fireTrigger += 1
                    } label: {
                        Label(tr("放个烟花", "Fireworks!"), systemImage: "sparkles")
                            .scaledFont(13, weight: .semibold)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Capsule().fill(Color.white.opacity(0.18)))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.35)))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .foregroundColor(.white)
            .padding(24)

            FireworksLayer(trigger: fireTrigger)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .frame(minHeight: 200)
        .shadow(color: Color.purple.opacity(0.25), radius: 16, y: 6)
    }

    private func heroStat(_ symbol: String, _ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: symbol).scaledFont(11)
                Text(value).scaledFont(15, weight: .bold, design: .rounded)
            }
            Text(label).scaledFont(10).opacity(0.75)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.12)))
    }

    // MARK: Heatmap

    private var heatmap: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // 12 weeks, Monday-first columns.
        let weekday = (cal.component(.weekday, from: today) + 5) % 7 // Monday = 0
        let start = cal.date(byAdding: .day, value: -(7 * 11 + weekday), to: today) ?? today
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(tr("放松打卡", "Relax calendar")).scaledFont(13, weight: .semibold)
                    Spacer()
                    HStack(spacing: 4) {
                        Text(tr("少", "less")).scaledFont(10).foregroundColor(.secondary)
                        ForEach(0..<4) { level in
                            RoundedRectangle(cornerRadius: 3).fill(Self.heat(level)).frame(width: 11, height: 11)
                        }
                        Text(tr("多", "more")).scaledFont(10).foregroundColor(.secondary)
                    }
                }
                HStack(alignment: .top, spacing: 4) {
                    VStack(alignment: .trailing, spacing: 4) {
                        ForEach(0..<7) { row in
                            Text(row % 2 == 0 ? WeekdayNames.short(WeekdayNames.mondayFirst[row]) : "")
                                .scaledFont(9)
                                .foregroundColor(.secondary)
                                .frame(height: 14)
                        }
                    }
                    ForEach(0..<12) { week in
                        VStack(spacing: 4) {
                            ForEach(0..<7) { row in
                                let day = cal.date(byAdding: .day, value: week * 7 + row, to: start) ?? start
                                let count = achievements.log.sessionDays[DayKey.string(for: day)] ?? 0
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(day > today ? Color.clear : Self.heat(min(3, count)))
                                    .frame(width: 14, height: 14)
                                    .help("\(DayKey.string(for: day)) · \(count)")
                            }
                        }
                    }
                }
            }
        }
    }

    private static func heat(_ level: Int) -> Color {
        switch level {
        case 0: return Color.primary.opacity(0.07)
        case 1: return Color(red: 0.55, green: 0.36, blue: 0.96).opacity(0.4)
        case 2: return Color(red: 0.55, green: 0.36, blue: 0.96).opacity(0.7)
        default: return Color(red: 0.55, green: 0.36, blue: 0.96)
        }
    }

    // MARK: Badges

    private func badges(_ ctx: AchievementContext) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("成就墙", "Achievements")).scaledFont(13, weight: .semibold)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), spacing: 14)], spacing: 14) {
                ForEach(Achievements.all) { a in
                    BadgeView(achievement: a,
                              unlockedAt: achievements.unlocked[a.id],
                              value: Achievements.value(a.metric, ctx),
                              isNew: fresh.contains(a.id))
                }
            }
        }
    }
}

struct BadgeView: View {
    let achievement: Achievement
    let unlockedAt: Date?
    let value: Int
    var isNew = false
    @State private var pulse = false

    private static let date: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    var body: some View {
        let unlocked = unlockedAt != nil
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(unlocked ? TierStyle.gradient(achievement.tier) : AnyShapeStyle(Color.primary.opacity(0.08)))
                    .frame(width: 64, height: 64)
                    .shadow(color: unlocked ? TierStyle.glow(achievement.tier).opacity(0.55) : .clear, radius: pulse ? 14 : 6)
                Image(systemName: achievement.symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(unlocked ? .white : .secondary)
                    .shadow(color: .black.opacity(unlocked ? 0.25 : 0), radius: 2, y: 1)
                if !unlocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .offset(x: 22, y: 22)
                }
            }
            .scaleEffect(pulse ? 1.08 : 1)
            Text(achievement.title.text)
                .scaledFont(13, weight: .semibold)
                .multilineTextAlignment(.center)
            Text(achievement.detail.text)
                .scaledFont(11)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let unlockedAt {
                Text(tr("\(achievement.tier.title) · \(Self.date.string(from: unlockedAt))",
                        "\(achievement.tier.title) · \(Self.date.string(from: unlockedAt))"))
                    .scaledFont(10)
                    .foregroundColor(.secondary)
            } else {
                ProgressView(value: min(1, Double(value) / Double(max(1, achievement.goal))))
                    .tint(Color(red: 0.55, green: 0.36, blue: 0.96))
                Text("\(min(value, achievement.goal)) / \(achievement.goal)")
                    .scaledFont(10)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isNew ? AnyShapeStyle(TierStyle.gradient(achievement.tier)) : AnyShapeStyle(Color.primary.opacity(0.08)),
                              lineWidth: isNew ? 2 : 1)
        )
        .opacity(unlocked ? 1 : 0.8)
        .onAppear {
            guard isNew else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatCount(5, autoreverses: true)) { pulse = true }
        }
    }
}
