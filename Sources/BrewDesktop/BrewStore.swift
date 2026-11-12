import Foundation
import SwiftUI

enum ServiceFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case running = "Running"
    case stopped = "Not running"

    var id: String { rawValue }

    func matches(_ svc: ServiceEntry) -> Bool {
        switch self {
        case .all: return true
        case .running: return svc.status.isRunning
        case .stopped: return !svc.status.isRunning
        }
    }
}

enum SidebarSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case installed = "Installed"
    case services = "Services"
    case outdated = "Outdated"
    case taps = "Taps"
    case cleanup = "Cleanup"
    case doctor = "Doctor"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "gauge"
        case .installed: return "shippingbox"
        case .services: return "play.circle"
        case .outdated: return "arrow.up.circle"
        case .taps: return "spigot"
        case .cleanup: return "trash"
        case .doctor: return "cross.case"
        }
    }
}

@MainActor
final class BrewStore: ObservableObject {

    // MARK: Navigation / filtering

    @Published var section: SidebarSection = .overview
    @Published var query = ""
    @Published var packageFilter: PackageEntry.Kind?
    @Published var serviceFilter: ServiceFilter = .all

    // MARK: Data

    @Published var packages: [PackageEntry] = []
    @Published var services: [ServiceEntry] = []
    @Published var outdated: [OutdatedEntry] = []
    @Published var taps: [TapEntry] = []
    @Published var stats = BrewStats()
    @Published var cleanupReport = CleanupReport()
    @Published var doctorText = ""
    @Published var doctorOK: Bool?

    @Published var loadingList = false
    @Published var loadingServices = false
    @Published var loadingOutdated = false

    /// Names of packages already installed (formula plain name + "cask:token").
    var installedNames: Set<String> {
        Set(packages.map(\.id))
    }

    // MARK: Console

    @Published var currentOp: RunningOp?
    @Published var showConsole = false
    /// Set when `brew update` fails on a removed tap ("does not exist! Run `brew untap X`").
    @Published var brokenTap: String?
    private var currentProcessCancel: (() -> Void)?

    // MARK: Loaders

    func refreshAll() {
        Task {
            await loadPackages()
            await loadServices()
            await loadOutdated()
            await loadTaps()
            await loadStats()
        }
    }

    func loadPackages() async {
        loadingList = true
        defer { loadingList = false }
        if let result = try? await Shell.brew(["info", "--json=v2", "--installed"]) {
            packages = (try? BrewParser.parseInstalledPackages(raw: result.stdout)) ?? packages
        }
    }

    func loadServices() async {
        loadingServices = true
        defer { loadingServices = false }
        if let result = try? await Shell.brew(["services", "list", "--json"]) {
            services = (try? BrewParser.parseServices(raw: result.stdout)) ?? services
        }
        stats.runningServices = services.filter { $0.status.isRunning }.count
        stats.registeredServices = services.filter { $0.status.isRegistered }.count
    }

    func loadOutdated() async {
        loadingOutdated = true
        defer { loadingOutdated = false }
        if let result = try? await Shell.brew(["outdated", "--json=v2", "--verbose"]) {
            outdated = (try? BrewParser.parseOutdated(raw: result.stdout)) ?? outdated
            stats.outdatedCount = outdated.count
        }
    }

    func loadTaps() async {
        if let result = try? await Shell.brew(["tap-info", "--json=v1", "--installed"]) {
            taps = (try? BrewParser.parseTaps(raw: result.stdout)) ?? taps
            stats.tapCount = taps.count
        }
    }

