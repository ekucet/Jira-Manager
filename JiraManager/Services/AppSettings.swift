import Foundation
import Combine

/// Jira hosting type — changes API version, auth scheme and payload format.
enum JiraDeployment: String, CaseIterable, Identifiable {
    case server   // Jira Server / Data Center (on-prem): API v2, Bearer PAT
    case cloud    // Jira Cloud: API v3, Basic email:token, ADF

    var id: String { rawValue }
    var label: String {
        switch self {
        case .server: return "Server / Data Center (on-prem)"
        case .cloud: return "Cloud (atlassian.net)"
        }
    }
}

/// Holds all connection configuration.
/// - URLs, email, deployment type live in UserDefaults.
/// - API tokens live in the Keychain (accounts "jira" and "bitbucket").
@MainActor
final class AppSettings: ObservableObject {

    // MARK: Jira

    @Published var jiraDeployment: JiraDeployment {
        didSet { UserDefaults.standard.set(jiraDeployment.rawValue, forKey: Keys.jiraDeployment) }
    }
    @Published var jiraURLString: String {
        didSet { UserDefaults.standard.set(jiraURLString, forKey: Keys.jiraURL) }
    }
    /// Only needed for Cloud (Basic auth). Ignored for Server/DC (Bearer PAT).
    @Published var jiraEmail: String {
        didSet { UserDefaults.standard.set(jiraEmail, forKey: Keys.jiraEmail) }
    }
    @Published var jiraToken: String {
        didSet { writeToken(jiraToken, account: KeychainAccount.jira) }
    }

    // MARK: Bitbucket

    @Published var bitbucketURLString: String {
        didSet { UserDefaults.standard.set(bitbucketURLString, forKey: Keys.bitbucketURL) }
    }
    @Published var bitbucketToken: String {
        didSet { writeToken(bitbucketToken, account: KeychainAccount.bitbucket) }
    }

    // MARK: Confluence

    @Published var confluenceURLString: String {
        didSet { UserDefaults.standard.set(confluenceURLString, forKey: Keys.confluenceURL) }
    }
    @Published var confluenceToken: String {
        didSet { writeToken(confluenceToken, account: KeychainAccount.confluence) }
    }

    // MARK: Local project

    /// Absolute path to the local project folder Claude Code will work in (Phase 2).
    @Published var projectPath: String {
        didSet { UserDefaults.standard.set(projectPath, forKey: Keys.projectPath) }
    }
    /// Path to the `claude` CLI binary.
    @Published var claudePath: String {
        didSet { UserDefaults.standard.set(claudePath, forKey: Keys.claudePath) }
    }
    /// Branch that PRs target (integration branch).
    @Published var targetBranch: String {
        didSet { UserDefaults.standard.set(targetBranch, forKey: Keys.targetBranch) }
    }

    private enum Keys {
        static let jiraDeployment = "jira.deployment"
        static let jiraURL = "jira.baseURL"
        static let jiraEmail = "jira.email"
        static let bitbucketURL = "bitbucket.baseURL"
        static let confluenceURL = "confluence.baseURL"
        static let projectPath = "jira.projectPath"
        static let claudePath = "claude.path"
        static let targetBranch = "git.targetBranch"
    }

    private enum KeychainAccount {
        static let jira = "jira"
        static let bitbucket = "bitbucket"
        static let confluence = "confluence"
    }

    init() {
        let d = UserDefaults.standard
        jiraDeployment = JiraDeployment(rawValue: d.string(forKey: Keys.jiraDeployment) ?? "") ?? .server
        jiraURLString = d.string(forKey: Keys.jiraURL) ?? ""
        jiraEmail = d.string(forKey: Keys.jiraEmail) ?? ""
        bitbucketURLString = d.string(forKey: Keys.bitbucketURL) ?? ""
        confluenceURLString = d.string(forKey: Keys.confluenceURL) ?? ""
        projectPath = d.string(forKey: Keys.projectPath) ?? ""
        let defaultClaude = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/claude").path
        claudePath = d.string(forKey: Keys.claudePath) ?? defaultClaude
        targetBranch = d.string(forKey: Keys.targetBranch) ?? "dev"
        jiraToken = KeychainStore.get(account: KeychainAccount.jira) ?? ""
        bitbucketToken = KeychainStore.get(account: KeychainAccount.bitbucket) ?? ""
        confluenceToken = KeychainStore.get(account: KeychainAccount.confluence) ?? ""
    }

    private func writeToken(_ value: String, account: String) {
        if value.isEmpty {
            KeychainStore.delete(account: account)
        } else {
            KeychainStore.set(value, account: account)
        }
    }

    var isConfigured: Bool { client != nil }

    /// Builds a ready-to-use Jira client if configuration is complete.
    var client: JiraClient? {
        guard let url = Self.normalizedURL(jiraURLString) else { return nil }
        guard !jiraToken.isEmpty else { return nil }
        // Cloud additionally needs an email for Basic auth.
        if jiraDeployment == .cloud && jiraEmail.isEmpty { return nil }
        return JiraClient(baseURL: url, deployment: jiraDeployment, email: jiraEmail, token: jiraToken)
    }

    /// Builds a Confluence client if URL + token are set.
    var confluenceClient: ConfluenceClient? {
        guard let url = Self.normalizedURL(confluenceURLString), !confluenceToken.isEmpty else { return nil }
        return ConfluenceClient(baseURL: url, token: confluenceToken)
    }

    static func normalizedURL(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        if !s.hasPrefix("http://") && !s.hasPrefix("https://") { s = "https://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        return URL(string: s)
    }
}
