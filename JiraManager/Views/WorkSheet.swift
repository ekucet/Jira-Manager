import SwiftUI

struct WorkSheet: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: WorkViewModel

    init(issue: JiraIssue) {
        _vm = StateObject(wrappedValue: WorkViewModel(
            issueKey: issue.key,
            title: issue.summary,
            taskText: issue.descriptionText
        ))
    }

    /// Free-text task (e.g. a selected Confluence section).
    init(title: String, taskText: String) {
        _vm = StateObject(wrappedValue: WorkViewModel(
            issueKey: nil, title: title, taskText: taskText
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let error = vm.errorMessage {
                Divider()
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).font(.callout)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 780, height: 620)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.subtitle).font(.caption.monospaced()).foregroundStyle(.secondary)
                Text(vm.title).font(.headline).lineLimit(1)
            }
            Spacer()
            Button("Kapat") { dismiss() }
        }
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        switch vm.stage {
        case .intro:      introView
        case .running:    runningView
        case .review:     reviewView
        case .committing: committingView
        case .done:       doneView
        }
    }

    // MARK: Intro

    private var introView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Claude Code'a bu issue için ne yapması gerektiğini anlat (feedback). Açıklama ve özet otomatik ekleniyor.")
                .font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $vm.feedback)
                .font(.body)
                .border(Color.secondary.opacity(0.3))
            HStack {
                Text("Proje: \(settings.projectPath.isEmpty ? "seçilmedi ⚠️" : settings.projectPath)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button {
                    Task { await vm.runClaude(settings: settings) }
                } label: {
                    Label("Claude ile çalıştır", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .disabled(settings.projectPath.isEmpty)
            }
        }
        .padding(16)
    }

    // MARK: Running

    private var runningView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Claude Code çalışıyor… (dosyalar düzenleniyor)").font(.callout)
            }
            logView
        }
        .padding(16)
    }

    // MARK: Review

    @ViewBuilder
    private var reviewView: some View {
        if vm.noChanges {
            VStack(spacing: 12) {
                Image(systemName: "questionmark.folder").font(.largeTitle).foregroundStyle(.secondary)
                Text("Claude bu çalışmada dosya değiştirmedi.").font(.headline)
                Text("Feedback'i netleştirip tekrar deneyebilirsin.").font(.callout).foregroundStyle(.secondary)
                Button("Geri dön") { vm.stage = .intro }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Değişen dosyalar (\(vm.changedFiles.count))").font(.headline)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(vm.changedFiles, id: \.self) { f in
                            Text(f).font(.caption.monospaced())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 80)
                .background(Color.secondary.opacity(0.06))

                DisclosureGroup("Diff") {
                    ScrollView([.horizontal, .vertical]) {
                        Text(vm.diffText.isEmpty ? "(diff boş)" : vm.diffText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                    }
                    .frame(height: 200)
                    .background(Color.secondary.opacity(0.06))
                }

                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                    GridRow {
                        Text("Branch").font(.caption).foregroundStyle(.secondary)
                        TextField("branch", text: $vm.branchName).textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("PR başlığı").font(.caption).foregroundStyle(.secondary)
                        TextField("başlık", text: $vm.prTitle).textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Hedef").font(.caption).foregroundStyle(.secondary)
                        Text("→ \(settings.targetBranch)").font(.callout)
                    }
                }

                HStack {
                    Button("İptal / Geri") { vm.stage = .intro }
                    Spacer()
                    Button {
                        Task { await vm.commitAndOpenPR(settings: settings) }
                    } label: {
                        Label("Onayla → Commit, Push, PR", systemImage: "checkmark.seal")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.branchName.isEmpty || vm.prTitle.isEmpty)
                }
            }
            .padding(16)
        }
    }

    // MARK: Committing

    private var committingView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Commit + push + PR açılıyor…").font(.callout)
            }
            logView
        }
        .padding(16)
    }

    // MARK: Done

    private var doneView: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 44)).foregroundStyle(.green)
            Text("PR açıldı 🎉").font(.title3.bold())
            if let url = vm.prURL, let link = URL(string: url) {
                Link(destination: link) {
                    Label("Pull Request'i aç", systemImage: "arrow.up.right.square")
                }
                .font(.callout)
                Text(url).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Button("Kapat") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: Shared

    private var logView: some View {
        ScrollView {
            Text(vm.log.isEmpty ? "…" : vm.log)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
        }
        .background(Color.black.opacity(0.04))
    }
}
