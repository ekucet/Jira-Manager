import Foundation

// MARK: - User (for connection test)

struct ConfluenceUser: Decodable {
    let username: String?
    let displayName: String?
}

// MARK: - Search results

struct ConfluenceSearchResponse: Decodable {
    let results: [ConfluencePage]
}

struct ConfluencePage: Decodable, Identifiable, Hashable {
    let id: String
    let type: String?
    let title: String
    let space: Space?
    let version: Version?
    let links: Links?

    struct Space: Decodable, Hashable {
        let key: String?
        let name: String?
    }
    struct Version: Decodable, Hashable {
        let when: String?
    }
    struct Links: Decodable, Hashable {
        let webui: String?
    }

    enum CodingKeys: String, CodingKey {
        case id, type, title, space, version
        case links = "_links"
    }

    var spaceName: String { space?.name ?? space?.key ?? "" }

    var updatedDisplay: String {
        guard let raw = version?.when else { return "" }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        guard let date else { return "" }
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        return fmt.string(from: date)
    }
}

// MARK: - Page detail (with body)

struct ConfluencePageDetail: Decodable {
    let id: String
    let title: String
    let body: Body?
    let space: ConfluencePage.Space?
    let links: ConfluencePage.Links?

    struct Body: Decodable {
        let exportView: Value?
        let storage: Value?
        struct Value: Decodable { let value: String }

        enum CodingKeys: String, CodingKey {
            case exportView = "export_view"
            case storage
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, body, space
        case links = "_links"
    }

    /// Best available HTML for display.
    var html: String { body?.exportView?.value ?? body?.storage?.value ?? "" }
}
