import SwiftUI

struct ApprovalView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var vm = ApprovalViewModel()

    var body: some View {
        NavigationSplitView {
            sidebar.frame(minWidth: 300)
        } detail: {
            detail
        }
        .task { await vm.loadPRs(using: settings) }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Toggle("Onayına düşenler", isOn: $vm.onlyReviewer)
                    .toggleStyle(.checkbox).font(.caption)
                    .onChange(of: vm.onlyReviewer) { _, _ in Task { await vm.loadPRs(using: settings) } }
                Spacer()
                Button { Task { await vm.loadPRs(using: settings) } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).disabled(vm.loading)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            Divider()

            if vm.loading && vm.prs.isEmpty {
                Spacer(); ProgressView("Yükleniyor…"); Spacer()
            } else if let error = vm.errorMessage, vm.prs.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal").font(.largeTitle).foregroundStyle(.secondary)
                    Text(error).font(.callout).multilineTextAlignment(.center).foregroundStyle(.secondary)
                }.padding().frame(maxHeight: .infinity)
            } else {
                List(selection: $vm.selectedID) {
                    ForEach(vm.prs) { pr in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("#\(pr.id)").font(.caption.monospaced()).foregroundStyle(.secondary)
                                Spacer()
                                if vm.myStatus(on: pr) == "APPROVED" {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                                }
                            }
                            Text(pr.title).font(.body).lineLimit(2)
                            Text("\(pr.fromBranch) → \(pr.toBranch)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .padding(.vertical, 2).tag(pr.id)
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let id = vm.selectedID, let pr = vm.prs.first(where: { $0.id == id }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
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

                    // My status + actions
                    let mine = vm.myStatus(on: pr)
                    HStack(spacing: 10) {
                        if mine == "APPROVED" {
                            Label("Onayladın", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                            Button {
                                Task { await vm.unapprove(pr, using: settings) }
                            } label: { Label("Onayı Geri Al", systemImage: "arrow.uturn.backward") }
                                .disabled(vm.acting)
                        } else {
                            Button {
                                Task { await vm.approve(pr, using: settings) }
                            } label: {
                                if vm.acting {
                                    HStack { ProgressView().controlSize(.small); Text("İşleniyor…") }
                                } else {
                                    Label("Onayla", systemImage: "checkmark.seal.fill")
                                }
                            }
                            .buttonStyle(.borderedProminent).disabled(vm.acting)
                        }
                    }

                    if let err = vm.actionError {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red).font(.callout).textSelection(.enabled)
                    }

                    Divider()

                    // Reviewers
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reviewer'lar").font(.headline)
                        if let reviewers = pr.reviewers, !reviewers.isEmpty {
                            ForEach(reviewers) { r in
                                HStack(spacing: 8) {
                                    Image(systemName: icon(for: r.status))
                                        .foregroundStyle(color(for: r.status))
                                    Text(r.user?.displayName ?? r.user?.name ?? "—")
                                    Spacer()
                                    Text(label(for: r.status)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Text("Reviewer atanmamış.").foregroundStyle(.secondary).italic().font(.callout)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(pr.id)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.seal").font(.system(size: 36)).foregroundStyle(.tertiary)
                Text("Onaylamak için bir PR seç").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func icon(for status: String?) -> String {
        switch status {
        case "APPROVED": return "checkmark.circle.fill"
        case "NEEDS_WORK": return "exclamationmark.circle.fill"
        default: return "circle"
        }
    }
    private func color(for status: String?) -> Color {
        switch status {
        case "APPROVED": return .green
        case "NEEDS_WORK": return .orange
        default: return .secondary
        }
    }
    private func label(for status: String?) -> String {
        switch status {
        case "APPROVED": return "Onayladı"
        case "NEEDS_WORK": return "Değişiklik istiyor"
        default: return "Bekliyor"
        }
    }
}
