import Foundation
import AppKit

/// Polls assigned issues + review PRs every few minutes. When NEW ones arrive it
/// surfaces an in-app popup and bounces the Dock icon (no system push notifications).
@MainActor
final class WatchService: ObservableObject {
    static let interval: UInt64 = 300 // seconds

    @Published var lastPoll: Date?
    @Published var newItemsMessage: String?   // drives the in-app popup

    private var loop: Task<Void, Never>?
    private var seenIssues: Set<String>
    private var seenPRs: Set<Int>
    private var baselinedIssues: Bool
    private var baselinedPRs: Bool

    private enum Keys {
        static let seenIssues = "watch.seenIssues"
        static let seenPRs = "watch.seenPRs"
        static let baseIssues = "watch.baseIssues"
        static let basePRs = "watch.basePRs"
    }

    init() {
        let d = UserDefaults.standard
        seenIssues = Set(d.stringArray(forKey: Keys.seenIssues) ?? [])
        seenPRs = Set((d.array(forKey: Keys.seenPRs) as? [Int]) ?? [])
        baselinedIssues = d.bool(forKey: Keys.baseIssues)
        baselinedPRs = d.bool(forKey: Keys.basePRs)
    }

    func start(settings: AppSettings) {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll(settings: settings)
                try? await Task.sleep(nanoseconds: Self.interval * 1_000_000_000)
            }
        }
    }

    func stop() { loop?.cancel(); loop = nil }

    func poll(settings: AppSettings) async {
        var fresh: [String] = []
        fresh += await pollIssues(settings: settings)
        fresh += await pollPRs(settings: settings)
        lastPoll = Date()
        guard !fresh.isEmpty else { return }
        newItemsMessage = fresh.joined(separator: "\n")
        // Bounce the Dock icon until the app is activated.
        NSApp.requestUserAttention(.criticalRequest)
    }

    // MARK: Issues

    private func pollIssues(settings: AppSettings) async -> [String] {
        guard let client = settings.client,
              let issues = try? await client.assignedIssues() else { return [] }
        let ids = Set(issues.map(\.key))
        let new = issues.filter { !seenIssues.contains($0.key) }
        seenIssues = ids
        UserDefaults.standard.set(Array(ids), forKey: Keys.seenIssues)

        guard baselinedIssues else {
            baselinedIssues = true
            UserDefaults.standard.set(true, forKey: Keys.baseIssues)
            return [] // first run: establish baseline, don't alert
        }
        return new.map { "🆕 İş: \($0.key) — \($0.summary)" }
    }

    // MARK: PRs assigned to me as reviewer

    private func pollPRs(settings: AppSettings) async -> [String] {
        guard let url = AppSettings.normalizedURL(settings.bitbucketURLString), !settings.bitbucketToken.isEmpty,
              !settings.projectPath.isEmpty else { return [] }
        let git = GitRunner(projectPath: settings.projectPath)
        guard let remote = try? await git.remoteURL(),
              let (project, slug) = BitbucketClient.parseRemote(remote) else { return [] }
        let bb = BitbucketClient(baseURL: url, token: settings.bitbucketToken)
        guard let prs = try? await bb.listOpenPullRequests(project: project, slug: slug, onlyReviewer: true) else { return [] }
        let ids = Set(prs.map(\.id))
        let new = prs.filter { !seenPRs.contains($0.id) }
        seenPRs = ids
        UserDefaults.standard.set(Array(ids), forKey: Keys.seenPRs)

        guard baselinedPRs else {
            baselinedPRs = true
            UserDefaults.standard.set(true, forKey: Keys.basePRs)
            return []
        }
        return new.map { "🔀 PR: #\($0.id) — \($0.title)" }
    }
}
