import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: BrewStore
    @State private var showInstallSheet = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .searchable(text: $store.query, placement: .toolbar, prompt: searchPrompt)
                .toolbar { toolbarContent }
        }
        .sheet(isPresented: $showInstallSheet) {
            InstallSheet()
                .environmentObject(store)
        }
        .sheet(isPresented: $store.showConsole) {
            ConsoleSheet(store: store)
                .interactiveDismissDisabled(store.currentOp?.running == true)
        }
        .navigationTitle(store.section.rawValue)
        .onReceive(NotificationCenter.default.publisher(for: .openInstallSheet)) { _ in
            showInstallSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshAll)) { _ in
            store.refreshAll()
        }
        .onChange(of: store.section) { _ in
            store.query = ""
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List {
            Section {
                ForEach(SidebarSection.allCases) { s in
                    NavigationLink(value: s) {
                        Label {
                            HStack {
                                Text(s.rawValue)
                                Spacer()
                                if s == .outdated && store.stats.outdatedCount > 0 {
                                    CountBadge(count: store.stats.outdatedCount, color: .orange)
                                }
                                if s == .services && store.runningServiceCount > 0 {
                                    CountBadge(count: store.runningServiceCount, color: .green)
                                }
                            }
                        } icon: {
                            Image(systemName: s.icon)
                        }
                    }
                    .tag(s)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var detail: some View {
        switch store.section {
        case .overview: OverviewView()
        case .installed: InstalledView()
        case .services: ServicesView()
        case .outdated: OutdatedView()
        case .taps: TapsView()
        case .cleanup: CleanupView()
        case .doctor: DoctorView()
        }
    }

    private var searchPrompt: String {
        switch store.section {
        case .installed: return "Search installed"
        case .services: return "Search services"
        case .outdated: return "Search outdated"
        case .taps: return "Search taps"
        default: return "Filter"
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if store.currentOp?.running == true {
                ProgressView().controlSize(.small)
            }
            Button {
                showInstallSheet = true
            } label: {
                Label("Install", systemImage: "plus")
            }
            .help("Install a formula or cask (⌘I)")

            Button {
                store.refreshAll()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Refresh everything (⌘R)")
        }
    }
}

struct CountBadge: View {
    let count: Int
    var color: Color = .accentColor

    var body: some View {
        Text("\(count)")
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.18), in: Capsule())
    }
}
