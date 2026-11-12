import Foundation

/// Pure parsing layer — everything here is testable without touching `brew`.
enum BrewParser {

    // MARK: brew info --json=v2 --installed

    private struct InfoResponse: Decodable {
        struct Formula: Decodable {
            struct Installed: Decodable {
                let version: String?
                let installed_on_request: Bool?
                let time: Int64?
                let pinned: Bool?
            }
            let name: String
            let full_name: String?
            let desc: String?
            let homepage: String?
            let tap: String?
            let outdated: Bool?
            let pinned: Bool?
            let caveats: String?
            let deprecated: Bool?
            let service: ServiceDef?
            let dependencies: [String]?
            let installed: [Installed]?
            let linked_keg: String?
            struct ServiceDef: Decodable {}
        }
        struct Cask: Decodable {
            let token: String?
            let name: [String]?
            let desc: String?
            let homepage: String?
            let tap: String?
            let version: String?
            let installed: String?
            let installed_time: Double?
            let outdated: Bool?
            let pinned: Bool?
            let caveats: String?
            let deprecated: Bool?
        }
        let formulae: [Formula]?
        let casks: [Cask]?
    }

    static func parseInstalledPackages(raw: String) throws -> [PackageEntry] {
        let payload = BrewJSON.payload(from: raw)
        guard let data = payload.data(using: .utf8) else { return [] }
        let response = try JSONDecoder().decode(InfoResponse.self, from: data)
        var result: [PackageEntry] = []

        for f in response.formulae ?? [] {
            let inst = f.installed?.last
            let version = inst?.version ?? f.linked_keg ?? "?"
            let onRequest = inst?.installed_on_request ?? true
            let date = inst?.time.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            result.append(PackageEntry(
                id: f.full_name ?? f.name,
                name: f.name,
                kind: .formula,
                desc: f.desc ?? "",
                homepage: f.homepage ?? "",
                version: version,
                tap: f.tap ?? "",
                outdated: f.outdated ?? false,
                pinned: f.pinned ?? inst?.pinned ?? false,
                installedOnRequest: onRequest,
                dependencies: f.dependencies ?? [],
                caveats: f.caveats,
                hasService: f.service != nil,
                installedTime: date,
                deprecated: f.deprecated ?? false
            ))
        }

        for c in response.casks ?? [] {
            let token = c.token ?? c.name?.first ?? "?"
            let date = c.installed_time.map { Date(timeIntervalSince1970: $0) }
            result.append(PackageEntry(
                id: "cask:\(token)",
                name: token,
                kind: .cask,
                desc: c.desc ?? c.name?.first ?? "",
                homepage: c.homepage ?? "",
                version: c.installed ?? c.version ?? "?",
                tap: c.tap ?? "",
                outdated: c.outdated ?? false,
                pinned: c.pinned ?? false,
                installedOnRequest: true,
                dependencies: [],
                caveats: c.caveats,
                hasService: false,
                installedTime: date,
                deprecated: c.deprecated ?? false
            ))
        }
        return result.sorted { $0.name < $1.name }
    }

    // MARK: brew services list --json

    private struct ServiceJSON: Decodable {
        let name: String
        let status: String?
        let user: String?
        let file: String?
        let exit_code: Int?
    }

    static func parseServices(raw: String) throws -> [ServiceEntry] {
        let payload = BrewJSON.payload(from: raw)
        guard let data = payload.data(using: .utf8) else { return [] }
        let decoded = try JSONDecoder().decode([ServiceJSON].self, from: data)
        return decoded.map { s in
            ServiceEntry(
                name: s.name,
                status: ServiceStatus(rawValue: s.status ?? "none") ?? .unknown,
                user: s.user,
                file: s.file,
                exitCode: s.exit_code
            )
        }
        .sorted { a, b in
            if a.status.isRunning != b.status.isRunning { return a.status.isRunning && !b.status.isRunning }
            return a.name < b.name
        }
    }

