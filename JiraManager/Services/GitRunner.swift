import Foundation

/// Runs git commands in a project directory.
struct GitRunner {
    let projectPath: String
    /// Bitbucket HTTP access token, injected as a Bearer header for network ops (fetch/push).
    var httpToken: String? = nil

    /// `-c http.extraHeader=...` args so HTTPS fetch/push authenticate without a credential prompt.
    private var authArgs: [String] {
        guard let httpToken, !httpToken.isEmpty else { return [] }
        return ["-c", "http.extraHeader=Authorization: Bearer \(httpToken)"]
    }

    private func git(_ args: [String]) async throws -> String {
        let result = try await ProcessRunner.run(executable: "/usr/bin/git", arguments: args, currentDirectory: projectPath)
        guard result.exitCode == 0 else {
            throw GitError(message: "git \(args.joined(separator: " ")) başarısız (\(result.exitCode)):\n\(result.output)")
        }
        return result.output
    }

    /// Runs a git command with the auth header (for fetch/push). Token is not echoed in errors.
    private func gitAuthed(_ args: [String]) async throws -> String {
        let result = try await ProcessRunner.run(executable: "/usr/bin/git", arguments: authArgs + args, currentDirectory: projectPath)
        guard result.exitCode == 0 else {
            throw GitError(message: "git \(args.joined(separator: " ")) başarısız (\(result.exitCode)):\n\(result.output)")
        }
        return result.output
    }

    /// Set of paths reported by `git status --porcelain` (staged or unstaged, tracked or untracked).
    func changedPaths() async throws -> Set<String> {
        let out = try await git(["status", "--porcelain"])
        var set = Set<String>()
        for line in out.split(separator: "\n") {
            // Format: "XY path" — status is first 2 chars, path from index 3.
            guard line.count > 3 else { continue }
            let path = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            // Handle renames "old -> new" by taking the new path.
            if let arrow = path.range(of: " -> ") {
                set.insert(String(path[arrow.upperBound...]))
            } else {
                set.insert(path)
            }
        }
        return set
    }

    func currentBranch() async throws -> String {
        try await git(["rev-parse", "--abbrev-ref", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Diff (including untracked, shown via intent-to-add) limited to the given paths.
    func diff(paths: [String]) async throws -> String {
        guard !paths.isEmpty else { return "" }
        // `git add -N` makes untracked files appear in diff without staging content.
        _ = try? await git(["add", "-N"] + paths)
        return try await git(["diff", "--"] + paths)
    }

    /// Fetches remote branches so PR refs are available locally.
    func fetch() async throws {
        _ = try await gitAuthed(["fetch", "origin", "--prune"])
    }

    /// The merge diff a PR would introduce: changes on `from` since it diverged from `to`.
    func pullRequestDiff(from: String, to: String) async throws -> String {
        try await git(["diff", "origin/\(to)...origin/\(from)"])
    }

    /// The `origin` remote URL.
    func remoteURL() async throws -> String {
        try await git(["config", "--get", "remote.origin.url"]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Creates a branch, stages ONLY the given paths, commits and pushes.
    /// Returns the branch name actually used.
    func commitAndPush(branch: String, message: String, paths: [String]) async throws {
        // Create (or switch to) the branch off the current HEAD.
        _ = try await git(["checkout", "-b", branch])
        // Stage only the files we were told to (protects pre-existing dirty files).
        _ = try await git(["add", "--"] + paths)
        _ = try await git(["commit", "-m", message])
        _ = try await gitAuthed(["push", "-u", "origin", branch])
    }
}

struct GitError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
