import SwiftUI
import AppKit

struct BlockSetEditorView: View {
    @ObservedObject var store: ScheduleStore
    @State private var selectedId: String?
    @State private var newDomain = ""
    @State private var importText = ""
    @State private var importURL = ""
    @State private var importing = false
    @State private var showingImport = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            editor
        }
        .sheet(isPresented: $showingImport) { importSheet }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Block Sets")
                .font(Theme.displayFont(18, .bold))
                .foregroundStyle(Theme.mist)
                .padding(.bottom, Theme.Spacing.xs)
            ForEach(store.config.blockSets, id: \.id) { set in
                Button {
                    selectedId = set.id
                } label: {
                    HStack {
                        Text(set.name).foregroundStyle(Theme.mist)
                        Spacer()
                        Text("\(set.domains.count)").foregroundStyle(Theme.mistDim).font(Theme.monoFont(11))
                    }
                    .padding(.vertical, 6).padding(.horizontal, Theme.Spacing.s)
                    .background(selectedId == set.id ? Theme.inkRaised : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            Divider().padding(.vertical, Theme.Spacing.s)
            Text("Add a preset")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.mistDim)
            ForEach(Preset.allCases) { preset in
                Button {
                    store.importPreset(preset)
                    selectedId = preset.rawValue
                    Task { _ = await store.commit() }
                } label: {
                    Label(preset.displayName, systemImage: "plus.circle")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
            }
            Spacer()
        }
        .frame(width: 200)
        .padding(Theme.Spacing.m)
        .background(Theme.inkBase)
    }

    @ViewBuilder private var editor: some View {
        if let id = selectedId, let idx = store.config.blockSets.firstIndex(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack {
                    Text(store.config.blockSets[idx].name)
                        .font(Theme.displayFont(20, .bold)).foregroundStyle(Theme.mist)
                    Spacer()
                    Button { showingImport = true } label: { Label("Import list", systemImage: "square.and.arrow.down") }
                        .buttonStyle(.bordered)
                }
                HStack {
                    TextField("Add domain (e.g. youtube.com)", text: $newDomain)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addDomain(idx) }
                    Button("Add") { addDomain(idx) }.tint(Theme.ember)
                }
                List {
                    ForEach(store.config.blockSets[idx].domains, id: \.self) { domain in
                        HStack {
                            Text(domain).font(Theme.monoFont(12)).foregroundStyle(Theme.mist)
                            Spacer()
                            Button(role: .destructive) {
                                store.config.blockSets[idx].domains.removeAll { $0 == domain }
                                Task { _ = await store.commit() }
                            } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(spacing: Theme.Spacing.m) {
                Image(systemName: "square.stack.3d.up").font(.system(size: 40)).foregroundStyle(Theme.mistDim)
                Text("Select or add a block set")
                    .font(Theme.displayFont(16, .medium)).foregroundStyle(Theme.mistDim)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var importSheet: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Import domains")
                .font(Theme.displayFont(18, .bold))
            Text("Paste one domain per line, or a hosts-file list. Comments and host prefixes are stripped automatically.")
                .font(.system(size: 12)).foregroundStyle(Theme.mistDim)
            TextEditor(text: $importText)
                .font(Theme.monoFont(12))
                .frame(height: 160)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.inkRaised))
            Divider()
            Text("…or fetch a public blocklist by URL")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.mistDim)
            HStack {
                TextField("https://…/hosts", text: $importURL)
                    .textFieldStyle(.roundedBorder)
                Button("Fetch") { fetchRemote() }
                    .disabled(importURL.isEmpty || importing)
            }
            if importing { ProgressView().controlSize(.small) }
            HStack {
                Spacer()
                Button("Cancel") { dismissImport() }
                Button("Import pasted") {
                    if let id = selectedId { store.importDomains(into: id, from: importText) }
                    Task { _ = await store.commit() }
                    dismissImport()
                }
                .buttonStyle(.borderedProminent).tint(Theme.ember)
            }
        }
        .padding(Theme.Spacing.l)
        .frame(width: 420)
    }

    private func dismissImport() {
        showingImport = false; importText = ""; importURL = ""
    }

    private func fetchRemote() {
        guard let id = selectedId, let url = URL(string: importURL) else { return }
        importing = true
        Task {
            _ = await store.importRemoteList(into: id, from: url)
            importing = false
            dismissImport()
        }
    }

    private func addDomain(_ idx: Int) {
        let parsed = ScheduleStore.parseDomainList(newDomain)
        for d in parsed where !store.config.blockSets[idx].domains.contains(d) {
            store.config.blockSets[idx].domains.append(d)
        }
        newDomain = ""
        Task { _ = await store.commit() }
    }
}
