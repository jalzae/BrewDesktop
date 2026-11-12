import SwiftUI

struct InstalledView: View {
    @EnvironmentObject var store: BrewStore
    @State private var selection: PackageEntry.ID?

    private var selected: PackageEntry? {
        store.packages.first { $0.id == selection }
    }

    var body: some View {
        HSplitView {
            List(selection: $selection) {
                filterPicker

                if store.loadingList && store.packages.isEmpty {
                    HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                }

                ForEach(store.filteredPackages()) { pkg in
                    PackageRow(pkg: pkg)
                        .tag(pkg.id)
                        .contextMenu { packageMenu(pkg) }
                }
            }
            .listStyle(.inset)
            .frame(minWidth: 420)

            Group {
                if let selected {
                    PackageDetailView(pkg: selected)
                } else {
                    EmptyState(icon: "shippingbox", title: "No package selected",
                               detail: "Select a formula or cask to inspect it.")
                }
            }
            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { if selection == nil { selection = store.filteredPackages().first?.id } }
        .confirmationDialog(
            uninstallTitle,
            isPresented: Binding(get: { pendingUninstall != nil }, set: { if !$0 { pendingUninstall = nil } })
        ) {
            Button("Uninstall \(pendingUninstall?.name ?? "")", role: .destructive) {
                if let pkg = pendingUninstall { store.uninstall(pkg, zap: pendingZap) }
                pendingUninstall = nil
            }
            Button("Cancel", role: .cancel) { pendingUninstall = nil }
        } message: {
            Text("Dependencies that require it may break. You can reinstall later.")
        }
    }

    private var uninstallTitle: String {
        pendingZap ? "Uninstall \(pendingUninstall?.name ?? "") and delete all files (zap)?"
                   : "Uninstall \(pendingUninstall?.name ?? "")?"
    }

    private var filterPicker: some View {
        Picker("", selection: $store.packageFilter) {
            Text("All").tag(PackageEntry.Kind?.none)
            Text("Formulae").tag(PackageEntry.Kind?.some(.formula))
            Text("Casks").tag(PackageEntry.Kind?.some(.cask))
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func packageMenu(_ pkg: PackageEntry) -> some View {
        Button("Show Info") { selection = pkg.id }
        Divider()
        if pkg.outdated {
            Button("Upgrade") { store.upgrade([pkg.name]) }
        }
        Button("Reinstall") { store.reinstall(pkg) }
        Divider()
        if pkg.kind == .formula {
            Button(pkg.pinned ? "Unpin" : "Pin") { store.setPinned(pkg, pinned: !pkg.pinned) }
        }
        Button("Open Homepage") {
            if let url = URL(string: pkg.homepage), !pkg.homepage.isEmpty {
                NSWorkspace.shared.open(url)
            }
        }
        Button("Copy Name") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(pkg.name, forType: .string) }
        Divider()
        Button("Uninstall…") { confirmUninstall(pkg, zap: false) }
        if pkg.kind == .cask {
            Button("Uninstall + Zap…") { confirmUninstall(pkg, zap: true) }
        }
    }

    @State private var pendingUninstall: PackageEntry?
    @State private var pendingZap = false

    private func confirmUninstall(_ pkg: PackageEntry, zap: Bool) {
        pendingUninstall = pkg
        pendingZap = zap
    }
}

struct PackageRow: View {
    let pkg: PackageEntry

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: pkg.kind == .cask ? "app.dashed" : "shippingbox")
                .foregroundStyle(pkg.kind == .cask ? Color.purple : Color.indigo)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(pkg.name).fontWeight(.medium)
                    Text(pkg.version).font(.caption.monospaced()).foregroundStyle(.secondary)
                    if pkg.outdated { Badge("↑ update", color: .orange) }
                    if pkg.pinned { Badge("pinned", color: .orange) }
                    if pkg.hasService { Badge("service", color: .green) }
                    if pkg.deprecated { Badge("deprecated", color: .red) }
                    if pkg.isDependencyOnly { Badge("dep", color: .gray) }
                }
                if !pkg.desc.isEmpty {
                    Text(pkg.desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}
