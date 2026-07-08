import SwiftUI

struct PRReviewView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var vm = PRReviewViewModel()

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 320)
            Divider()
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await vm.loadPRs(using: settings) }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Toggle("Sadece bana atanan", isOn: $vm.onlyReviewer)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .onChange(of: vm.onlyReviewer) { _, _ in
                        Task { await vm.loadPRs(using: settings) }
                    }
                Spacer()
                Button {
                    Task { await vm.loadPRs(using: settings) }
                } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .disabled(vm.loading)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            Divider()

            if vm.loading && vm.prs.isEmpty {
                Spacer(); ProgressView("Yükleniyor…"); Spacer()
            } else if let error = vm.errorMessage, vm.prs.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.pull").font(.largeTitle).foregroundStyle(.secondary)
                    Text(error).font(.callout).multilineTextAlignment(.center).foregroundStyle(.secondary)
                }.padding().frame(maxHeight: .infinity)
            } else {
                List(selection: $vm.selectedID) {
                    ForEach(vm.prs) { pr in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("#\(pr.id)").font(.caption.monospaced()).foregroundStyle(.secondary)
                                Spacer()
                                Text("\(pr.fromBranch) → \(pr.toBranch)")
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Text(pr.title).font(.body).lineLimit(2)
                            Text(pr.authorName).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        .tag(pr.id)
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let id = vm.selectedID, let pr = vm.prs.first(where: { $0.id == id }) {
            PRDetail(pr: pr, vm: vm)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "arrow.triangle.pull").font(.system(size: 36)).foregroundStyle(.tertiary)
                Text("Bir PR seç, Claude'a inceletelim").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct PRDetail: View {
    let pr: BitbucketPR
    @ObservedObject var vm: PRReviewViewModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("#\(pr.id) · \(pr.fromBranch) → \(pr.toBranch)")
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                        Text(pr.title).font(.title3.bold())
                        Text("Açan: \(pr.authorName)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let url = pr.webURL, let link = URL(string: url) {
                        Link(destination: link) { Label("Aç", systemImage: "arrow.up.right.square") }
                    }
                }

                Button {
                    Task { await vm.review(pr, using: settings) }
                } label: {
                    if vm.reviewing {
                        HStack { ProgressView().controlSize(.small); Text("İnceleniyor…") }
                    } else {
                        Label("Claude ile review yaptır", systemImage: "wand.and.stars")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.reviewing || settings.projectPath.isEmpty)

                if let error = vm.reviewError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).font(.callout).textSelection(.enabled)
                }

                if vm.reviewing && vm.reviewText.isEmpty {
                    Text(vm.reviewLog.isEmpty ? "…" : vm.reviewLog)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !vm.reviewText.isEmpty {
                    Divider()

                    if let result = vm.reviewResult {
                        ReviewResultView(result: result)
                    } else {
                        // Fallback: model didn't return parseable JSON — show raw text.
                        Text("Review").font(.headline)
                        Text(vm.reviewText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack {
                        Button {
                            Task { await vm.postReviewAsComment(pr, using: settings) }
                        } label: {
                            if vm.posting {
                                HStack { ProgressView().controlSize(.small); Text("Ekleniyor…") }
                            } else {
                                Label("Review'ı PR'a yorum olarak ekle", systemImage: "text.bubble")
                            }
                        }
                        .disabled(vm.posting)
                        if let msg = vm.postResult {
                            Text(msg).font(.callout).foregroundStyle(.secondary)
                        }
                    }

                    DisclosureGroup("Diff") {
                        ScrollView([.horizontal, .vertical]) {
                            Text(vm.diffText)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(6)
                        }
                        .frame(height: 220)
                        .background(Color.secondary.opacity(0.06))
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(pr.id)
    }
}

// MARK: - Structured review rendering

private struct ReviewResultView: View {
    let result: ReviewResult

    private var findings: [ReviewFinding] { result.sortedFindings }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Summary card
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles").foregroundStyle(.purple)
                Text(result.summary)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

            // Severity counts
            if !findings.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Severity.allCases, id: \.self) { sev in
                        let count = findings.filter { $0.sev == sev }.count
                        if count > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: sev.icon)
                                Text("\(count) \(sev.label)")
                            }
                            .font(.caption.bold())
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(sev.color.opacity(0.15), in: Capsule())
                            .foregroundStyle(sev.color)
                        }
                    }
                }
            }

            if findings.isEmpty {
                Label("Belirgin bir sorun bulunamadı 👍", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else {
                ForEach(findings) { finding in
                    FindingCard(finding: finding)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FindingCard: View {
    let finding: ReviewFinding

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label(finding.sev.label, systemImage: finding.sev.icon)
                    .font(.caption.bold())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(finding.sev.color.opacity(0.18), in: Capsule())
                    .foregroundStyle(finding.sev.color)
                Text(finding.title)
                    .font(.subheadline.bold())
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }
            if let loc = finding.locationText {
                Text(loc)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Text(finding.detail)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(finding.sev.color.opacity(0.35), lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(finding.sev.color)
                .frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }
}
