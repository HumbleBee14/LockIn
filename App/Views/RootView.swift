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
    @StateObject private var gate = InstallGate()
    @StateObject private var quickLockDraft = QuickLockDraft()
    private let poll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if statusModel.isActive {
                ActiveLockView(model: statusModel, store: store)
            } else if !statusModel.stateIsKnown && gate.installer.isReady() {
                // bias toward blocked: a REGISTERED daemon we can't reach may be holding a live lock —
                // never drop to controls. A not-yet-installed daemon falls through to the normal UI.
                DaemonUnreachableView()
            } else {
                splitView
            }
        }
        .background(Theme.inkBase)
        .task { await statusModel.refresh() }
        .onReceive(poll) { _ in Task { await statusModel.refresh() } }
        .sheet(isPresented: $gate.showingInstall) {
            InstallSheet(gate: gate)
        }
    }

    private var splitView: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.inkBase)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Section.allCases) { section in
                sidebarItem(section)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.top, Theme.Spacing.m)
        .frame(width: 200)
        .frame(maxHeight: .infinity)
        .background(Theme.inkBase)
    }

    private func sidebarItem(_ section: Section) -> some View {
        let on = selection == section
        return Button {
            selection = section
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: section.icon)
                    .frame(width: 18)
                    .foregroundStyle(on ? Theme.ember : Theme.mistDim)
                Text(section.rawValue)
                    .foregroundStyle(on ? Theme.mist : Theme.mistDim)
                Spacer()
            }
            .font(.system(size: 13, weight: on ? .semibold : .regular))
            .padding(.vertical, 7).padding(.horizontal, Theme.Spacing.s)
            .background(on ? Theme.inkRaised : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .quickLock: QuickLockView(store: store, statusModel: statusModel, gate: gate, draft: quickLockDraft)
        case .schedule: ScheduleGridView(store: store, statusModel: statusModel, gate: gate)
        case .blockSets: BlockSetEditorView(store: store)
        case .settings: SettingsView(store: store, client: DaemonClient())
        }
    }
}
