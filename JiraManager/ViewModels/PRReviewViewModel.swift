import Foundation

@MainActor
final class PRReviewViewModel: ObservableObject {
    @Published var prs: [BitbucketPR] = []
    @Published var loading = false
    @Published var errorMessage: String?
    @Published var onlyReviewer = false

    @Published var selectedID: BitbucketPR.ID?
    @Published var reviewing = false
    @Published var reviewLog = ""
    @Published var reviewText = ""
    @Published var reviewResult: ReviewResult?
    @Published var diffText = ""
    @Published var reviewError: String?

    @Published var posting = false
    @Published var postResult: String?

    private func repoCoordinates(_ settings: AppSettings) async -> (project: String, slug: String)? {
        guard !settings.projectPath.isEmpty else { return nil }
        let git = GitRunner(projectPath: settings.projectPath)
        guard let remote = try? await git.remoteURL() else { return nil }
        return BitbucketClient.parseRemote(remote)
    }

    func loadPRs(using settings: AppSettings) async {
        guard let bbURL = AppSettings.normalizedURL(settings.bitbucketURLString),
              !settings.bitbucketToken.isEmpty else {
            errorMessage = "Ayarlar'dan Bitbucket URL + token gir."
            return
        }
        guard let (project, slug) = await repoCoordinates(settings) else {
            errorMessage = "Proje klasörü/remote çözümlenemedi. Ayarlar'dan proje klasörünü seç."
            return
        }
        loading = true
        errorMessage = nil
        defer { loading = false }
        let bb = BitbucketClient(baseURL: bbURL, token: settings.bitbucketToken)
        do {
            prs = try await bb.listOpenPullRequests(project: project, slug: slug, onlyReviewer: onlyReviewer)
            if prs.isEmpty { errorMessage = onlyReviewer ? "Reviewer olduğun açık PR yok." : "Açık PR yok." }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            prs = []
        }
    }

    func review(_ pr: BitbucketPR, using settings: AppSettings) async {
        reviewing = true
        reviewError = nil
        reviewLog = ""
        reviewText = ""
        reviewResult = nil
        diffText = ""
        defer { reviewing = false }

        let git = GitRunner(projectPath: settings.projectPath, httpToken: settings.bitbucketToken)
        let claude = ClaudeRunner(claudePath: settings.claudePath, projectPath: settings.projectPath)
        do {
            try await git.fetch()
            let diff = try await git.pullRequestDiff(from: pr.fromBranch, to: pr.toBranch)
            diffText = diff
            if diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                reviewError = "Diff boş (branch'ler fetch edilemedi olabilir): \(pr.fromBranch) → \(pr.toBranch)"
                return
            }
            // Cap the diff sent to Claude so a huge PR doesn't blow the context window.
            let maxChars = 250_000
            var diffForReview = diff
            if diff.count > maxChars {
                diffForReview = String(diff.prefix(maxChars))
                reviewLog += "⚠️ Diff çok büyük (\(diff.count) karakter), ilk \(maxChars) karakter incelendi.\n"
            }
            let result = try await claude.review(prTitle: pr.title, diff: diffForReview) { [weak self] line in
                self?.reviewLog += line + "\n"
            }
            if result.exitCode != 0 {
                reviewError = "Claude \(result.exitCode) koduyla çıktı. (claude login yapıldı mı?)"
                return
            }
            reviewText = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            reviewResult = ReviewResult.parse(from: reviewText)
        } catch {
            reviewError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func postReviewAsComment(_ pr: BitbucketPR, using settings: AppSettings) async {
        guard !reviewText.isEmpty,
              let bbURL = AppSettings.normalizedURL(settings.bitbucketURLString),
              !settings.bitbucketToken.isEmpty,
              let (project, slug) = await repoCoordinates(settings) else { return }
        posting = true
        postResult = nil
        defer { posting = false }
        let bb = BitbucketClient(baseURL: bbURL, token: settings.bitbucketToken)
        do {
            let body = reviewResult?.markdown ?? ("🤖 Claude Code review:\n\n" + reviewText)
            try await bb.addComment(project: project, slug: slug, prId: pr.id, text: body)
            postResult = "Yorum PR'a eklendi ✓"
        } catch {
            postResult = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
