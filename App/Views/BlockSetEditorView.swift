import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct BlockSetEditorView: View {
    @ObservedObject var store: ScheduleStore
    @State private var selectedId: String?
    @State private var newDomain = ""
    @State private var importText = ""
    @State private var importURL = ""
    @State private var importing = false
    @State private var showingImport = false
    @State private var showingNewSet = false
    @State private var newSetTitle = ""
    @State private var newSetMode: BlockSetMode = .blocklist
    @State private var hoveredId: String?
    @State private var pendingDelete: BlockSet?
    @State private var search = ""
    @State private var showingCapAlert = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            editor
        }
        .sheet(isPresented: $showingImport) { importSheet }
        .sheet(isPresented: $showingNewSet) { newSetSheet }
        .confirmationDialog(
            "Delete “\(pendingDelete?.name ?? "")”?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { confirmDelete() }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This removes the block set and its list. Schedules using it will need a new one.")
        }
        .alert("List is full", isPresented: $showingCapAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("A block set can hold up to \(BlockLimits.maxActiveDomains) sites. Remove some to add more.")
        }
    }

    private func itemCount(_ set: BlockSet) -> Int {
        set.domains.count + set.appBundleIds.count
    }

    private func modeHint(_ mode: BlockSetMode) -> String {
        mode == .allowlist
            ? "Only these are reachable. Everything else is blocked."
            : "These are blocked. Everything else stays reachable."
    }

    private func confirmDelete() {
        guard let set = pendingDelete else { return }
        if selectedId == set.id { selectedId = nil }
        store.removeBlockSet(id: set.id)
        Task { _ = await store.commit() }
        pendingDelete = nil
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Block Sets")
                .font(Theme.displayFont(18, .bold))
                .foregroundStyle(Theme.mist)
                .padding(.bottom, Theme.Spacing.s)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    ForEach(store.config.blockSets, id: \.id) { set in
                        setRow(set)
                    }
                }
            }
            Divider().padding(.vertical, Theme.Spacing.s)
            Button {
                newSetTitle = ""; newSetMode = .blocklist; showingNewSet = true
            } label: {
                Label("New Block Set", systemImage: "plus.circle")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
        }
        .frame(width: 200)
        .padding(Theme.Spacing.m)
        .background(Theme.inkBase)
    }

    private func setRow(_ set: BlockSet) -> some View {
        Button {
            selectedId = set.id
        } label: {
            HStack {
                Text(set.name).foregroundStyle(Theme.mist).lineLimit(1)
                Spacer()
                if hoveredId == set.id {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.ember)
                        .onTapGesture { pendingDelete = set }
                } else {
                    Text("\(itemCount(set))").foregroundStyle(Theme.mistDim).font(Theme.monoFont(11))
                }
            }
            .padding(.vertical, 6).padding(.horizontal, Theme.Spacing.s)
            .background(selectedId == set.id ? Theme.inkRaised : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredId = $0 ? set.id : (hoveredId == set.id ? nil : hoveredId) }
    }

    private var newSetSheet: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("New Block Set").font(Theme.displayFont(18, .bold))
            TextField("Name (e.g. Work Distractions)", text: $newSetTitle)
                .textFieldStyle(.roundedBorder)
            Picker("Mode", selection: $newSetMode) {
                Text("Blocklist").tag(BlockSetMode.blocklist)
                Text("Allowlist").tag(BlockSetMode.allowlist)
            }
            .pickerStyle(.radioGroup)
            Text(modeHint(newSetMode))
                .font(.system(size: 11)).foregroundStyle(Theme.mistDim)
            HStack {
                Spacer()
                Button("Cancel") { showingNewSet = false }
                Button("Create") {
                    let set = store.createBlockSet(title: newSetTitle, mode: newSetMode)
                    selectedId = set.id
                    Task { _ = await store.commit() }
                    showingNewSet = false
                }
                .buttonStyle(.borderedProminent).tint(Theme.ember)
                .disabled(newSetTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Theme.Spacing.l)
        .frame(width: 360)
    }

    @ViewBuilder private var editor: some View {
        if let id = selectedId, let idx = store.config.blockSets.firstIndex(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack {
                    Text(store.config.blockSets[idx].name)
                        .font(Theme.displayFont(20, .bold)).foregroundStyle(Theme.mist)
                    Spacer()
                    Button { exportSet(idx) } label: { Label("Export", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.bordered)
                        .disabled(store.config.blockSets[idx].domains.isEmpty)
                    Button { showingImport = true } label: { Label("Import list", systemImage: "square.and.arrow.down") }
                        .buttonStyle(.bordered)
                }
                Picker("Mode", selection: Binding(
                    get: { store.config.blockSets[idx].mode },
                    set: { store.setMode($0, forBlockSet: id); Task { _ = await store.commit() } })) {
                    Text("Blocklist").tag(BlockSetMode.blocklist)
                    Text("Allowlist").tag(BlockSetMode.allowlist)
                }
                .pickerStyle(.segmented)
                Text(modeHint(store.config.blockSets[idx].mode))
                    .font(.system(size: 11)).foregroundStyle(Theme.mistDim)
                HStack {
                    TextField("Add domain (e.g. youtube.com)", text: $newDomain)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addDomain(idx) }
                    Button("Add") { addDomain(idx) }.tint(Theme.ember)
                }

                let domains = store.config.blockSets[idx].domains
                HStack {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.mistDim)
                    TextField("Search this list", text: $search)
                        .textFieldStyle(.plain)
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless).foregroundStyle(Theme.mistDim)
                    }
                    Spacer()
                    Text("\(domains.count) site\(domains.count == 1 ? "" : "s")")
                        .font(.system(size: 11)).foregroundStyle(Theme.mistDim)
                }
                .padding(.horizontal, Theme.Spacing.s).padding(.vertical, 6)
                .background(Theme.inkSurface)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                let filtered = filteredDomains(domains)
                if !search.isEmpty && filtered.isEmpty {
                    Text("“\(search.trimmingCharacters(in: .whitespaces).lowercased())” is not in this list.")
                        .font(.system(size: 12)).foregroundStyle(Theme.mistDim)
                }
                List {
                    ForEach(filtered, id: \.self) { domain in
                        HStack {
                            Text(domain).font(Theme.monoFont(12)).foregroundStyle(Theme.mist)
                            Spacer()
                            Button(role: .destructive) {
                                store.removeDomain(domain, fromBlockSet: id)
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
            Text("Paste a list, hosts file, AdBlock filter, or CSV. The format is detected automatically.")
                .font(.system(size: 12)).foregroundStyle(Theme.mistDim)
            Label("Very large lists use more memory and can slow DNS. Keep blocklists focused.",
                  systemImage: "info.circle")
                .font(.system(size: 11)).foregroundStyle(Theme.mistDim)
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
            Button("Import from file…") { importFromFile() }
                .buttonStyle(.borderless)
            if importing { ProgressView().controlSize(.small) }
            HStack {
                Spacer()
                Button("Cancel") { dismissImport() }
                Button("Import pasted") {
                    if let id = selectedId {
                        let outcome = store.importDomains(into: id, from: importText)
                        if outcome.hitCap { showingCapAlert = true }
                    }
                    Task { _ = await store.commit() }
                    dismissImport()
                }
                .buttonStyle(.borderedProminent).tint(Theme.ember)
            }
        }
        .padding(Theme.Spacing.l)
        .frame(width: 420)
    }

    private func filteredDomains(_ domains: [String]) -> [String] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? domains : domains.filter { $0.contains(q) }
    }

    private func exportSet(_ idx: Int) {
        let set = store.config.blockSets[idx]
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(set.name).txt"
        if panel.runModal() == .OK, let url = panel.url {
            try? DomainListImporter.export(set.domains).write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func dismissImport() {
        showingImport = false; importText = ""; importURL = ""
    }

    private func importFromFile() {
        guard let id = selectedId else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .commaSeparatedText, .text, .data]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            _ = store.importFile(into: id, at: url)
            Task { _ = await store.commit() }
            dismissImport()
        }
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
        let id = store.config.blockSets[idx].id
        let parsed = ScheduleStore.parseDomainList(newDomain)
        let outcome = store.addDomains(parsed, toBlockSet: id)
        newDomain = ""
        if outcome.hitCap { showingCapAlert = true }
        if outcome.added > 0 { Task { _ = await store.commit() } }
    }
}
