import Foundation

struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let assets: [Asset]
    let htmlUrl: String?

    struct Asset: Decodable {
        let name: String
        let url: String              // API URL (used with Accept: octet-stream for private repos)
        let browserDownloadUrl: String
        let size: Int

        enum CodingKeys: String, CodingKey {
            case name, url, size
            case browserDownloadUrl = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case name, body, assets
        case tagName = "tag_name"
        case htmlUrl = "html_url"
    }

    /// Version numbers from the tag, e.g. "v1.2.0" -> "1.2.0".
    var version: String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }

    /// The first `.dmg` asset, if any.
    var dmgAsset: Asset? {
        assets.first { $0.name.lowercased().hasSuffix(".dmg") }
    }
}

/// Info about an available update, ready to present.
struct AvailableUpdate {
    let version: String
    let notes: String
    let asset: GitHubRelease.Asset
    let htmlUrl: String?
}

/// Compares dotted numeric versions. Returns true if `lhs` is strictly newer than `rhs`.
enum SemVer {
    static func isNewer(_ lhs: String, than rhs: String) -> Bool {
        let a = parts(lhs), b = parts(rhs)
        let n = max(a.count, b.count)
        for i in 0..<n {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func parts(_ v: String) -> [Int] {
        v.split(whereSeparator: { $0 == "." || $0 == "-" }).map { Int($0) ?? 0 }
    }
}
