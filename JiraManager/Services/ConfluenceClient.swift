import Foundation

struct ConfluenceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Async client for the Confluence Data Center REST API.
/// Authenticates with a Bearer Personal Access Token (Confluence's own token, separate from Jira's).
struct ConfluenceClient {
    let baseURL: URL
    let token: String

    private func makeRequest(path: String, query: [URLQueryItem] = []) -> URLRequest? {
        guard var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            return nil
        }
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ConfluenceError(message: "Ağ hatası: \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else {
            throw ConfluenceError(message: "Beklenmeyen yanıt.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            let hint: String
            switch http.statusCode {
            case 401: hint = "Kimlik doğrulama başarısız (401). Confluence token yanlış/expired olabilir."
            case 403: hint = "Erişim reddedildi (403)."
            case 404: hint = "Adres bulunamadı (404). Confluence URL'ini kontrol et."
            default: hint = "Sunucu \(http.statusCode) döndü."
            }
            throw ConfluenceError(message: "\(hint)\n\(bodyText.prefix(400))")
        }
        return data
    }

    /// Validates the connection.
    func currentUser() async throws -> ConfluenceUser {
        guard let req = makeRequest(path: "rest/api/user/current") else {
            throw ConfluenceError(message: "Geçersiz URL.")
        }
        let data = try await send(req)
        do {
            return try JSONDecoder().decode(ConfluenceUser.self, from: data)
        } catch {
            throw ConfluenceError(message: "Kullanıcı bilgisi çözümlenemedi: \(error.localizedDescription)")
        }
    }

    /// Full-text search across pages/blogposts, newest first.
    func search(_ text: String) async throws -> [ConfluencePage] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        // Escape double quotes for CQL, then match title or body text.
        let safe = trimmed.replacingOccurrences(of: "\"", with: "\\\"")
        let cql = "(title ~ \"\(safe)\" OR text ~ \"\(safe)\") AND type IN (page, blogpost) ORDER BY lastmodified DESC"
        guard let req = makeRequest(path: "rest/api/content/search", query: [
            URLQueryItem(name: "cql", value: cql),
            URLQueryItem(name: "limit", value: "30"),
            URLQueryItem(name: "expand", value: "space,version"),
        ]) else {
            throw ConfluenceError(message: "Geçersiz URL.")
        }
        let data = try await send(req)
        do {
            return try JSONDecoder().decode(ConfluenceSearchResponse.self, from: data).results
        } catch {
            throw ConfluenceError(message: "Arama sonuçları çözümlenemedi: \(error.localizedDescription)")
        }
    }

    /// Fetches a single page with its rendered body.
    func page(id: String) async throws -> ConfluencePageDetail {
        guard let req = makeRequest(path: "rest/api/content/\(id)", query: [
            URLQueryItem(name: "expand", value: "body.export_view,body.storage,space,version"),
        ]) else {
            throw ConfluenceError(message: "Geçersiz URL.")
        }
        let data = try await send(req)
        do {
            return try JSONDecoder().decode(ConfluencePageDetail.self, from: data)
        } catch {
            throw ConfluenceError(message: "Sayfa çözümlenemedi: \(error.localizedDescription)")
        }
    }

    /// Absolute browser URL for a page's `_links.webui` (which is relative to the base).
    func browserURL(webui: String?) -> URL? {
        guard let webui, !webui.isEmpty else { return nil }
        return URL(string: baseURL.absoluteString + webui)
    }
}
