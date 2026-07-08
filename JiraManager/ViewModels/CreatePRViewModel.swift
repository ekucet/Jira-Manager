import Foundation

@MainActor
final class CreatePRViewModel: ObservableObject {
    @Published var branches: [BitbucketBranch] = []
    @Published var loading = false
    @Published var errorMessage: String?
    @Published var filter = ""

    @Published var selectedID: BitbucketBranch.ID?
    @Published var prTitle = ""
    @Published var prDescription = ""

    @Published var creating = false
    @Published var createError: String?
    @Published var createdURL: String?

    private func repoCoordinates(_ settings: AppSettings) async -> (project: String, slug: String)? {
        guard !settings.projectPath.isEmpty else { return nil }
        let git = GitRunner(projectPath: settings.projectPath)
        guard let remote = try? await git.remoteURL() else { return nil }
        return BitbucketClient.parseRemote(remote)
    }

    func loadBranches(using settings: AppSettings) async {
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
            let all = try await bb.listBranches(project: project, slug: slug, filter: filter)
            // Don't offer the target branch itself as a source.
            branches = all.filter { $0.displayId != settings.targetBranch }
            if branches.isEmpty { errorMessage = "Branch bulunamadı." }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            branches = []
        }
    }

    /// When a branch is selected, seed a sensible PR title.
    func selectBranch(_ id: BitbucketBranch.ID?) {
        selectedID = id
        createError = nil
        createdURL = nil
        if let branch = branches.first(where: { $0.id == id }) {
            prTitle = branch.displayId
            prDescription = ""
        }
    }

    func createPR(using settings: AppSettings) async {
        guard let branch = branches.first(where: { $0.id == selectedID }) else { return }
        guard let bbURL = AppSettings.normalizedURL(settings.bitbucketURLString),
              !settings.bitbucketToken.isEmpty,
              let (project, slug) = await repoCoordinates(settings) else {
            createError = "Bitbucket bağlantısı eksik."
            return
        }
        creating = true
        createError = nil
        createdURL = nil
        defer { creating = false }
        let bb = BitbucketClient(baseURL: bbURL, token: settings.bitbucketToken)
        do {
            let url = try await bb.createPullRequest(
                project: project, slug: slug,
                title: prTitle, description: prDescription,
                fromBranch: branch.displayId, toBranch: settings.targetBranch
            )
            createdURL = url
        } catch {
            createError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
