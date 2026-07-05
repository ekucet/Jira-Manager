import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var viewModel = IssuesViewModel()
    @State private var selection: JiraIssue.ID?
    @State private var showingSettings = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .frame(minWidth: 280)
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.reload(using: settings) }
                } label: {
                    Label("Yenile", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingSettings = true
                } label: {
                    Label("Ayarlar", systemImage: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(onClose: {
                showingSettings = false
                Task { await viewModel.reload(using: settings) }
            })
            .environmentObject(settings)
            .frame(width: 460)
        }
        .task {
            await viewModel.reload(using: settings)
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            if let user = viewModel.currentUser {
                HStack {
                    Image(systemName: "person.crop.circle")
                    Text(user.displayName).font(.subheadline).bold()
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                Divider()
            }

            if viewModel.isLoading && viewModel.issues.isEmpty {
                Spacer()
                ProgressView("Yükleniyor…")
                Spacer()
            } else if let error = viewModel.errorMessage, viewModel.issues.isEmpty {
                errorState(error)
            } else if viewModel.issues.isEmpty {
                emptyState
            } else {
                List(selection: $selection) {
                    Section("Üstüne atanmış (\(viewModel.issues.count))") {
                        ForEach(viewModel.issues) { issue in
                            IssueRow(issue: issue).tag(issue.id)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private func errorState(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(error)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Ayarları Aç") { showingSettings = true }
        }
        .padding()
        .frame(maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.largeTitle)
                .foregroundStyle(.green)
            Text("Sana atanmış açık bir issue yok.")
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxHeight: .infinity)
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let id = selection, let issue = viewModel.issues.first(where: { $0.id == id }) {
            IssueDetailView(issue: issue, client: settings.client)
                .id(issue.id)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 36))
                    .foregroundStyle(.tertiary)
                Text("Soldan bir issue seç")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct IssueRow: View {
    let issue: JiraIssue

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(issue.key)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                StatusBadge(text: issue.statusName)
            }
            Text(issue.summary)
                .font(.body)
                .lineLimit(2)
            HStack(spacing: 6) {
                Text(issue.typeName)
                if issue.priorityName != "—" {
                    Text("· \(issue.priorityName)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct StatusBadge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15), in: Capsule())
    }
}
