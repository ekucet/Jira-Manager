import Foundation

struct JiraError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Async client for the Jira REST API.
/// - Server / Data Center: API v2, Bearer Personal Access Token.
/// - Cloud: API v3, HTTP Basic (email:apiToken).
struct JiraClient {
    let baseURL: URL
    let deployment: JiraDeployment
    let email: String
    let token: String

    // MARK: Endpoint & auth differences

    private var apiBase: String {
        deployment == .cloud ? "rest/api/3" : "rest/api/2"
    }

    /// Server/DC enhanced search lives at a different path than Cloud.
    private var searchPath: String {
        deployment == .cloud ? "rest/api/3/search/jql" : "rest/api/2/search"
    }

    private var authHeader: String {
        switch deployment {
        case .cloud:
            let creds = "\(email):\(token)"
            return "Basic " + Data(creds.utf8).base64EncodedString()
        case .server:
            return "Bearer \(token)"
        }
    }

    private func makeRequest(path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        return req
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw JiraError(message: "Ağ hatası: \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else {
            throw JiraError(message: "Beklenmeyen yanıt.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            let hint: String
            switch http.statusCode {
            case 401: hint = "Kimlik doğrulama başarısız (401). Token yanlış/expired olabilir."
            case 403: hint = "Erişim reddedildi (403). Token yetkisi veya CAPTCHA gerekebilir."
            case 404: hint = "Adres bulunamadı (404). Jira URL'ini ve deployment tipini kontrol et."
            default: hint = "Sunucu \(http.statusCode) döndü."
            }
            throw JiraError(message: "\(hint)\n\(bodyText.prefix(400))")
        }
        return data
    }

    /// Validates the connection and returns the authenticated user.
    func myself() async throws -> JiraUser {
        let data = try await send(makeRequest(path: "\(apiBase)/myself"))
        do {
            return try JSONDecoder().decode(JiraUser.self, from: data)
        } catch {
            throw JiraError(message: "Kullanıcı bilgisi çözümlenemedi: \(error.localizedDescription)")
        }
    }

    /// Fetches open issues assigned to the current user, newest first.
    func assignedIssues() async throws -> [JiraIssue] {
        let jql = "assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC"
        let payload: [String: Any] = [
            "jql": jql,
            "maxResults": 50,
            "fields": ["summary", "status", "issuetype", "priority", "updated", "description", "assignee"],
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = makeRequest(path: searchPath, method: "POST", body: body)
        let data = try await send(request)
        do {
            return try JSONDecoder().decode(JiraSearchResponse.self, from: data).issues
        } catch {
            throw JiraError(message: "Issue listesi çözümlenemedi: \(error.localizedDescription)")
        }
    }

    /// Logs work (effort) on a specific issue.
    /// - timeSpent: Jira duration string, e.g. "3h", "30m", "1h 30m", "1d".
    /// - started: when the work began.
    /// - comment: optional note (sent as ADF on Cloud, plain string on Server/DC).
    func logWork(issueKey: String, timeSpent: String, started: Date, comment: String) async throws {
        var payload: [String: Any] = [
            "timeSpent": timeSpent,
            "started": Self.jiraDateString(started),
        ]
        let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedComment.isEmpty {
            if deployment == .cloud {
                payload["comment"] = [
                    "type": "doc",
                    "version": 1,
                    "content": [[
                        "type": "paragraph",
                        "content": [["type": "text", "text": trimmedComment]],
                    ]],
                ]
            } else {
                payload["comment"] = trimmedComment
            }
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = makeRequest(path: "\(apiBase)/issue/\(issueKey)/worklog", method: "POST", body: body)
        _ = try await send(request)
    }

    /// Jira expects worklog timestamps like `2026-07-05T14:30:00.000+0300`.
    static func jiraDateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return f.string(from: date)
    }

    /// URL to open an issue in the browser.
    func browserURL(for issue: JiraIssue) -> URL? {
        URL(string: baseURL.absoluteString + "/browse/" + issue.key)
    }
}
