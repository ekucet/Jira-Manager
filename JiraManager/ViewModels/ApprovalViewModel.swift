import Foundation

@MainActor
final class ApprovalViewModel: ObservableObject {
    @Published var prs: [BitbucketPR] = []
    @Published var loading = false
    @Published var errorMessage: String?
    @Published var onlyReviewer = true

    @Published var selectedID: BitbucketPR.ID?
    @Published var acting = false
    @Published var actionError: String?
    @Published var currentUser: String?

    private func client(_ settings: AppSettings) -> BitbucketClient? {
        guard let url = AppSettings.normalizedURL(settings.bitbucketURLString), !settings.bitbucketToken.isEmpty else { return nil }
        return BitbucketClient(baseURL: url, token: settings.bitbucketToken)
    }

    private func repoCoordinates(_ settings: AppSettings) async -> (project: String, slug: String)? {
        guard !settings.projectPath.isEmpty else { return nil }
        let git = GitRunner(projectPath: settings.projectPath)
        guard let remote = try? await git.remoteURL() else { return nil }
        return BitbucketClient.parseRemote(remote)
    }

    func loadPRs(using settings: AppSettings) async {
        guard let bb = client(settings) else {
            errorMessage = "Ayarlar'dan Bitbucket URL + token gir."
            return
        }
        guard let (project, slug) = await repoCoordinates(settings) else {
            errorMessage = "Proje klasörü/remote çözümlenemedi."
            return
        }
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            if currentUser == nil { currentUser = try? await bb.currentUsername() }
            prs = try await bb.listOpenPullRequests(project: project, slug: slug, onlyReviewer: onlyReviewer)
            if prs.isEmpty { errorMessage = onlyReviewer ? "Onayına düşen açık PR yok." : "Açık PR yok." }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            prs = []
        }
    }

    /// The current user's own review status on a PR, if any.
    func myStatus(on pr: BitbucketPR) -> String? {
        guard let me = currentUser else { return nil }
        return pr.reviewers?.first { $0.user?.name == me }?.status
    }

    func approve(_ pr: BitbucketPR, using settings: AppSettings) async {
        await act(pr, using: settings, approve: true)
    }

    func unapprove(_ pr: BitbucketPR, using settings: AppSettings) async {
        await act(pr, using: settings, approve: false)
    }

    private func act(_ pr: BitbucketPR, using settings: AppSettings, approve: Bool) async {
        guard let bb = client(settings), let (project, slug) = await repoCoordinates(settings) else {
            actionError = "Bitbucket bağlantısı eksik."
            return
        }
        acting = true
        actionError = nil
        defer { acting = false }
        do {
            if approve {
                try await bb.approve(project: project, slug: slug, prId: pr.id)
            } else {
                try await bb.unapprove(project: project, slug: slug, prId: pr.id)
            }
            // Refresh to reflect the new status.
            prs = try await bb.listOpenPullRequests(project: project, slug: slug, onlyReviewer: onlyReviewer)
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
