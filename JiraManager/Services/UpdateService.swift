import Foundation
import AppKit

@MainActor
final class UpdateService: ObservableObject {
    static let owner = "ekucet"
    static let repo = "Jira-Manager"

    enum Phase: Equatable {
        case idle, checking, upToDate, available, downloading, installing, failed
    }

    @Published var phase: Phase = .idle
    @Published var update: AvailableUpdate?
    @Published var errorMessage: String?
    @Published var showSheet = false
    @Published var progress: Double = 0   // 0…1 during download

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    // MARK: Check

    /// Checks for a newer release. `silent` suppresses the "up to date" / error UI (for launch checks).
    func check(silent: Bool) async {
        phase = .checking
        errorMessage = nil
        do {
            let release = try await fetchLatest()
            if SemVer.isNewer(release.version, than: currentVersion), let dmg = release.dmgAsset {
                update = AvailableUpdate(version: release.version,
                                         notes: release.body ?? "",
                                         asset: dmg, htmlUrl: release.htmlUrl)
                phase = .available
                showSheet = true
            } else {
                update = nil
                phase = .upToDate
                if !silent { showSheet = true }
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            phase = .failed
            if !silent { showSheet = true }
        }
    }

    private func fetchLatest() async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/\(Self.owner)/\(Self.repo)/releases/latest")!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateError("Beklenmeyen yanıt.")
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 404 {
                throw UpdateError("Release bulunamadı (henüz yayınlanmamış olabilir).")
            }
            if http.statusCode == 403 {
                throw UpdateError("GitHub API limiti (403). Biraz sonra tekrar dene.")
            }
            throw UpdateError("GitHub \(http.statusCode) döndü.")
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    // MARK: Install

    func installAndRelaunch() async {
        guard let update else { return }
        phase = .downloading
        progress = 0
        errorMessage = nil
        let appPath = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        do {
            let dmg = try await download(asset: update.asset)
            phase = .installing
            // Mount + copy is blocking work — run it off the main thread so the UI stays responsive.
            try await Task.detached(priority: .userInitiated) {
                try UpdateService.performInstall(dmgPath: dmg.path, appPath: appPath, pid: pid)
            }.value
            // Helper is running and waiting for us to quit; hand off by terminating.
            NSApp.terminate(nil)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            phase = .failed
        }
    }

    private func download(asset: GitHubRelease.Asset) async throws -> URL {
        // Public release asset — direct download, no auth, with progress.
        guard let url = URL(string: asset.browserDownloadUrl) else { throw UpdateError("Geçersiz asset URL.") }
        var req = URLRequest(url: url)
        req.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        let downloader = Downloader { [weak self] p in
            Task { @MainActor in self?.progress = p }
        }
        return try await downloader.download(req)
    }

    /// Mounts the DMG and launches a detached script that swaps the app and relaunches after we quit.
    /// Runs off the main actor (blocking Process calls).
    nonisolated static func performInstall(dmgPath: String, appPath: String, pid: Int32) throws {
        // Mount at our own unique path — avoids "/Volumes/JiraManager N" collisions and parsing.
        let mountPoint = FileManager.default.temporaryDirectory
            .appendingPathComponent("jm-mount-\(UUID().uuidString)").path
        try? FileManager.default.createDirectory(atPath: mountPoint, withIntermediateDirectories: true)
        let mount = Process()
        mount.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        mount.arguments = ["attach", "-nobrowse", "-noverify", "-noautoopen", "-mountpoint", mountPoint, dmgPath]
        mount.standardOutput = Pipe()
        mount.standardError = Pipe()
        try mount.run()
        mount.waitUntilExit()
        guard mount.terminationStatus == 0 else {
            throw UpdateError("DMG mount edilemedi (hdiutil \(mount.terminationStatus)).")
        }
        let srcApp = mountPoint + "/JiraManager.app"
        guard FileManager.default.fileExists(atPath: srcApp) else {
            throw UpdateError("DMG içinde JiraManager.app bulunamadı.")
        }

        let scriptPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("jm-update-\(UUID().uuidString).sh")
        let script = """
        #!/bin/bash
        while kill -0 \(pid) 2>/dev/null; do sleep 0.4; done
        if rm -rf "\(appPath)" && /usr/bin/ditto "\(srcApp)" "\(appPath)"; then
          /usr/bin/xattr -dr com.apple.quarantine "\(appPath)" 2>/dev/null
          /usr/bin/hdiutil detach "\(mountPoint)" >/dev/null 2>&1
          rmdir "\(mountPoint)" 2>/dev/null
          rm -f "\(dmgPath)"
          /usr/bin/open "\(appPath)"
        else
          /usr/bin/hdiutil detach "\(mountPoint)" >/dev/null 2>&1
          /usr/bin/open -R "\(appPath)"
        fi
        rm -f "$0"
        """
        try script.write(to: scriptPath, atomically: true, encoding: .utf8)

        let run = Process()
        run.executableURL = URL(fileURLWithPath: "/bin/bash")
        run.arguments = [scriptPath.path]
        try run.run()
        // Do not wait — the helper outlives us and relaunches the app.
    }
}

/// Delegate-based downloader that reports progress and returns the downloaded file.
private final class Downloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: (Double) -> Void
    private var continuation: CheckedContinuation<URL, Error>?

    init(onProgress: @escaping (Double) -> Void) { self.onProgress = onProgress }

    func download(_ request: URLRequest) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            session.downloadTask(with: request).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // The temp file at `location` is removed once this returns — move it now.
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("JiraManagerUpdate-\(UUID().uuidString).dmg")
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: location, to: dest)
            continuation?.resume(returning: dest)
        } catch {
            continuation?.resume(throwing: UpdateError("İndirilen dosya taşınamadı: \(error.localizedDescription)"))
        }
        continuation = nil
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuation?.resume(throwing: UpdateError("İndirme hatası: \(error.localizedDescription)"))
            continuation = nil
            session.finishTasksAndInvalidate()
        }
    }
}

struct UpdateError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}
