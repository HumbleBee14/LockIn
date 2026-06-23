import SwiftUI

enum Section: String, CaseIterable, Identifiable {
    case quickLock = "Quick Lock"
    case schedule = "Schedule"
    case blockSets = "Block Sets"
    case settings = "Settings"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .quickLock: return "bolt.shield"
        case .schedule: return "calendar"
        case .blockSets: return "square.stack.3d.up"
        case .settings: return "gearshape"
        }
    }
}

struct RootView: View {
    @State private var selection: Section = .quickLock
    @StateObject private var store = ScheduleStore(client: DaemonClient())
    @StateObject private var statusModel = StatusViewModel(client: DaemonClient())
    private let poll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if statusModel.isActive {
                ActiveLockView(model: statusModel, client: DaemonClient())
            } else {
                splitView
            }
        }
        .background(Theme.inkBase)
        .task { await statusModel.refresh() }
        .onReceive(poll) { _ in Task { await statusModel.refresh() } }
    }

    private var splitView: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .listStyle(.sidebar)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.inkBase)
        }
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .quickLock: QuickLockView(store: store, statusModel: statusModel)
        case .schedule: ScheduleGridView(store: store, statusModel: statusModel)
        case .blockSets: BlockSetEditorView(store: store)
        case .settings: SettingsView(store: store)
        }
    }
}
