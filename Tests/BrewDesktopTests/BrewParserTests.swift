import XCTest
@testable import BrewDesktop

final class BrewParserTests: XCTestCase {

    // MARK: Installed packages (brew info --json=v2)

    func testParseInstalledPackages() throws {
        let raw = """
        Some preamble text
        {
          "formulae": [
            {
              "name": "redis", "full_name": "redis", "desc": "Persistent key-value database",
              "homepage": "https://redis.io", "tap": "homebrew/core",
              "outdated": true, "pinned": false, "deprecated": false,
              "dependencies": ["openssl@3"],
              "caveats": "Some caveat text.",
              "service": {"name": "homebrew.redis"},
              "installed": [
                {"version": "7.2.4", "installed_on_request": true, "time": 1700000000, "pinned": false}
              ],
              "linked_keg": "7.2.4"
            }
          ],
          "casks": [
            {
              "token": "visual-studio-code", "name": ["Microsoft Visual Studio Code"],
              "desc": "Microsoft editor", "homepage": "https://code.visualstudio.com",
              "tap": "homebrew/cask", "version": "2.0.0", "installed": "1.9.0",
              "installed_time": 1700000000.0, "outdated": true, "pinned": false, "deprecated": false
            }
          ]
        }
        """
        let pkgs = try BrewParser.parseInstalledPackages(raw: raw)
        XCTAssertEqual(pkgs.count, 2)

        let redis = try XCTUnwrap(pkgs.first { $0.name == "redis" })
        XCTAssertEqual(redis.kind, .formula)
        XCTAssertEqual(redis.version, "7.2.4")
        XCTAssertTrue(redis.outdated)
        XCTAssertTrue(redis.hasService)
        XCTAssertTrue(redis.installedOnRequest)
        XCTAssertEqual(redis.dependencies, ["openssl@3"])
        XCTAssertNotNil(redis.caveats)
        XCTAssertNotNil(redis.installedTime)

        let code = try XCTUnwrap(pkgs.first { $0.name == "visual-studio-code" })
        XCTAssertEqual(code.kind, .cask)
        XCTAssertEqual(code.id, "cask:visual-studio-code")
        XCTAssertEqual(code.version, "1.9.0")  // installed version wins
        XCTAssertTrue(code.outdated)
    }

    // MARK: Services (brew services list --json)

    func testParseServices() throws {
        let raw = """
        [
          {"name": "httpd", "status": "started", "user": "me", "file": "/Users/me/Library/LaunchAgents/homebrew.mxcl.httpd.plist", "exit_code": null},
          {"name": "kafka", "status": "none", "user": null, "file": "/opt/homebrew/opt/kafka/homebrew.mxcl.kafka.plist", "exit_code": null},
          {"name": "php@7.4", "status": "error", "user": "root", "file": null, "exit_code": 78},
          {"name": "postgres", "status": "stopped", "user": "me", "file": "/Users/me/x.plist", "exit_code": null}
        ]
        """
        let svcs = try BrewParser.parseServices(raw: raw)
        XCTAssertEqual(svcs.count, 4)

        let httpd = try XCTUnwrap(svcs.first { $0.name == "httpd" })
        XCTAssertEqual(httpd.status, .started)
        XCTAssertTrue(httpd.status.isRunning)
        XCTAssertTrue(httpd.status.isRegistered)

        let kafka = try XCTUnwrap(svcs.first { $0.name == "kafka" })
        XCTAssertEqual(kafka.status, .none_)
        XCTAssertFalse(kafka.status.isRunning)
        XCTAssertFalse(kafka.status.isRegistered)  // plist present but not registered with launchd

        let php = try XCTUnwrap(svcs.first { $0.name == "php@7.4" })
        XCTAssertEqual(php.status, .error)
        XCTAssertTrue(php.needsRoot)
        XCTAssertEqual(php.exitCode, 78)

        // Running services float to the top.
        XCTAssertEqual(svcs.first?.name, "httpd")
    }

    // MARK: Outdated (brew outdated --json=v2)

