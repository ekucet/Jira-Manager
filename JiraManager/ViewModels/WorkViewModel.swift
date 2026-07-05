import Foundation

@MainActor
final class WorkViewModel: ObservableObject {

    enum Stage {
        case intro       // enter feedback
        case running     // claude working
        case review      // show diff, edit branch/title
        case committing  // git + PR
        case done
    }

    // Context
    let issueKey: String
    let summary: String
    let issueDescription: String

    // Flow state
    @Published var stage: Stage = .intro
    @Published var feedback = ""
    @Published var log = ""
    @Published var changedFiles: [String] = []
    @Published var diffText = ""
    @Published var branchName = ""
    @Published var prTitle = ""
    @Published var prDescription = ""
    @Published var prURL: String?
    @Published var errorMessage: String?
    @Published var noChanges = false

    init(issueKey: String, summary: String, issueDescription: String) {
        self.issueKey = issueKey
        self.summary = summary
        self.issueDescription = issueDescription
        self.branchName = "feature/\(issueKey)"
        self.prTitle = "\(issueKey) \(summary)"
        self.prDescription = "Jira: \(issueKey)\n\n\(summary)"
    }

    private func appendLog(_ line: String) { log += line + "\n" }

    // MARK: Step 1 — run Claude Code

    func runClaude(settings: AppSettings) async {
        guard !settings.projectPath.isEmpty else {
            errorMessage = "Ayarlar'dan proje klasörünü seç."
            return
        }
        errorMessage = nil
        noChanges = false
        log = ""
        stage = .running

        let git = GitRunner(projectPath: settings.projectPath, httpToken: settings.bitbucketToken)
        let claude = ClaudeRunner(claudePath: settings.claudePath, projectPath: settings.projectPath)
        let prompt = ClaudeRunner.buildPrompt(
            issueKey: issueKey, summary: summary,
            description: issueDescription, feedback: feedback
        )

        do {
            let before = try await git.changedPaths()
            appendLog("▶︎ Claude Code çalışıyor…\n")
            let result = try await claude.run(prompt: prompt) { [weak self] line in
                self?.appendLog(line)
            }
            if result.exitCode != 0 {
                errorMessage = "Claude \(result.exitCode) koduyla çıktı. Girişi (claude login) ve logları kontrol et."
                stage = .intro
                return
            }
            let after = try await git.changedPaths()
            let newlyChanged = after.subtracting(before).sorted()
            changedFiles = newlyChanged
            if newlyChanged.isEmpty {
                noChanges = true
                stage = .review
                return
            }
            diffText = try await git.diff(paths: newlyChanged)
            stage = .review
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            stage = .intro
        }
    }

    // MARK: Step 2 — commit, push, open PR

    func commitAndOpenPR(settings: AppSettings) async {
        guard !changedFiles.isEmpty else { return }
        guard let bbURL = AppSettings.normalizedURL(settings.bitbucketURLString),
              !settings.bitbucketToken.isEmpty else {
            errorMessage = "Bitbucket bağlantısı eksik (URL/token)."
            return
        }
        errorMessage = nil
        stage = .committing

        let git = GitRunner(projectPath: settings.projectPath, httpToken: settings.bitbucketToken)
        let bb = BitbucketClient(baseURL: bbURL, token: settings.bitbucketToken)
        let commitMessage = "\(issueKey): \(summary)"

        do {
            let remote = try await git.remoteURL()
            guard let (project, slug) = BitbucketClient.parseRemote(remote) else {
                throw GitError(message: "Remote çözümlenemedi: \(remote)")
            }
            appendLog("\n▶︎ Branch oluşturuluyor: \(branchName)")
            try await git.commitAndPush(branch: branchName, message: commitMessage, paths: changedFiles)
            appendLog("▶︎ Push tamam. PR açılıyor → \(settings.targetBranch)")
            let url = try await bb.createPullRequest(
                project: project, slug: slug,
                title: prTitle, description: prDescription,
                fromBranch: branchName, toBranch: settings.targetBranch
            )
            prURL = url
            appendLog("✅ PR açıldı: \(url)")
            stage = .done
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            stage = .review
        }
    }
}
