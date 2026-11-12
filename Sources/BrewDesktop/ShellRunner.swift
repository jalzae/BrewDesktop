import Foundation
import AppKit

struct ShellResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    var succeeded: Bool { exitCode == 0 }
}

enum ShellError: LocalizedError {
    case exited(Int32, String)
    case interrupted

    var errorDescription: String? {
        switch self {
        case .exited(let code, let msg):
            return msg.isEmpty ? "Command exited with code \(code)" : msg.trimmingCharacters(in: .whitespacesAndNewlines)
        case .interrupted:
            return "Command was cancelled"
        }
    }
}

/// Runs subprocesses with a GUI-safe environment (Finder-launched apps do not
/// inherit the shell PATH, so Homebrew locations are injected explicitly).
enum Shell {
    /// Locate the brew binary the way `brew` itself does: standard prefixes first.
    static let brewPath: String = {
        let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "brew"
    }()

    static var brewPrefix: String {
        URL(fileURLWithPath: URL(fileURLWithPath: brewPath).deletingLastPathComponent().path)
            .deletingLastPathComponent().path
    }

    static var baseEnvironment: [String: String] {
        [
            "PATH": "\(brewPrefix)/bin:\(brewPrefix)/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "HOMEBREW_NO_AUTO_UPDATE": "1",
            "HOMEBREW_NO_ENV_HINTS": "1",
            "HOME": NSHomeDirectory(),
            "TERM": "dumb",
        ]
    }

    /// Run a command, streaming combined output to `onOutput` (main actor).
    static func run(
        _ launchPath: String,
        _ arguments: [String],
        environment: [String: String]? = nil,
        onOutput: (@MainActor (String) -> Void)? = nil
    ) async throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        var env = environment ?? baseEnvironment
        env.merge(ProcessInfo.processInfo.environment.filter { $0.key == "LANG" || $0.key == "LC_ALL" }) { a, _ in a }
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutBuffer = OutputBuffer()
        let stderrBuffer = OutputBuffer()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            stdoutBuffer.append(chunk)
            if let onOutput {
                let text = String(decoding: chunk, as: UTF8.self)
                Task { @MainActor in onOutput(text) }
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            stderrBuffer.append(chunk)
            if let onOutput {
                let text = String(decoding: chunk, as: UTF8.self)
                Task { @MainActor in onOutput(text) }
            }
        }

        process.terminationHandler = { _ in }

        return try await withTaskCancellationHandler(operation: {
            do {
                try process.run()
            } catch {
                throw ShellError.exited(-1, "Failed to launch \(launchPath): \(error.localizedDescription)")
            }

            let code: Int32 = await withCheckedContinuation { continuation in
                process.terminationHandler = { proc in
                    continuation.resume(returning: proc.terminationStatus)
                }
            }

            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            // Drain whatever remains buffered after handlers were detached.
            stdoutBuffer.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
            stderrBuffer.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())

            let out = String(decoding: stdoutBuffer.current, as: UTF8.self)
            let err = String(decoding: stderrBuffer.current, as: UTF8.self)
            if code != 0 {
                throw ShellError.exited(code, err.isEmpty ? out : err)
            }
            return ShellResult(exitCode: code, stdout: out, stderr: err)
        }, onCancel: {
            if process.isRunning {
                process.terminate()
            }
        })
    }

    static func brew(
        _ arguments: [String],
        onOutput: (@MainActor (String) -> Void)? = nil
    ) async throws -> ShellResult {
        try await run(brewPath, arguments, onOutput: onOutput)
    }

    /// Run a command elevated via the macOS admin-password dialog (osascript).
    /// Output is only available after completion (no streaming).
    static func runElevated(_ command: String) async throws -> ShellResult {
        let script = "do shell script \(quoted(command)) with administrator privileges"
        let result = try await run("/usr/bin/osascript", ["-e", script])
        return result
    }

    static func quoted(_ s: String) -> String {
        "\"" + s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

// MARK: - JSON helpers

/// Thread-safe chunk accumulator: pipe readabilityHandlers run on arbitrary
/// queues, so captured mutable state needs locking.
final class OutputBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
    }

    var current: Data {
        lock.lock(); defer { lock.unlock() }
        return data
    }
}

enum BrewJSON {
    /// Homebrew occasionally prints a preamble (e.g. auto-update notes) before
    /// JSON on stdout; locate the first JSON payload character.
    static func payload(from raw: String) -> String {
        guard let first = raw.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return raw }
        return String(raw[first...])
    }
}
