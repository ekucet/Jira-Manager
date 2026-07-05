import SwiftUI

struct ConfluenceView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var viewModel = ConfluenceViewModel()

    var body: some View {
        NavigationSplitView {
            sidebar.frame(minWidth: 300)
        } detail: {
            detail
        }
    }

    // MARK: Sidebar (search + results)

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Confluence'ta ara…", text: $viewModel.query)
                    .textFieldStyle(.plain)
                    .onSubmit { Task { await viewModel.search(using: settings) } }
                if viewModel.isSearching { ProgressView().controlSize(.small) }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            .padding(10)

            Divider()

            if let error = viewModel.errorMessage, viewModel.results.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.largeTitle).foregroundStyle(.secondary)
                    Text(error).font(.callout).multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxHeight: .infinity)
            } else {
                List(selection: $viewModel.selectedID) {
                    ForEach(viewModel.results) { page in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(page.title).font(.body).lineLimit(2)
                            HStack(spacing: 6) {
                                if !page.spaceName.isEmpty {
                                    Text(page.spaceName)
                                }
                                if !page.updatedDisplay.isEmpty {
                                    Text("· \(page.updatedDisplay)")
                                }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        .tag(page.id)
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .onChange(of: viewModel.selectedID) { _, newValue in
            if let id = newValue {
                Task { await viewModel.loadPage(id: id, using: settings) }
            }
        }
    }

    // MARK: Detail (rendered page)

    @ViewBuilder
    private var detail: some View {
        if viewModel.loadingDetail {
            ProgressView("Döküman yükleniyor…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.detailError {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
                Text(error).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let detail = viewModel.detail {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(detail.title).font(.headline)
                        if let space = detail.space?.name ?? detail.space?.key {
                            Text(space).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let url = settings.confluenceClient?.browserURL(webui: detail.links?.webui) {
                        Link(destination: url) {
                            Label("Tarayıcıda aç", systemImage: "arrow.up.right.square")
                        }
                        .font(.callout)
                    }
                    Button {
                        // Phase 2 hook: send this document to Claude Code.
                    } label: {
                        Label("Claude ile çalış (yakında)", systemImage: "wand.and.stars")
                    }
                    .disabled(true)
                }
                .padding(12)
                Divider()
                HTMLView(html: detail.html, baseURL: settings.confluenceClient?.baseURL)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "doc.richtext").font(.system(size: 36)).foregroundStyle(.tertiary)
                Text("Ara ve bir döküman seç").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
