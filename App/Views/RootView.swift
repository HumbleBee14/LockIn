import SwiftUI

enum Section: String, CaseIterable, Identifiable {
    case status = "Status"
    case schedule = "Schedule"
    case blockSets = "Block Sets"
    case settings = "Settings"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .status: return "shield.lefthalf.filled"
        case .schedule: return "calendar"
        case .blockSets: return "square.stack.3d.up"
        case .settings: return "gearshape"
        }
    }
}

struct RootView: View {
    @State private var selection: Section = .status
    @StateObject private var store = ScheduleStore(client: DaemonClient())
    @StateObject private var statusModel = StatusViewModel(client: DaemonClient())

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .listStyle(.sidebar)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.inkBase)
        }
        .task { await statusModel.refresh() }
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .status: StatusView(model: statusModel)
        case .schedule: ScheduleGridView(store: store, statusModel: statusModel)
        case .blockSets: BlockSetEditorView(store: store)
        case .settings: SettingsView(store: store)
        }
    }
}
