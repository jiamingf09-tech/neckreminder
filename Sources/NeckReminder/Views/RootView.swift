import SwiftUI
import NeckReminderCore

struct RootView: View {
    @ObservedObject var navigation: Navigation
    @EnvironmentObject var prefs: Preferences

    var body: some View {
        NavigationSplitView {
            List(selection: $navigation.section) {
                ForEach(AppSection.allCases) { section in
                    Label(section.title, systemImage: section.symbol)
                        .tag(section)
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 240)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        // All strings are computed with `tr`; rebuild the tree when the language changes.
        .id(prefs.language)
        .frame(minWidth: 760, minHeight: 540)
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.section ?? .overview {
        case .overview: OverviewView(navigation: navigation)
        case .relax: RelaxView()
        case .library: LibraryView()
        case .schedule: ScheduleView()
        case .settings: SettingsView()
        case .about: AboutView()
        }
    }
}
