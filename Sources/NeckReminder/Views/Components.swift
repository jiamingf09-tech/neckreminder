import AppKit
import SwiftUI
import NeckReminderCore

enum Palette {
    static let accent = Color(red: 0.13, green: 0.68, blue: 0.62)
    static let accent2 = Color(red: 0.12, green: 0.55, blue: 0.85)
    static let gradient = LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)

    static func color(for state: PresenceState) -> Color {
        switch state {
        case .active: return .green
        case .passive: return .blue
        case .away: return .gray
        }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            )
    }
}

struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 14
    var gradient: LinearGradient = Palette.gradient

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: progress)
        }
    }
}

struct StatTile: View {
    let symbol: String
    let title: String
    let value: String

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: symbol)
                    .scaledFont(10.5)
                    .foregroundColor(.secondary)
                Text(value)
                    .scaledFont(22, weight: .semibold, design: .rounded)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }
}

struct PageHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).scaledFont(26, weight: .bold, design: .rounded)
            if let subtitle {
                Text(subtitle).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .scaledFont(13, weight: .medium)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .foregroundColor(selected ? .white : .primary)
                .background(Capsule().fill(selected ? AnyShapeStyle(Palette.gradient) : AnyShapeStyle(Color.primary.opacity(0.07))))
        }
        .buttonStyle(.plain)
    }
}

struct WarningBox<Actions: View>: View {
    let text: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            actions
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
    }
}

extension NotificationManager.Status {
    var label: String {
        switch self {
        case .unknown: return tr("检查中…", "Checking…")
        case .notDetermined: return tr("尚未授权", "Not requested yet")
        case .denied: return tr("已被拒绝", "Denied")
        case .authorized: return tr("已允许", "Allowed")
        case .alertsOff: return tr("已允许，但提醒样式为“无”", "Allowed, but alert style is None")
        case .unavailable: return tr("不可用（需以 .app 运行）", "Unavailable (run as .app)")
        }
    }
}
