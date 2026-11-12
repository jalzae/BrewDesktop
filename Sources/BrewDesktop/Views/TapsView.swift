import SwiftUI

struct TapsView: View {
    @EnvironmentObject var store: BrewStore
    @State private var newTap = ""
    @State private var showAddTap = false

    var body: some View {
        VStack(spacing: 0) {
            actionBar
            Divider()
            List {
                ForEach(store.filteredTaps()) { tap in
                    TapRow(tap: tap)
                        .contextMenu {
                            Button("Untap…") { store.untap(tap) }
                            Button("Copy Path") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(tap.path, forType: .string)
                            }
                        }
                }
            }
            .listStyle(.inset)
            .refreshable { await store.loadTaps() }
        }
        .sheet(isPresented: $showAddTap) { addTapSheet }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Text("\(store.taps.count) taps").font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Button {
                newTap = ""
                showAddTap = true
            } label: {
                Label("Add Tap", systemImage: "plus")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var addTapSheet: some View {
        VStack(spacing: 14) {
            Text("Add Tap").font(.headline)
            TextField("e.g. shivammathur/php or user/repo", text: $newTap)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
                .onSubmit { submit() }
            HStack {
                Button("Cancel") { showAddTap = false }
                Button("Add") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newTap.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }

    private func submit() {
        let repo = newTap.trimmingCharacters(in: .whitespaces)
        guard !repo.isEmpty else { return }
        showAddTap = false
        store.addTap(repo)
    }
}

struct TapRow: View {
    let tap: TapEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "spigot")
                .foregroundStyle(tap.official ? Color.teal : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(tap.name).fontWeight(.medium)
                    if tap.official { Badge("official", color: .teal) }
                }
                if !tap.remote.isEmpty {
                    Text(tap.remote).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                } else if !tap.path.isEmpty {
                    Text(tap.path).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(tap.formulaCount) formulae").font(.caption).foregroundStyle(.secondary)
                Text("\(tap.caskCount) casks").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
