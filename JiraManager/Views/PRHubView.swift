import SwiftUI

struct PRHubView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case create = "Aç"
        case review = "Review"
        case approve = "Onay"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .review

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { m in Text(m.rawValue).tag(m) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: 360)

            Divider()

            switch mode {
            case .create: CreatePRView()
            case .review: PRReviewView()
            case .approve: ApprovalView()
            }
        }
    }
}
