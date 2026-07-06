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

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    // MARK: Check

    /// Checks for a newer release. `silent` suppresses the "up to date" / error UI (for launch checks).
    func check(settings: AppSettings, silent: Bool) async {
        phase = .checking
        errorMessage = nil
        do {
            let release = try await fetchLatest(token: settings.githubToken)
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

    private func fetchLatest(token: String) async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/\(Self.owner)/\(Self.repo)/releases/latest")!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

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

    func installAndRelaunch(settings: AppSettings) async {
        guard let update else { return }
        phase = .downloading
        errorMessage = nil
        do {
            let dmg = try await download(asset: update.asset, token: settings.githubToken)
            phase = .installing
            try launchInstaller(dmgPath: dmg.path)
            // The installer waits for us to quit, swaps the app, and relaunches.
            NSApp.terminate(nil)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            phase = .failed
        }
    }

    private func download(asset: GitHubRelease.Asset, token: String) async throws -> URL {
        // Use the API asset URL with octet-stream so private assets resolve.
        guard let url = URL(string: asset.url) else { throw UpdateError("Geçersiz asset URL.") }
        var req = URLRequest(url: url)
        req.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        if !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let stripper = RedirectAuthStripper()
        let (tmp, response): (URL, URLResponse)
        do {
            (tmp, response) = try await URLSession.shared.download(for: req, delegate: stripper)
        } catch {
            throw UpdateError("İndirme hatası: \(error.localizedDescription)")
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UpdateError("İndirme başarısız (\(http.statusCode)).")
        }
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("JiraManagerUpdate-\(UUID().uuidString).dmg")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }

    /// Mounts the DMG, then launches a detached script that (after we quit) swaps the app and relaunches it.
    private func launchInstaller(dmgPath: String) throws {
        // Mount
        let attach = Pipe()
        let mount = Process()
        mount.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        mount.arguments = ["attach", "-nobrowse", "-noverify", dmgPath]
        mount.standardOutput = attach
        try mount.run()
        mount.waitUntilExit()
        let out = String(data: attach.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        var mountPoint = ""
        for line in out.split(separator: "\n") {
            if let r = line.range(of: "/Volumes/") {
                mountPoint = String(line[r.lowerBound...]).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        guard !mountPoint.isEmpty else { throw UpdateError("DMG mount edilemedi.") }
        let srcApp = mountPoint + "/JiraManager.app"
        guard FileManager.default.fileExists(atPath: srcApp) else {
            throw UpdateError("DMG içinde JiraManager.app bulunamadı.")
        }
        let destApp = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier

        let scriptPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("jm-update-\(UUID().uuidString).sh")
        let script = """
        #!/bin/bash
        while kill -0 \(pid) 2>/dev/null; do sleep 0.4; done
        if rm -rf "\(destApp)" && /usr/bin/ditto "\(srcApp)" "\(destApp)"; then
          /usr/sbin/xattr -dr com.apple.quarantine "\(destApp)" 2>/dev/null
          /usr/bin/hdiutil detach "\(mountPoint)" >/dev/null 2>&1
          rm -f "\(dmgPath)"
          /usr/bin/open "\(destApp)"
        else
          /usr/bin/open "\(mountPoint)"
        fi
        rm -f "$0"
        """
        try script.write(to: scriptPath, atomically: true, encoding: .utf8)

        let run = Process()
        run.executableURL = URL(fileURLWithPath: "/bin/bash")
        run.arguments = [scriptPath.path]
        try run.run()
        // Do not wait — it will outlive us and relaunch the app.
    }
}

struct UpdateError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

/// Removes the Authorization header when a request is redirected to a different host
/// (GitHub asset downloads redirect to a pre-signed storage URL that rejects extra auth).
final class RedirectAuthStripper: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        var req = request
        if request.url?.host != task.originalRequest?.url?.host {
            req.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        return req
    }
}
