import SwiftUI

struct IssueDetailView: View {
    @EnvironmentObject private var settings: AppSettings
    let issue: JiraIssue
    let client: JiraClient?

    // Worklog form state
    @State private var timeSpent: String = "8h"
    @State private var startedDate: Date = IssueDetailView.defaultStart()
    @State private var worklogComment: String = ""
    @State private var submittingWorklog = false
    @State private var worklogResult: WorklogResult?

    enum WorklogResult {
        case success(String)
        case failure(String)
    }

    @State private var showingWorkSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                metaGrid

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Açıklama").font(.headline)
                    if issue.descriptionText.isEmpty {
                        Text("Bu issue'nun açıklaması yok.")
                            .foregroundStyle(.secondary)
                            .italic()
                    } else {
                        Text(issue.descriptionText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Divider()

                worklogSection

                Divider()

                // Hand the issue to Claude Code → review → commit/push → PR.
                VStack(alignment: .leading, spacing: 8) {
                    Text("Claude Code ile çalış").font(.headline)
                    Text("Feedback'ini al, proje klasöründe değişiklikleri yaptır, diff'i onayla, commit + push + Bitbucket PR aç.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button {
                        showingWorkSheet = true
                    } label: {
                        Label("Claude Code ile çalış", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showingWorkSheet) {
            WorkSheet(issue: issue).environmentObject(settings)
        }
    }

    // MARK: Worklog

    /// Today at 09:00 local time — the default worklog start.
    static func defaultStart() -> Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    }

    private var worklogSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Efor Gir", systemImage: "clock")
                .font(.headline)

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Harcanan süre").font(.caption).foregroundStyle(.secondary)
                    TextField("örn. 1h 30m", text: $timeSpent)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                    HStack(spacing: 6) {
                        ForEach(["30m", "1h", "2h", "4h", "8h"], id: \.self) { preset in
                            Button(preset) { timeSpent = preset }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Başlangıç").font(.caption).foregroundStyle(.secondary)
                    DatePicker("", selection: $startedDate)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Açıklama (opsiyonel)").font(.caption).foregroundStyle(.secondary)
                TextField("Ne yaptın?", text: $worklogComment, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
            }

            HStack {
                Button {
                    Task { await submitWorklog() }
                } label: {
                    if submittingWorklog {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("\(issue.key) için efor gir", systemImage: "paperplane")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(submittingWorklog || client == nil || timeSpent.trimmingCharacters(in: .whitespaces).isEmpty)

                if let result = worklogResult {
                    switch result {
                    case .success(let msg):
                        Label(msg, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green).font(.callout)
                    case .failure(let msg):
                        Label(msg, systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red).font(.callout)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func submitWorklog() async {
        guard let client else { return }
        submittingWorklog = true
        worklogResult = nil
        defer { submittingWorklog = false }
        do {
            try await client.logWork(
                issueKey: issue.key,
                timeSpent: timeSpent.trimmingCharacters(in: .whitespaces),
                started: startedDate,
                comment: worklogComment
            )
            worklogResult = .success("Kaydedildi: \(timeSpent)")
            timeSpent = "8h"
            worklogComment = ""
        } catch {
            worklogResult = .failure((error as? JiraError)?.message ?? error.localizedDescription)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(issue.key)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                if let url = client?.browserURL(for: issue) {
                    Link(destination: url) {
                        Label("Jira'da aç", systemImage: "arrow.up.right.square")
                            .font(.caption)
                    }
                }
                Spacer()
                StatusBadge(text: issue.statusName)
            }
            Text(issue.summary)
                .font(.title2.bold())
                .textSelection(.enabled)
        }
    }

    private var metaGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
            GridRow {
                metaLabel("Tür")
                Text(issue.typeName)
            }
            GridRow {
                metaLabel("Öncelik")
                Text(issue.priorityName)
            }
            GridRow {
                metaLabel("Atanan")
                Text(issue.fields.assignee?.displayName ?? "—")
            }
            GridRow {
                metaLabel("Güncellenme")
                Text(issue.updatedDisplay)
            }
        }
        .font(.callout)
    }

    private func metaLabel(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.leading)
    }
}
