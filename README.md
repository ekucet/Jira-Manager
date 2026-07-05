# JiraManager

A native macOS app (SwiftUI) that streamlines a developer's daily Jira/Bitbucket/Confluence workflow — and hands the actual coding and reviewing off to Claude Code.

## Features

- **İşlerim** — Lists issues assigned to you (Jira Server/DC or Cloud), with detail view.
  - **Log work** — quick effort entry on an issue (defaults to a full 8h day at 09:00).
  - **Claude Code ile çalış** — give feedback, let Claude Code edit the project, review the diff, then commit + push + open a Bitbucket pull request — all gated by your approval.
- **PR Review** — Lists open Bitbucket pull requests, runs a Claude Code review on the diff, renders findings grouped by severity, and can post the review back as a PR comment.
- **Confluence** — Full-text search and in-app reading of Confluence pages.

## Requirements

- macOS 14+
- Xcode 16+ (built with Xcode 26 / Swift)
- [Claude Code CLI](https://claude.com/claude-code) installed and logged in (`claude login`) — used for the coding and review flows.
- Access tokens for Jira / Bitbucket / Confluence (entered in the app's Settings; stored in the macOS Keychain).

## Configuration

Open **Settings** in the app and fill in:

- **Jira** — deployment type (Server/DC or Cloud), base URL, access token (Cloud also needs email).
- **Bitbucket** — base URL and HTTP access token.
- **Confluence** — base URL and access token (a token separate from Jira's).
- **Project folder** — the local git checkout Claude Code will work in.
- **claude CLI path** and **PR target branch**.

No credentials are stored in the repository; tokens live only in your Keychain.

## Architecture

- `Services/` — `JiraClient`, `BitbucketClient`, `ConfluenceClient`, `GitRunner`, `ClaudeRunner`, `ProcessRunner`, `KeychainStore`, `AppSettings`.
- `ViewModels/` — per-tab state (`IssuesViewModel`, `PRReviewViewModel`, `ConfluenceViewModel`, `WorkViewModel`).
- `Views/` — SwiftUI screens (`RootView` tab shell, issue list/detail, PR review, Confluence, settings, work sheet).

## License

MIT