    // MARK: brew outdated --json=v2

    private struct OutdatedResponse: Decodable {
        struct Item: Decodable {
            let name: String
            let installed_versions: [String]?
            let current_version: String?
            let pinned: Bool?
            let pinned_version: String?
        }
        let formulae: [Item]?
        let casks: [Item]?
    }

    static func parseOutdated(raw: String) throws -> [OutdatedEntry] {
        let payload = BrewJSON.payload(from: raw)
        guard let data = payload.data(using: .utf8) else { return [] }
        let response = try JSONDecoder().decode(OutdatedResponse.self, from: data)
        var result: [OutdatedEntry] = []
        for f in response.formulae ?? [] {
            result.append(OutdatedEntry(
                name: f.name,
                installedVersions: f.installed_versions ?? [],
                currentVersion: f.current_version ?? "?",
                pinned: f.pinned ?? false,
                pinnedVersion: f.pinned_version,
                kind: .formula
            ))
        }
        for c in response.casks ?? [] {
            result.append(OutdatedEntry(
                name: c.name,
                installedVersions: c.installed_versions ?? [],
                currentVersion: c.current_version ?? "?",
                pinned: c.pinned ?? false,
                pinnedVersion: c.pinned_version,
                kind: .cask
            ))
        }
        return result
    }

    // MARK: brew tap-info --json=v1 --installed

    private struct TapJSON: Decodable {
        let name: String
        let path: String?
        let remote: String?
        let official: Bool?
        let formula_names: [String]?
        let cask_tokens: [String]?
    }

    static func parseTaps(raw: String) throws -> [TapEntry] {
        let payload = BrewJSON.payload(from: raw)
        guard let data = payload.data(using: .utf8) else { return [] }
        let decoded = try JSONDecoder().decode([TapJSON].self, from: data)
        return decoded.map { t in
            TapEntry(
                name: t.name,
                path: t.path ?? "",
                remote: t.remote ?? "",
                official: t.official ?? false,
                formulaCount: t.formula_names?.count ?? 0,
                caskCount: t.cask_tokens?.count ?? 0
            )
        }
        .sorted { $0.name < $1.name }
    }

    // MARK: brew search <term>

    static func parseSearch(_ raw: String) -> [SearchHit] {
        var section: PackageEntry.Kind?
        var hits: [SearchHit] = []
        var seen = Set<String>()

        for line in raw.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("==>") {
                if trimmed.lowercased().contains("formula") { section = .formula }
                else if trimmed.lowercased().contains("cask") { section = .cask }
                else { section = nil }
                continue
            }
            if trimmed.hasPrefix("Error") || trimmed.hasPrefix("Usage") { continue }
            let name = trimmed
            guard !name.isEmpty, name.hasPrefix("/") == false else { continue }
            let kind = section ?? .formula
            let id = "\(kind.rawValue):\(name)"
            if seen.insert(id).inserted {
                hits.append(SearchHit(name: name, kind: kind, installed: false))
            }
        }
        return hits
    }

    // MARK: brew cleanup -n

    static func parseCleanupDryRun(_ raw: String) -> CleanupReport {
        var items: [String] = []
        var freeSpace = ""
        for line in raw.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Would remove:") {
                items.append(String(trimmed.dropFirst("Would remove:".count)).trimmingCharacters(in: .whitespaces))
            } else if trimmed.lowercased().contains("would free") {
                // "==> This operation would free approximately 1.2GB of disk space."
                if let range = trimmed.range(of: "approximately") {
                    let tail = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                    freeSpace = tail.components(separatedBy: " of disk").first ?? tail
                }
            }
        }
        return CleanupReport(items: items, freeSpace: freeSpace)
    }

    // MARK: brew --version

    static func parseVersion(_ raw: String) -> String {
        raw.split(separator: "\n").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? "?"
    }
}
