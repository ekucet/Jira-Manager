import Foundation

struct ProcessResult {
    let exitCode: Int32
    let output: String
}

enum ProcessRunner {

    /// Runs an executable to completion, capturing combined stdout+stderr.
    /// `onLine` is called (on the main actor) for each line as it streams in.
    @discardableResult
    static func run(
        executable: String,
        arguments: [String],
        currentDirectory: String? = nil,
        stdin: String? = nil,
        onLine: (@MainActor (String) -> Void)? = nil
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let currentDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
        }

        // Feed stdin if provided (used to pass large prompts to `claude -p`).
        let inputPipe: Pipe?
        if stdin != nil {
            let p = Pipe()
            process.standardInput = p
            inputPipe = p
        } else {
            inputPipe = nil
        }

        // Ensure common tool locations + the CLI dir are on PATH.
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extra = "\(home)/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = extra + ":" + (env["PATH"] ?? "")
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let collected = OutputCollector()
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { fh in
            let data = fh.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            collected.append(chunk)
            if let onLine {
                Task { @MainActor in
                    for line in chunk.split(separator: "\n", omittingEmptySubsequences: false) {
                        let s = String(line)
                        if !s.isEmpty { onLine(s) }
                    }
                }
            }
        }

        do {
            try process.run()
        } catch {
            handle.readabilityHandler = nil
            throw ProcessError.launchFailed(error.localizedDescription)
        }

        // Write stdin then close so the process sees EOF.
        if let inputPipe, let stdin {
            let fh = inputPipe.fileHandleForWriting
            try? fh.write(contentsOf: Data(stdin.utf8))
            try? fh.close()
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in cont.resume() }
        }
        handle.readabilityHandler = nil
        // Drain anything left.
        if let rest = try? handle.readToEnd(), let s = String(data: rest, encoding: .utf8), !s.isEmpty {
            collected.append(s)
        }

        return ProcessResult(exitCode: process.terminationStatus, output: collected.text)
    }

    enum ProcessError: LocalizedError {
        case launchFailed(String)
        var errorDescription: String? {
            switch self {
            case .launchFailed(let m): return "Komut başlatılamadı: \(m)"
            }
        }
    }
}

/// Thread-safe accumulator for streamed output.
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    func append(_ s: String) { lock.lock(); buffer += s; lock.unlock() }
    var text: String { lock.lock(); defer { lock.unlock() }; return buffer }
}
