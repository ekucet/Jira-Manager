import Foundation

struct BitbucketPRPage: Decodable {
    let values: [BitbucketPR]
}

struct BitbucketBranchPage: Decodable {
    let values: [BitbucketBranch]
}

struct BitbucketBranch: Decodable, Identifiable, Hashable {
    let id: String            // e.g. "refs/heads/feature/x"
    let displayId: String     // e.g. "feature/x"
    let isDefault: Bool?
    let latestCommit: String?
}

struct BitbucketPR: Decodable, Identifiable, Hashable {
    let id: Int
    let title: String
    let description: String?
    let author: Participant?
    let fromRef: Ref
    let toRef: Ref
    let links: Links?

    struct Participant: Decodable, Hashable {
        let user: User?
        struct User: Decodable, Hashable { let displayName: String? }
    }
    struct Ref: Decodable, Hashable {
        let displayId: String      // branch name, e.g. "feature/x"
        let repository: Repo?
        struct Repo: Decodable, Hashable {
            let slug: String?
            let project: Proj?
            struct Proj: Decodable, Hashable { let key: String? }
        }
    }
    struct Links: Decodable, Hashable {
        let selfLinks: [Href]?
        enum CodingKeys: String, CodingKey { case selfLinks = "self" }
        struct Href: Decodable, Hashable { let href: String? }
    }

    var authorName: String { author?.user?.displayName ?? "—" }
    var fromBranch: String { fromRef.displayId }
    var toBranch: String { toRef.displayId }
    var webURL: String? { links?.selfLinks?.first?.href }
}
