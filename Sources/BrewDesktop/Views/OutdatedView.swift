import SwiftUI

struct OutdatedView: View {
    @EnvironmentObject var store: BrewStore
    @State private var selection = Set<String>()

    var body: some View {
        VStack(spacing: 0) {
            actionBar
            Divider()
            List(selection: $selection) {
                if store.loadingOutdated && store.outdated.isEmpty {
                    HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                }
                ForEach(store.filteredOutdated()) { entry in
                    HStack(spacing: 8) {
                        Image(systemName: entry.kind == .cask ? "app.dashed" : "shippingbox")
                            .foregroundStyle(entry.kind == .cask ? Color.purple : Color.indigo)
                            .frame(width: 16)
                        Text(entry.name).fontWeight(.medium)
                        Text("\(entry.installedVersions.joined(separator: ", ")) → \(entry.currentVersion)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        if entry.pinned {
                            Badge(entry.pinnedVersion.map { "pinned → \($0)" } ?? "pinned", color: .orange)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 2)
                    .tag(entry.id)
                    .contextMenu {
                        Button("Upgrade") { store.upgrade([entry.name]) }
                        Button("Copy Name") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(entry.name, forType: .string)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .refreshable { await store.loadOutdated() }
        }
        .overlay {
            if store.outdated.isEmpty && !store.loadingOutdated {
                EmptyState(icon: "checkmark.seal", title: "Everything is up to date")
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Text("\(store.outdated.count) outdated")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !selection.isEmpty {
                Text("\(selection.count) selected").font(.subheadline)
            }
            Spacer()
            Button("Select All") {
                selection = Set(store.filteredOutdated().map(\.id))
            }
            Button("Upgrade Selected") {
                let names = store.outdated.filter { selection.contains($0.id) }.map(\.name)
                store.upgrade(names.isEmpty ? [] : names)
            }
            .disabled(selection.isEmpty)
            Button {
                store.upgrade(store.outdated.filter { !$0.pinned }.map(\.name))
            } label: {
                Label("Upgrade All", systemImage: "arrow.up.circle")
            }
            .disabled(store.outdated.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
