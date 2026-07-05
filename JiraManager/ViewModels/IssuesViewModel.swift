import Foundation

@MainActor
final class IssuesViewModel: ObservableObject {
    @Published var issues: [JiraIssue] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var currentUser: JiraUser?

    func reload(using settings: AppSettings) async {
        guard let client = settings.client else {
            errorMessage = "Önce Ayarlar'dan Jira bağlantını gir (kurulum tipi, URL ve token)."
            issues = []
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let user = client.myself()
            async let list = client.assignedIssues()
            currentUser = try await user
            issues = try await list
        } catch {
            errorMessage = (error as? JiraError)?.message ?? error.localizedDescription
        }
    }
}
