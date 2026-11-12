import Foundation

// MARK: - Package

struct PackageEntry: Identifiable, Hashable {
    enum Kind: String, Codable, Hashable, CaseIterable {
        case formula
        case cask
    }

    let id: String              // full name / token
    let name: String
    let kind: Kind
    let desc: String
    let homepage: String
    let version: String
    let tap: String
    let outdated: Bool
    let pinned: Bool
    let installedOnRequest: Bool
    let dependencies: [String]
    let caveats: String?
    let hasService: Bool
    let installedTime: Date?
    let deprecated: Bool

    var isDependencyOnly: Bool { kind == .formula && !installedOnRequest }

    var searchBlob: String { (name + " " + desc).lowercased() }
}

// MARK: - Service

enum ServiceStatus: String, Codable {
    case started
    case stopped
    case error
    case unknown
    case scheduled
    case none_ = "none"

    var isRunning: Bool { self == .started || self == .scheduled }
    var isRegistered: Bool { self != .none_ }

    var label: String {
        switch self {
        case .none_: return "available"
        case .unknown: return "unknown"
        default: return rawValue
        }
    }
}

struct ServiceEntry: Identifiable, Hashable {
    let name: String
    let status: ServiceStatus
    let user: String?
    let file: String?
    let exitCode: Int?

    var id: String { name }
    var needsRoot: Bool { user == "root" }
}

// MARK: - Outdated

struct OutdatedEntry: Identifiable, Hashable {
    let name: String
    let installedVersions: [String]
    let currentVersion: String
    let pinned: Bool
    let pinnedVersion: String?
    let kind: PackageEntry.Kind

    var id: String { "\(kind.rawValue):\(name)" }
}

// MARK: - Tap

struct TapEntry: Identifiable, Hashable {
    let name: String
    let path: String
    let remote: String
    let official: Bool
    let formulaCount: Int
    let caskCount: Int

    var id: String { name }
}

// MARK: - Search

struct SearchHit: Identifiable, Hashable {
    let name: String
    let kind: PackageEntry.Kind
    let installed: Bool

    var id: String { "\(kind.rawValue):\(name)" }
}

// MARK: - Stats

struct BrewStats: Hashable {
    var brewVersion = "—"
    var prefix = "—"
    var cellar = "—"
    var formulaCount = 0
    var caskCount = 0
    var outdatedCount = 0
    var runningServices = 0
    var registeredServices = 0
    var tapCount = 0
    var cellarSize = "…"          // du -sh, filled async
}

// MARK: - Cleanup dry run

struct CleanupReport {
    var items: [String] = []
    var freeSpace: String = ""
}

// MARK: - Running operation (console)

struct RunningOp: Identifiable {
    let id = UUID()
    var title: String
    var log: String = ""
    var running: Bool
    var failed: Bool = false
}
