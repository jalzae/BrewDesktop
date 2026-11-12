import SwiftUI

struct InstallSheet: View {
    @EnvironmentObject var store: BrewStore
    @Environment(\.dismiss) private var dismiss

    @State private var term = ""
    @State private var results: [SearchHit] = []
    @State private var searching = false
    @State private var selected: SearchHit?
    @State private var selectedInfo: InfoCard?

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            Divider()

            HSplitView {
                List {
                    if searching {
                        HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                    }
                    ForEach(results) { hit in
                        SearchRow(hit: hit)
                            .tag(hit.id)
                            .contentShape(Rectangle())
                            .onTapGesture { select(hit) }
                    }
                }
                .listStyle(.inset)
                .frame(minWidth: 260, idealWidth: 300)

                Group {
                    if let card = selectedInfo {
                        infoCard(card)
                    } else {
                        EmptyState(icon: "magnifyingglass", title: "Search formulae & casks",
                                   detail: "Type at least 2 characters to search Homebrew.")
                    }
                }
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 640, minHeight: 440)
        .task(id: term) {
            await debounceSearch()
        }
    }

    private var searchHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search packages to install…", text: $term)
                .textFieldStyle(.plain)
                .font(.title3)
                .onSubmit { Task { await debounceSearch(immediate: true) } }
            if !term.isEmpty {
                Button("Clear") { term = ""; results = []; selected = nil; selectedInfo = nil }
                    .controlSize(.small)
            }
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    private func debounceSearch(immediate: Bool = false) async {
        let query = term.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else {
            results = []
            return
        }
        if !immediate {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard term.trimmingCharacters(in: .whitespaces) == query else { return }
        }
        searching = true
        defer { searching = false }
        results = await store.search(query)
    }

    private func select(_ hit: SearchHit) {
        selected = hit
        selectedInfo = nil
        Task {
            selectedInfo = await fetchInfo(hit)
        }
    }

    private func fetchInfo(_ hit: SearchHit) async -> InfoCard? {
        let args = ["info", "--json=v2"] + (hit.kind == .cask ? ["--cask"] : []) + [hit.name]
        guard let result = try? await Shell.brew(args) else { return nil }
        return InfoCard.decode(raw: result.stdout, hit: hit)
    }

    @ViewBuilder
    private func infoCard(_ card: InfoCard) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(card.name).font(.title3.weight(.bold))
                        if let v = card.version {
                            Text(v).font(.body.monospaced()).foregroundStyle(.secondary)
                        }
                        if card.installed {
                            Badge("installed", color: .green)
                        }
                        Spacer()
                        if card.installed {
                            Button("Reinstall") {
                                dismiss()
                                store.reinstall(PackageEntry(
                                    id: card.kind == .cask ? "cask:\(card.name)" : card.name,
                                    name: card.name,
                                    kind: card.kind,
                                    desc: card.desc, homepage: card.homepage,
                                    version: card.version ?? "?", tap: "", outdated: false,
                                    pinned: false, installedOnRequest: true,
                                    dependencies: [], caveats: card.caveats,
                                    hasService: false, installedTime: nil, deprecated: false
                                ))
                            }
                        } else {
                            Button {
                                dismiss()
                                store.install(card.name, isCask: card.kind == .cask)
                            } label: {
                                Label("Install", systemImage: "arrow.down.circle")
                            }
                            .keyboardShortcut(.defaultAction)
                        }
                    }
                    if !card.desc.isEmpty {
                        Text(card.desc).foregroundStyle(.secondary)
                    }
                    if !card.homepage.isEmpty, let url = URL(string: card.homepage) {
                        Link(card.homepage, destination: url).font(.caption).lineLimit(1)
                    }
                }

                if !card.dependencies.isEmpty {
                    GroupBox("Dependencies") {
                        FlowLayout(deps: card.dependencies).padding(6)
                    }
                }

                if let caveats = card.caveats, !caveats.isEmpty {
                    GroupBox("Caveats") {
                        Text(caveats)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                    }
                }
            }
            .padding(14)
        }
    }
}

// MARK: - Info card

struct InfoCard {
    let name: String
    let kind: PackageEntry.Kind
    let desc: String
    let homepage: String
    let version: String?
    let dependencies: [String]
    let caveats: String?
    let installed: Bool

    static func decode(raw: String, hit: SearchHit) -> InfoCard? {
        guard let data = BrewJSON.payload(from: raw).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        if hit.kind == .cask, let cask = (obj["casks"] as? [[String: Any]])?.first {
            return InfoCard(
                name: cask["token"] as? String ?? hit.name,
                kind: .cask,
                desc: cask["desc"] as? String ?? "",
                homepage: cask["homepage"] as? String ?? "",
                version: cask["version"] as? String,
                dependencies: [],
                caveats: cask["caveats"] as? String,
                installed: cask["installed"] != nil
            )
        }
        if let f = (obj["formulae"] as? [[String: Any]])?.first {
            return InfoCard(
                name: f["name"] as? String ?? hit.name,
                kind: .formula,
                desc: f["desc"] as? String ?? "",
                homepage: f["homepage"] as? String ?? "",
                version: (f["versions"] as? [String: Any])?["stable"] as? String,
                dependencies: f["dependencies"] as? [String] ?? [],
                caveats: f["caveats"] as? String,
                installed: false
            )
        }
        return nil
    }
}

// MARK: - Search row

struct SearchRow: View {
    let hit: SearchHit

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: hit.kind == .cask ? "app.dashed" : "shippingbox")
                .foregroundStyle(hit.kind == .cask ? Color.purple : Color.indigo)
            Text(hit.name)
            Spacer()
            if hit.installed {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
        .padding(.vertical, 2)
    }
}