    func loadStats() async {
        if let v = try? await Shell.brew(["--version"]) {
            stats.brewVersion = BrewParser.parseVersion(v.stdout)
        }
        if let p = try? await Shell.brew(["--prefix"]) {
            stats.prefix = p.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let c = try? await Shell.brew(["--cellar"]) {
            stats.cellar = c.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        stats.formulaCount = packages.filter { $0.kind == .formula }.count
        stats.caskCount = packages.filter { $0.kind == .cask }.count
        stats.outdatedCount = outdated.count
        stats.tapCount = taps.count
        // Cellar disk usage is slow; run detached so stats stay responsive.
        Task.detached { [stats] in
            let prefix = await MainActor.run { stats.prefix }
            if let du = try? await Shell.run("/usr/bin/du", ["-sh", prefix + "/Cellar"]) {
                let size = du.stdout.split(separator: "\t").first.map(String.init) ?? "?"
                await MainActor.run { self.stats.cellarSize = size }
            } else {
                await MainActor.run { self.stats.cellarSize = "?" }
            }
        }
    }

    func runDoctor() {
        perform(title: "brew doctor") {
            let result = try await Shell.brew(["doctor"]) { chunk in self.appendLog(chunk) }
            self.doctorText = result.stdout + result.stderr
            self.doctorOK = true
        } onError: { message in
            self.doctorText = message
            self.doctorOK = false
        }
    }

    func analyzeCleanup() {
        perform(title: "Scanning for cleanable files") {
            let result = try await Shell.brew(["cleanup", "-n"]) { chunk in self.appendLog(chunk) }
            self.cleanupReport = BrewParser.parseCleanupDryRun(result.stdout)
        }
    }

    func runCleanup() {
        perform(title: "brew cleanup") {
            let result = try await Shell.brew(["cleanup"]) { chunk in self.appendLog(chunk) }
            self.appendLog("\n✅ \(result.stdout.split(separator: "\n").last ?? "done")\n")
        } onFinish: {
            Task { await self.loadStats(); await self.analyzeCleanupQuiet() }
        }
    }

    private func analyzeCleanupQuiet() async {
        if let result = try? await Shell.brew(["cleanup", "-n"]) {
            cleanupReport = BrewParser.parseCleanupDryRun(result.stdout)
        }
    }

    // MARK: Search & install

    func search(_ term: String) async -> [SearchHit] {
        guard term.count >= 2 else { return [] }
        guard let result = try? await Shell.brew(["search", term]) else { return [] }
        let hits = BrewParser.parseSearch(result.stdout)
        let installed = installedNames
        return hits.map { h in
            let isInstalled = packages.contains { $0.name == h.name || $0.id == "cask:\(h.name)" }
            return SearchHit(name: h.name, kind: h.kind, installed: isInstalled)
        }
    }

    func install(_ name: String, isCask: Bool) {
        let args = ["install"] + (isCask ? ["--cask"] : []) + [name]
        perform(title: "Installing \(name)") {
            _ = try await Shell.brew(args) { chunk in self.appendLog(chunk) }
            self.appendLog("\n✅ \(name) installed\n")
        } onFinish: {
            Task {
                await self.loadPackages()
                await self.loadServices()
                await self.loadStats()
            }
        }
    }

    func uninstall(_ pkg: PackageEntry, zap: Bool = false) {
        let args = ["uninstall"] + (pkg.kind == .cask ? ["--cask"] : []) + (zap ? ["--zap"] : []) + [pkg.name]
        perform(title: "Uninstalling \(pkg.name)") {
            _ = try await Shell.brew(args) { chunk in self.appendLog(chunk) }
            self.appendLog("\n✅ \(pkg.name) uninstalled\n")
        } onFinish: {
            Task {
                await self.loadPackages()
                await self.loadStats()
            }
        }
    }

    func upgrade(_ names: [String]) {
        guard !names.isEmpty else { return }
        let pretty = names.count <= 3 ? names.joined(separator: ", ") : "\(names.count) packages"
        perform(title: "Upgrading \(pretty)") {
            _ = try await Shell.brew(["upgrade"] + names) { chunk in self.appendLog(chunk) }
            self.appendLog("\n✅ Upgrade finished\n")
        } onFinish: {
            Task {
                await self.loadPackages()
                await self.loadOutdated()
                await self.loadStats()
            }
        }
    }

    func reinstall(_ pkg: PackageEntry) {
        let args = ["reinstall"] + (pkg.kind == .cask ? ["--cask"] : []) + [pkg.name]
        perform(title: "Reinstalling \(pkg.name)") {
            _ = try await Shell.brew(args) { chunk in self.appendLog(chunk) }
            self.appendLog("\n✅ \(pkg.name) reinstalled\n")
        } onFinish: {
            Task { await self.loadPackages() }
        }
    }

    func setPinned(_ pkg: PackageEntry, pinned: Bool) {
        perform(title: "\(pinned ? "Pinning" : "Unpinning") \(pkg.name)") {
            _ = try await Shell.brew([pinned ? "pin" : "unpin", pkg.name])
        } onFinish: {
            Task { await self.loadPackages() }
        }
    }

    func brewUpdate() {
        perform(title: "brew update") {
            do {
                _ = try await Shell.run(Shell.brewPath, ["update"], environment: Self.updateEnv) { chunk in
                    self.appendLog(chunk)
                    self.detectBrokenTap(chunk)
                }
                self.appendLog("\n✅ Homebrew updated\n")
            } catch let error as LocalizedError {
                self.detectBrokenTap(error.errorDescription ?? "")
                throw error
            }
        } onFinish: {
            Task {
                await self.loadOutdated()
                await self.loadPackages()
                await self.loadStats()
            }
        }
    }

    private func detectBrokenTap(_ text: String) {
        guard brokenTap == nil,
              let range = text.range(of: #"does not exist! Run `brew untap (\S+)`"#, options: .regularExpression)
        else { return }
        // Extract the tap name from the matched suggestion.
        let suggestion = text[range]
        if let nameStart = suggestion.range(of: "untap ") {
            brokenTap = String(suggestion[nameStart.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "`"))
        }
    }

    /// Remove a dead tap Homebrew itself recommended removing, then retry update.
    func fixBrokenTap() {
        guard let tap = brokenTap else { return }
        brokenTap = nil
        perform(title: "Untapping broken tap \(tap)") {
            _ = try await Shell.brew(["untap", tap]) { chunk in self.appendLog(chunk) }
            self.appendLog("\n✅ Removed \(tap)\n\nRetrying brew update…\n")
            _ = try await Shell.run(Shell.brewPath, ["update"], environment: Self.updateEnv) { chunk in self.appendLog(chunk) }
            self.appendLog("\n✅ Homebrew updated\n")
        } onFinish: {
            Task {
                await self.loadTaps()
                await self.loadOutdated()
                await self.loadStats()
            }
        }
    }

    private static var updateEnv: [String: String] {
        var env = Shell.baseEnvironment
        env.removeValue(forKey: "HOMEBREW_NO_AUTO_UPDATE")
        return env
    }

    // MARK: Services

    func service(_ action: String, _ service: ServiceEntry) {
        let args = ["services", action, service.name]
        let verb = action.capitalized
        perform(title: "\(verb) service \(service.name)") {
            if service.needsRoot {
                self.appendLog("🔐 Service runs as root — requesting administrator privileges…\n")
                let cmd = "\(Shell.brewPath) services \(action) \(service.name)"
                let result = try await Shell.runElevated(cmd)
                self.appendLog(result.stdout)
            } else {
                let result = try await Shell.brew(args) { chunk in self.appendLog(chunk) }
                self.appendLog(result.stdout)
            }
            self.appendLog("\n✅ \(service.name) \(verb.lowercased())d\n")
        } onFinish: {
            // launchctl needs a beat before the new status shows up.
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await self.loadServices()
            }
        }
    }

    // MARK: Taps

    func addTap(_ repo: String) {
        perform(title: "Adding tap \(repo)") {
            _ = try await Shell.brew(["tap", repo]) { chunk in self.appendLog(chunk) }
            self.appendLog("\n✅ Tapped \(repo)\n")
        } onFinish: {
            Task { await self.loadTaps() }
        }
    }

    func untap(_ tap: TapEntry) {
        perform(title: "Untapping \(tap.name)") {
            _ = try await Shell.brew(["untap", tap.name]) { chunk in self.appendLog(chunk) }
            self.appendLog("\n✅ Untapped \(tap.name)\n")
        } onFinish: {
            Task { await self.loadTaps() }
        }
    }

    // MARK: Console plumbing

    /// Run an operation with the console sheet visible; log streamed live.
    func perform(
        title: String,
        _ body: @escaping () async throws -> Void,
        onError: ((String) -> Void)? = nil,
        onFinish: (() -> Void)? = nil
    ) {
        guard currentOp == nil || currentOp?.running != true else { return }
        currentOp = RunningOp(title: title, running: true)
        showConsole = true

        let task = Task {
            do {
                try await body()
                self.finishOp(failed: false)
            } catch is CancellationError {
                self.appendLog("\n⚠️ Cancelled\n")
                self.finishOp(failed: true)
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.appendLog("\n❌ \(message)\n")
                onError?(message)
                self.finishOp(failed: true)
            }
            onFinish?()
        }
        currentProcessCancel = { task.cancel() }
    }

    func cancelOp() {
        currentProcessCancel?()
    }

    func dismissConsole() {
        showConsole = false
        currentOp = nil
    }

    private func finishOp(failed: Bool) {
        currentOp?.running = false
        currentOp?.failed = failed
        currentProcessCancel = nil
    }

    func appendLog(_ chunk: String) {
        currentOp?.log += chunk
    }

    // MARK: Filtering

    func filteredPackages() -> [PackageEntry] {
        var list = packages
        if let filter = packageFilter {
            list = list.filter { $0.kind == filter }
        }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter { $0.searchBlob.contains(q) }
        }
        return list
    }

    func filteredServices() -> [ServiceEntry] {
        var list = services.filter { serviceFilter.matches($0) }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter { $0.name.lowercased().contains(q) }
        }
        return list
    }

    func filteredOutdated() -> [OutdatedEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return outdated }
        return outdated.filter { $0.name.lowercased().contains(q) }
    }

    func filteredTaps() -> [TapEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return taps }
        return taps.filter { $0.name.lowercased().contains(q) }
    }

    var runningServiceCount: Int { services.filter { $0.status.isRunning }.count }
}
