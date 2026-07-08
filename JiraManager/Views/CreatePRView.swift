import SwiftUI

struct CreatePRView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var vm = CreatePRViewModel()

    var body: some View {
        NavigationSplitView {
            sidebar.frame(minWidth: 300)
        } detail: {
            detail
        }
        .task { await vm.loadBranches(using: settings) }
    }

    // MARK: Sidebar (branch list)

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Branch filtrele…", text: $vm.filter)
                    .textFieldStyle(.plain)
                    .onSubmit { Task { await vm.loadBranches(using: settings) } }
                if vm.loading { ProgressView().controlSize(.small) }
                Button {
                    Task { await vm.loadBranches(using: settings) }
                } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .disabled(vm.loading)
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            .padding(10)

            Divider()

            if let error = vm.errorMessage, vm.branches.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.largeTitle).foregroundStyle(.secondary)
                    Text(error).font(.callout).multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
                .padding().frame(maxHeight: .infinity)
            } else {
                List(selection: Binding(get: { vm.selectedID }, set: { vm.selectBranch($0) })) {
                    Section("Branch'ler (\(vm.branches.count))") {
                        ForEach(vm.branches) { branch in
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.branch").font(.caption).foregroundStyle(.secondary)
                                Text(branch.displayId).font(.body).lineLimit(1)
                            }
                            .padding(.vertical, 2)
                            .tag(branch.id)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    // MARK: Detail (create PR form)

    @ViewBuilder
    private var detail: some View {
        if let branch = vm.branches.first(where: { $0.id == vm.selectedID }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Branch → target
                    HStack(spacing: 10) {
                        badge(branch.displayId, system: "arrow.triangle.branch")
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        badge(settings.targetBranch, system: "target")
                    }
                    .font(.callout)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("PR başlığı").font(.caption).foregroundStyle(.secondary)
                        TextField("başlık", text: $vm.prTitle).textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Açıklama (opsiyonel)").font(.caption).foregroundStyle(.secondary)
                        TextField("açıklama", text: $vm.prDescription, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3...6)
                    }

                    HStack {
                        Button {
                            Task { await vm.createPR(using: settings) }
                        } label: {
                            if vm.creating {
                                HStack { ProgressView().controlSize(.small); Text("Açılıyor…") }
                            } else {
                                Label("PR Aç → \(settings.targetBranch)", systemImage: "arrow.triangle.pull")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(vm.creating || vm.prTitle.isEmpty)
                    }

                    if let url = vm.createdURL, let link = URL(string: url) {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Label("PR açıldı 🎉", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green).font(.headline)
                            Link(destination: link) {
                                Label("Pull Request'i aç", systemImage: "arrow.up.right.square")
                            }
                            Text(url).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                    if let err = vm.createError {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red).font(.callout).textSelection(.enabled)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 36)).foregroundStyle(.tertiary)
                Text("Bir branch seç, dev'e PR açalım").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func badge(_ text: String, system: String) -> some View {
        Label(text, systemImage: system)
            .font(.callout.monospaced())
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.secondary.opacity(0.15), in: Capsule())
    }
}
