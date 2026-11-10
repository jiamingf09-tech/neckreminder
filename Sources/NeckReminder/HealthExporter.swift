import AppKit
import UniformTypeIdentifiers
import NeckReminderCore

/// Saves a CSV of daily computer-use time and neck-relax time.
enum HealthExporter {
    @MainActor
    static func present(stats: StatsStore, achievements: AchievementStore) {
        let csv = HealthExport.csv(days: stats.daysForExport(), log: achievements.log, chinese: L10n.isChinese)
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.allowsOtherFileTypes = false
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = "NeckReminder-health-\(DayKey.string(for: Date())).csv"
        panel.title = tr("导出健康数据", "Export health data")
        panel.prompt = tr("导出", "Export")
        panel.message = tr("最近 30 天的电脑使用时间和颈椎放松时间，可用 Numbers 或 Excel 打开。",
                           "The last 30 days of computer-use and neck-relax time, for Numbers or Excel.")

        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            let destination = url.pathExtension.lowercased() == "csv" ? url : url.appendingPathExtension("csv")
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    write(csv, to: destination)
                }
            }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }

    @MainActor
    private static func write(_ csv: String, to url: URL) {
        do {
            try ("\u{FEFF}" + csv).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert()
            alert.messageText = tr("导出失败", "Export failed")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
