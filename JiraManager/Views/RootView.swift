import SwiftUI

struct RootView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var updater: UpdateService

    var body: some View {
        TabView {
            ContentView()
                .tabItem { Label("İşlerim", systemImage: "checklist") }

            PRReviewView()
                .tabItem { Label("PR Review", systemImage: "arrow.triangle.pull") }

            ConfluenceView()
                .tabItem { Label("Confluence", systemImage: "doc.richtext") }
        }
        .task {
            // Silent update check on launch (only surfaces if a newer version exists).
            await updater.check(settings: settings, silent: true)
        }
        .sheet(isPresented: $updater.showSheet) {
            UpdateSheet(service: updater)
                .environmentObject(settings)
        }
    }
}
