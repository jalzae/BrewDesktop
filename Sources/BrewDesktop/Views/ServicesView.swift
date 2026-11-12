import SwiftUI

struct ServicesView: View {
    @EnvironmentObject var store: BrewStore

    var body: some View {
        VStack(spacing: 0) {
            summaryBar
            Divider()
            List {
                if store.loadingServices && store.services.isEmpty {
                    HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                }
                ForEach(store.filteredServices()) { svc in
                    ServiceRow(svc: svc)
                        .contextMenu { serviceMenu(svc) }
                }
            }
            .listStyle(.inset)
            .refreshable { await store.loadServices() }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard store.currentOp?.running != true else { continue }
                await store.loadServices()
            }
        }
        .overlay {
            if store.services.isEmpty && !store.loadingServices {
                EmptyState(icon: "play.circle", title: "No services", detail: "Install a formula that ships a service (e.g. redis) to manage it here.")
            }
        }
    }

    private var summaryBar: some View {
        HStack(spacing: 14) {
            Label("\(store.runningServiceCount) running", systemImage: "play.fill")
                .foregroundStyle(.green)
            Label("\(store.services.count - store.runningServiceCount) not running", systemImage: "pause.circle")
                .foregroundStyle(.secondary)
            Label("\(store.stats.registeredServices) registered with launchd", systemImage: "list.bullet.rectangle")
                .foregroundStyle(.secondary)
            Spacer()
            Picker("", selection: $store.serviceFilter) {
                ForEach(ServiceFilter.allCases) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
            Button {
                store.refreshAll()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func serviceMenu(_ svc: ServiceEntry) -> some View {
        Button("Start") { store.service("start", svc) }
        Button("Run (once, no login item)") { store.service("run", svc) }
        Divider()
        Button("Restart") { store.service("restart", svc) }
        Button("Stop") { store.service("stop", svc) }
        Button("Kill (hard signal)") { store.service("kill", svc) }
        Divider()
        Button("Copy plist path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(svc.file ?? "", forType: .string)
        }
        if let file = svc.file, !file.isEmpty {
            Button("Reveal plist in Finder") {
                NSWorkspace.shared.selectFile(expandingPath(file), inFileViewerRootedAtPath: "")
            }
        }
    }

    private func expandingPath(_ p: String) -> String {
        (p as NSString).expandingTildeInPath
    }
}

struct ServiceRow: View {
    @EnvironmentObject var store: BrewStore
    let svc: ServiceEntry

    var body: some View {
        HStack(spacing: 10) {
            StatusDot(status: svc.status)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(svc.name).fontWeight(.medium)
                    Text(svc.status.label)
                        .font(.caption)
                        .foregroundStyle(svc.status.isRunning ? .green : .secondary)
                    if svc.needsRoot { Badge("root", color: .red) }
                    if let code = svc.exitCode, code != 0 {
                        Badge("exit \(code)", color: .red)
                    }
                }
                if let file = svc.file, !file.isEmpty {
                    Text(file)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                if svc.status.isRunning {
                    Button("Restart") { store.service("restart", svc) }
                    Button("Stop") { store.service("stop", svc) }
                } else {
                    Button("Start") { store.service("start", svc) }
                }
            }
            .controlSize(.small)
        }
        .padding(.vertical, 3)
    }
}
