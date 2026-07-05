import Foundation

@MainActor
final class ConfluenceViewModel: ObservableObject {
    @Published var query = ""
    @Published var results: [ConfluencePage] = []
    @Published var isSearching = false
    @Published var errorMessage: String?

    @Published var selectedID: ConfluencePage.ID?
    @Published var detail: ConfluencePageDetail?
    @Published var loadingDetail = false
    @Published var detailError: String?

    func search(using settings: AppSettings) async {
        guard let client = settings.confluenceClient else {
            errorMessage = "Önce Ayarlar'dan Confluence bağlantını gir (URL + token)."
            return
        }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { results = []; return }
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }
        do {
            results = try await client.search(q)
            if results.isEmpty { errorMessage = "Sonuç bulunamadı." }
        } catch {
            errorMessage = (error as? ConfluenceError)?.message ?? error.localizedDescription
            results = []
        }
    }

    func loadPage(id: String, using settings: AppSettings) async {
        guard let client = settings.confluenceClient else { return }
        loadingDetail = true
        detailError = nil
        detail = nil
        defer { loadingDetail = false }
        do {
            detail = try await client.page(id: id)
        } catch {
            detailError = (error as? ConfluenceError)?.message ?? error.localizedDescription
        }
    }
}
