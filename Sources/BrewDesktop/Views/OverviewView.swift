import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var store: BrewStore
    @State private var pendingAction: MaintenanceAction?

    private enum MaintenanceAction: String, Identifiable {
        case update, upgradeAll, cleanup

        var id: String { rawValue }

        var title: String {
            switch self {
            case .update: return "Run brew update?"
            case .upgradeAll: return "Upgrade all outdated packages?"
            case .cleanup: return "Run brew cleanup?"
            }
        }

        var detail: String {
            switch self {
            case .update: return "Refreshes Homebrew's tap metadata and formula definitions. May take a minute."
            case .upgradeAll: return "Upgrades every outdated formula and cask to its latest version."
            case .cleanup: return "Removes old versions and stale files from the Cellar. Free space estimate is shown in Cleanup."
            }
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 210), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LazyVGrid(columns: columns, spacing: 12) {
                    StatTile(label: "Homebrew", value: store.stats.brewVersion, icon: "software", color: .brown)
                    StatTile(label: "Prefix", value: store.stats.prefix, icon: "folder", color: .blue)
                    StatTile(label: "Formulae", value: "\(store.stats.formulaCount)", icon: "shippingbox", color: .indigo)
                    StatTile(label: "Casks", value: "\(store.stats.caskCount)", icon: "app", color: .purple)
                    StatTile(label: "Outdated", value: "\(store.stats.outdatedCount)", icon: "arrow.up.circle", color: .orange)
                    StatTile(label: "Services running", value: "\(store.runningServiceCount) / \(store.stats.registeredServices)", icon: "play.circle", color: .green)
                    StatTile(label: "Taps", value: "\(store.stats.tapCount)", icon: "spigot", color: .teal)
                    StatTile(label: "Cellar size", value: store.stats.cellarSize, icon: "internaldrive", color: .gray)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Maintenance")
                        .font(.headline)
                    HStack {
                        Button {
                            pendingAction = .update
                        } label: {
                            Label("brew update", systemImage: "arrow.triangle.2.circlepath")
                        }
                        Button {
                            pendingAction = .upgradeAll
                        } label: {
                            Label("Upgrade All", systemImage: "arrow.up.circle")
                        }
                        .disabled(store.outdated.isEmpty)
                        Button {
                            store.section = .doctor
                            store.runDoctor()
                        } label: {
                            Label("Doctor", systemImage: "cross.case")
                        }
                        Button {
                            pendingAction = .cleanup
                        } label: {
                            Label("Cleanup", systemImage: "trash")
                        }
                    }
                }

                if !store.outdated.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Outdated")
                            .font(.headline)
                        ForEach(store.outdated.prefix(8)) { o in
                            HStack {
                                Text(o.name).fontWeight(.medium)
                                Text("\(o.installedVersions.joined(separator: ", ")) → \(o.currentVersion)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                if o.pinned { Badge("pinned", color: .orange) }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { store.section = .outdated }
                        }
                        if store.outdated.count > 8 {
                            Button("Show all \(store.outdated.count)…") { store.section = .outdated }
                        }
                    }
                }

                if !store.services.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Services")
                                .font(.headline)
                            Text("\(store.runningServiceCount) running, \(store.services.count - store.runningServiceCount) not running")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Manage all…") { store.section = .services }
                                .controlSize(.small)
                        }
                        ForEach(store.services) { s in
                            HStack {
                                StatusDot(status: s.status)
                                Text(s.name).fontWeight(.medium)
                                Text(s.status.label)
                                    .font(.caption)
                                    .foregroundStyle(s.status.isRunning ? .green : .secondary)
                                Spacer()
                                if s.status.isRunning {
                                    Button("Restart") { store.service("restart", s) }
                                        .controlSize(.small)
                                    Button("Stop") { store.service("stop", s) }
                                        .controlSize(.small)
                                } else {
                                    Button("Start") { store.service("start", s) }
                                        .controlSize(.small)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                    }
                }
            }
            .padding(18)
        }
        .confirmationDialog(
            pendingAction?.title ?? "",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Run") {
                switch pendingAction {
                case .update: store.brewUpdate()
                case .upgradeAll: store.upgrade(store.outdated.map(\.name))
                case .cleanup:
                    store.section = .cleanup
                    store.runCleanup()
                case nil: break
                }
                pendingAction = nil
            }
            Button("Cancel", role: .cancel) { pendingAction = nil }
        } message: {
            Text(pendingAction?.detail ?? "")
        }
    }
}
