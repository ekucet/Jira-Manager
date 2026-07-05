import Foundation

// MARK: - User

struct JiraUser: Decodable {
    let accountId: String?   // Cloud only
    let name: String?        // Server/DC username
    let displayName: String
    let emailAddress: String?
}

// MARK: - Issue

struct JiraIssue: Decodable, Identifiable, Hashable {
    let id: String
    let key: String
    let fields: Fields

    struct Fields: Decodable, Hashable {
        let summary: String
        let status: NamedField?
        let issuetype: IssueType?
        let priority: NamedField?
        let updated: String?
        let assignee: Assignee?
        let description: RichText?
    }

    struct NamedField: Decodable, Hashable {
        let name: String
    }

    struct IssueType: Decodable, Hashable {
        let name: String
        let iconUrl: String?
        let subtask: Bool?
    }

    struct Assignee: Decodable, Hashable {
        let displayName: String
        let accountId: String?
    }

    var summary: String { fields.summary }
    var statusName: String { fields.status?.name ?? "—" }
    var typeName: String { fields.issuetype?.name ?? "—" }
    var priorityName: String { fields.priority?.name ?? "—" }
    var descriptionText: String { fields.description?.text ?? "" }

    /// A human-friendly "updated" string (falls back to the raw value on parse failure).
    var updatedDisplay: String {
        guard let raw = fields.updated else { return "" }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        guard let date else { return raw }
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }
}

// MARK: - Search response

struct JiraSearchResponse: Decodable {
    let issues: [JiraIssue]
}

// MARK: - Rich text (handles both Server plain-string and Cloud ADF descriptions)

/// Jira Server/DC returns `description` as a plain string; Jira Cloud returns ADF (a JSON object).
/// This decodes either shape into readable text.
struct RichText: Decodable, Hashable {
    let text: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            text = string
        } else if let adf = try? container.decode(ADFNode.self) {
            text = adf.plainText
        } else {
            text = ""
        }
    }
}

// MARK: - Atlassian Document Format (minimal text extraction)

/// Jira Cloud REST v3 returns rich text as ADF (a nested JSON tree).
/// We only need a readable plain-text rendering, so this decodes the parts we care about.
struct ADFNode: Decodable, Hashable {
    let type: String?
    let text: String?
    let content: [ADFNode]?

    var plainText: String {
        render().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func render() -> String {
        switch type {
        case "text":
            return text ?? ""
        case "hardBreak":
            return "\n"
        case "paragraph", "heading":
            return (content?.map { $0.render() }.joined() ?? "") + "\n\n"
        case "bulletList", "orderedList":
            return content?.map { $0.render() }.joined() ?? ""
        case "listItem":
            return "• " + (content?.map { $0.render() }.joined() ?? "")
        case "codeBlock":
            return (content?.map { $0.render() }.joined() ?? "") + "\n"
        default:
            // doc, and anything else: just concatenate children.
            return content?.map { $0.render() }.joined() ?? (text ?? "")
        }
    }
}
