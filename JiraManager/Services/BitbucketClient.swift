import Foundation

struct BitbucketError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Minimal Bitbucket Data Center REST client (for creating pull requests).
struct BitbucketClient {
    let baseURL: URL
    let token: String

    /// Parses a Bitbucket remote URL into (projectKey, repoSlug).
    /// Handles both `https://host/bitbucket/scm/PROJ/repo.git` and `ssh://git@host:7999/PROJ/repo.git`.
    static func parseRemote(_ remote: String) -> (project: String, slug: String)? {
        var path = remote
        if let range = path.range(of: "/scm/") {
            path = String(path[range.upperBound...])
        } else if let schemeRange = path.range(of: "://") {
            // ssh style: strip scheme+host, keep path after first "/".
            let afterScheme = String(path[schemeRange.upperBound...])
            if let slash = afterScheme.firstIndex(of: "/") {
                path = String(afterScheme[afterScheme.index(after: slash)...])
            }
        }
        let comps = path.split(separator: "/").map(String.init)
        guard comps.count >= 2 else { return nil }
        let project = comps[comps.count - 2]
        var slug = comps[comps.count - 1]
        if slug.hasSuffix(".git") { slug = String(slug.dropLast(4)) }
        // Bitbucket project keys are stored uppercase.
        return (project.uppercased(), slug)
    }

    private func authedRequest(path: String, query: [URLQueryItem] = [], method: String = "GET", body: Data? = nil) -> URLRequest? {
        guard var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else { return nil }
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        return req
    }

    private func sendJSON(_ req: URLRequest) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw BitbucketError(message: "Ağ hatası: \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else { throw BitbucketError(message: "Beklenmeyen yanıt.") }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw BitbucketError(message: "Bitbucket \(http.statusCode):\n\(text.prefix(400))")
        }
        return data
    }

    /// Lists open pull requests for a repo. `onlyReviewer` filters to PRs where the token owner is a reviewer.
    func listOpenPullRequests(project: String, slug: String, onlyReviewer: Bool) async throws -> [BitbucketPR] {
        var query = [
            URLQueryItem(name: "state", value: "OPEN"),
            URLQueryItem(name: "limit", value: "50"),
            URLQueryItem(name: "order", value: "NEWEST"),
        ]
        if onlyReviewer { query.append(URLQueryItem(name: "role", value: "REVIEWER")) }
        guard let req = authedRequest(path: "rest/api/1.0/projects/\(project)/repos/\(slug)/pull-requests", query: query) else {
            throw BitbucketError(message: "Geçersiz URL.")
        }
        let data = try await sendJSON(req)
        do {
            return try JSONDecoder().decode(BitbucketPRPage.self, from: data).values
        } catch {
            throw BitbucketError(message: "PR listesi çözümlenemedi: \(error.localizedDescription)")
        }
    }

    /// The authenticated user's username, via Bitbucket's `X-AUSERNAME` response header.
    func currentUsername() async throws -> String {
        guard let req = authedRequest(path: "rest/api/1.0/application-properties") else {
            throw BitbucketError(message: "Geçersiz URL.")
        }
        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse,
              let user = http.value(forHTTPHeaderField: "X-AUSERNAME"), user != "anonymous" else {
            throw BitbucketError(message: "Kullanıcı belirlenemedi.")
        }
        return user
    }

    /// Approves a pull request as the authenticated user.
    func approve(project: String, slug: String, prId: Int) async throws {
        guard let req = authedRequest(
            path: "rest/api/1.0/projects/\(project)/repos/\(slug)/pull-requests/\(prId)/approve",
            method: "POST"
        ) else { throw BitbucketError(message: "Geçersiz URL.") }
        _ = try await sendJSON(req)
    }

    /// Removes the authenticated user's approval.
    func unapprove(project: String, slug: String, prId: Int) async throws {
        guard let req = authedRequest(
            path: "rest/api/1.0/projects/\(project)/repos/\(slug)/pull-requests/\(prId)/approve",
            method: "DELETE"
        ) else { throw BitbucketError(message: "Geçersiz URL.") }
        _ = try await sendJSON(req)
    }

    /// Lists branches, most recently modified first. `filter` narrows by name substring.
    func listBranches(project: String, slug: String, filter: String?) async throws -> [BitbucketBranch] {
        var query = [
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "orderBy", value: "MODIFICATION"),
        ]
        if let filter, !filter.isEmpty { query.append(URLQueryItem(name: "filterText", value: filter)) }
        guard let req = authedRequest(path: "rest/api/1.0/projects/\(project)/repos/\(slug)/branches", query: query) else {
            throw BitbucketError(message: "Geçersiz URL.")
        }
        let data = try await sendJSON(req)
        do {
            return try JSONDecoder().decode(BitbucketBranchPage.self, from: data).values
        } catch {
            throw BitbucketError(message: "Branch listesi çözümlenemedi: \(error.localizedDescription)")
        }
    }

    /// Posts a general comment on a pull request.
    func addComment(project: String, slug: String, prId: Int, text: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["text": text])
        guard let req = authedRequest(
            path: "rest/api/1.0/projects/\(project)/repos/\(slug)/pull-requests/\(prId)/comments",
            method: "POST", body: body
        ) else { throw BitbucketError(message: "Geçersiz URL.") }
        _ = try await sendJSON(req)
    }

    /// Creates a pull request and returns its browser URL.
    func createPullRequest(
        project: String,
        slug: String,
        title: String,
        description: String,
        fromBranch: String,
        toBranch: String
    ) async throws -> String {
        let path = "rest/api/1.0/projects/\(project)/repos/\(slug)/pull-requests"
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "title": title,
            "description": description,
            "fromRef": [
                "id": "refs/heads/\(fromBranch)",
                "repository": ["slug": slug, "project": ["key": project]],
            ],
            "toRef": [
                "id": "refs/heads/\(toBranch)",
                "repository": ["slug": slug, "project": ["key": project]],
            ],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw BitbucketError(message: "Ağ hatası: \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else {
            throw BitbucketError(message: "Beklenmeyen yanıt.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw BitbucketError(message: "PR oluşturulamadı (\(http.statusCode)):\n\(text.prefix(500))")
        }
        // Extract the self link.
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let links = json["links"] as? [String: Any],
           let selfs = links["self"] as? [[String: Any]],
           let href = selfs.first?["href"] as? String {
            return href
        }
        return baseURL.absoluteString + "/projects/\(project)/repos/\(slug)/pull-requests"
    }
}
