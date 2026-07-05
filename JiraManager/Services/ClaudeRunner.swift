import Foundation

/// Runs Claude Code headlessly to make code changes in the project.
struct ClaudeRunner {
    let claudePath: String
    let projectPath: String

    /// Builds the instruction prompt from an issue and the user's feedback.
    static func buildPrompt(issueKey: String, summary: String, description: String, feedback: String) -> String {
        var p = """
        You are working inside this project's git repository to address a Jira issue.

        Jira issue: \(issueKey)
        Summary: \(summary)
        """
        if !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            p += "\n\nDescription:\n\(description)"
        }
        if !feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            p += "\n\nUser guidance / feedback (follow this closely):\n\(feedback)"
        }
        p += """


        Make the necessary code changes in this repository to implement/fix the issue.
        Rules:
        - Only edit files. Do NOT commit, push, or create git branches — the surrounding tool handles that.
        - Keep changes focused on this issue.
        - When done, briefly summarize what you changed and why.
        """
        return p
    }

    /// A prompt built directly from free text (e.g. a Confluence doc task).
    static func buildFreePrompt(_ text: String) -> String {
        """
        You are working inside this project's git repository.

        Task:
        \(text)

        Rules:
        - Only edit files. Do NOT commit, push, or create git branches — the surrounding tool handles that.
        - When done, briefly summarize what you changed and why.
        """
    }

    func run(prompt: String, onLine: @escaping @MainActor (String) -> Void) async throws -> ProcessResult {
        // Prompt goes via stdin to avoid argument-length limits with big descriptions.
        let args = ["-p", "--permission-mode", "acceptEdits"]
        return try await ProcessRunner.run(
            executable: claudePath,
            arguments: args,
            currentDirectory: projectPath,
            stdin: prompt,
            onLine: onLine
        )
    }

    /// Read-only code review of a diff. Returns Claude's findings as text.
    func review(prTitle: String, diff: String, onLine: @escaping @MainActor (String) -> Void) async throws -> ProcessResult {
        let prompt = """
        You are a senior code reviewer. Review the following pull request diff.
        PR title: \(prTitle)

        Respond with ONLY a single JSON object (no prose before/after, no markdown code fences) with this exact shape:
        {
          "summary": "1-3 sentence overall assessment, in Turkish",
          "findings": [
            {
              "severity": "Blocker" | "Major" | "Minor" | "Nit" | "Praise",
              "title": "short finding title, in Turkish",
              "file": "path/to/file relative to repo, or empty string",
              "line": 123,
              "detail": "clear, actionable explanation, in Turkish"
            }
          ]
        }
        Rules:
        - Focus on correctness bugs, security, edge cases, and API misuse. Skip trivial style unless it hurts readability.
        - "line" is optional; use the new-file line number when known, otherwise omit it or set null.
        - Order does not matter; the UI sorts by severity.
        - If the PR looks solid, return an empty "findings" array and a positive "summary".
        - Write all Turkish text naturally. Do NOT modify any files.

        --- DIFF ---
        \(diff)
        --- END DIFF ---
        """
        // Plan permission mode guarantees no file edits during review.
        let args = ["-p", "--permission-mode", "plan"]
        return try await ProcessRunner.run(
            executable: claudePath,
            arguments: args,
            currentDirectory: projectPath,
            stdin: prompt,
            onLine: onLine
        )
    }
}
