import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            ContentView()
                .tabItem { Label("İşlerim", systemImage: "checklist") }

            PRReviewView()
                .tabItem { Label("PR Review", systemImage: "arrow.triangle.pull") }

            ConfluenceView()
                .tabItem { Label("Confluence", systemImage: "doc.richtext") }
        }
    }
}
