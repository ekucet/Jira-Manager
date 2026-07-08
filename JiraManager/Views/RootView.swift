import SwiftUI

struct RootView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var updater: UpdateService
    @EnvironmentObject private var watch: WatchService

    var body: some View {
        TabView {
            ContentView()
                .tabItem { Label("İşlerim", systemImage: "checklist") }

            PRHubView()
                .tabItem { Label("PR", systemImage: "arrow.triangle.pull") }

            ConfluenceView()
                .tabItem { Label("Confluence", systemImage: "doc.richtext") }
        }
        .alert("Yeni gelenler", isPresented: Binding(
            get: { watch.newItemsMessage != nil },
            set: { if !$0 { watch.newItemsMessage = nil } }
        )) {
            Button("Tamam") { watch.newItemsMessage = nil }
        } message: {
            Text(watch.newItemsMessage ?? "")
        }
        .task {
            // Silent update check on launch (only surfaces if a newer version exists).
            await updater.check(silent: true)
        }
        .task {
            // Poll assigned issues + review PRs every 5 min; notify on new arrivals.
            watch.start(settings: settings)
        }
        .sheet(isPresented: $updater.showSheet) {
            UpdateSheet(service: updater)
                .environmentObject(settings)
        }
    }
}
