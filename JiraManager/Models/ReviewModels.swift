import SwiftUI

/// Structured result of a Claude PR review.
struct ReviewResult: Decodable {
    let summary: String
    let findings: [ReviewFinding]
}

struct ReviewFinding: Decodable, Identifiable, Hashable {
    let severity: String
    let title: String
    let file: String?
    let line: Int?
    let detail: String

    // Stable-ish id for ForEach.
    var id: String { "\(severity)|\(title)|\(file ?? "")|\(line ?? -1)" }

    var sev: Severity { Severity(rawValue: severity.lowercased()) ?? .minor }

    var locationText: String? {
        guard let file, !file.isEmpty else { return nil }
        if let line { return "\(file):\(line)" }
        return file
    }
}

enum Severity: String, CaseIterable {
    case blocker
    case major
    case minor
    case nit
    case praise

    /// Sort priority (blocker first).
    var order: Int {
        switch self {
        case .blocker: return 0
        case .major: return 1
        case .minor: return 2
        case .nit: return 3
        case .praise: return 4
        }
    }

    var label: String {
        switch self {
        case .blocker: return "Blocker"
        case .major: return "Major"
        case .minor: return "Minor"
        case .nit: return "Nit"
        case .praise: return "Olumlu"
        }
    }

    var color: Color {
        switch self {
        case .blocker: return .red
        case .major: return .orange
        case .minor: return .yellow
        case .nit: return .gray
        case .praise: return .green
        }
    }

    var icon: String {
        switch self {
        case .blocker: return "exclamationmark.octagon.fill"
        case .major: return "exclamationmark.triangle.fill"
        case .minor: return "exclamationmark.circle.fill"
        case .nit: return "info.circle"
        case .praise: return "checkmark.seal.fill"
        }
    }
}

extension ReviewResult {
    /// Extracts a ReviewResult from Claude's raw output, tolerating stray prose or code fences.
    static func parse(from raw: String) -> ReviewResult? {
        // Grab the outermost {...} block.
        guard let start = raw.firstIndex(of: "{"),
              let end = raw.lastIndex(of: "}"),
              start < end else { return nil }
        let jsonSlice = String(raw[start...end])
        guard let data = jsonSlice.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ReviewResult.self, from: data)
    }

    /// Findings sorted by severity for display.
    var sortedFindings: [ReviewFinding] {
        findings.sorted { $0.sev.order < $1.sev.order }
    }

    /// Markdown rendering, used when posting the review as a Bitbucket comment.
    var markdown: String {
        var md = "🤖 **Claude Code review**\n\n\(summary)\n"
        if findings.isEmpty {
            md += "\n_Belirgin bir sorun bulunamadı._"
            return md
        }
        for f in sortedFindings {
            let loc = f.locationText.map { " `\($0)`" } ?? ""
            md += "\n**[\(f.sev.label)] \(f.title)**\(loc)\n\(f.detail)\n"
        }
        return md
    }
}