    func testParseOutdated() throws {
        let raw = """
        {
          "formulae": [
            {"name": "abseil", "installed_versions": ["20240722.1"], "current_version": "20260817.0", "pinned": false, "pinned_version": null},
            {"name": "openssl@3", "installed_versions": ["3.1.0", "3.1.1"], "current_version": "3.2.0", "pinned": true, "pinned_version": "3.1.0"}
          ],
          "casks": [
            {"name": "iterm2", "installed_versions": ["3.4"], "current_version": "3.5", "pinned": false, "pinned_version": null}
          ]
        }
        """
        let items = try BrewParser.parseOutdated(raw: raw)
        XCTAssertEqual(items.count, 3)
        let openssl = try XCTUnwrap(items.first { $0.name == "openssl@3" })
        XCTAssertTrue(openssl.pinned)
        XCTAssertEqual(openssl.pinnedVersion, "3.1.0")
        XCTAssertEqual(openssl.installedVersions.count, 2)
        let iterm = try XCTUnwrap(items.first { $0.kind == .cask })
        XCTAssertEqual(iterm.name, "iterm2")
    }

    // MARK: Taps (brew tap-info --json=v1 --installed)

    func testParseTaps() throws {
        let raw = """
        [
          {"name": "homebrew/core", "path": "/opt/homebrew/Library/Taps/homebrew/homebrew-core", "remote": "https://github.com/Homebrew/homebrew-core", "official": true, "formula_names": ["a", "b"], "cask_tokens": []},
          {"name": "btwld/fvm", "path": "/opt/homebrew/Library/Taps/btwld/homebrew-fvm", "remote": "https://github.com/btwld/homebrew-fvm", "official": false, "formula_names": ["a", "b", "c"], "cask_tokens": ["x"]}
        ]
        """
        let taps = try BrewParser.parseTaps(raw: raw)
        XCTAssertEqual(taps.count, 2)
        let core = try XCTUnwrap(taps.first { $0.name == "homebrew/core" })
        XCTAssertTrue(core.official)
        XCTAssertEqual(core.formulaCount, 2)
        let fvm = try XCTUnwrap(taps.first { $0.name == "btwld/fvm" })
        XCTAssertFalse(fvm.official)
        XCTAssertEqual(fvm.caskCount, 1)
    }

    // MARK: Search (brew search <term>)

    func testParseSearch() {
        let raw = """
        ==> Formulae
        nginx
        nginx-parser
        error-guard

        ==> Casks
        nginxutils
        """
        let hits = BrewParser.parseSearch(raw)
        XCTAssertEqual(hits.count, 4)
        XCTAssertEqual(hits.filter { $0.kind == .formula }.count, 3)
        XCTAssertEqual(hits.filter { $0.kind == .cask }.count, 1)
        XCTAssertEqual(hits.last?.name, "nginxutils")
    }

    func testParseSearchFlatOutput() {
        // Single-result output has no section header.
        let hits = BrewParser.parseSearch("nginx\n")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].kind, .formula)
    }

    // MARK: Cleanup dry run (brew cleanup -n)

    func testParseCleanupDryRun() {
        let raw = """
        Would remove: /opt/homebrew/Cellar/tbb/2021.11.0 (203 files, 3.3MB)
        Would remove: /opt/homebrew/Cellar/xz/5.8.3 (96 files, 2.7MB)
        ==> This operation would free approximately 1.2GB of disk space.
        """
        let report = BrewParser.parseCleanupDryRun(raw)
        XCTAssertEqual(report.items.count, 2)
        XCTAssertTrue(report.items[0].contains("tbb"))
        XCTAssertEqual(report.freeSpace, "1.2GB")
    }

    // MARK: Version (brew --version)

    func testParseVersion() {
        XCTAssertEqual(BrewParser.parseVersion("Homebrew 7.0.13\nSomething else\n"), "Homebrew 7.0.13")
    }

    // MARK: JSON payload stripping

    func testPayloadStrip() {
        XCTAssertEqual(BrewJSON.payload(from: "noise\n{\"a\":1}"), "{\"a\":1}")
        XCTAssertEqual(BrewJSON.payload(from: "[1,2]"), "[1,2]")
    }
}
