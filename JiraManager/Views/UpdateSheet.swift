import SwiftUI

struct UpdateSheet: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var service: UpdateService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .frame(width: 460)
        .padding(24)
    }

    @ViewBuilder
    private var content: some View {
        switch service.phase {
        case .available:
            availableView
        case .downloading, .installing:
            busyView
        case .upToDate:
            messageView(icon: "checkmark.circle.fill", color: .green,
                        title: "Güncelsin",
                        detail: "En son sürümü (\(service.currentVersion)) kullanıyorsun.")
        case .failed:
            messageView(icon: "exclamationmark.triangle.fill", color: .orange,
                        title: "Güncelleme kontrol edilemedi",
                        detail: service.errorMessage ?? "Bilinmeyen hata.")
        default:
            ProgressView()
        }
    }

    private var availableView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.app.fill")
                    .font(.system(size: 34)).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Yeni sürüm mevcut").font(.headline)
                    Text("Sürüm \(service.update?.version ?? "")  ·  şu an \(service.currentVersion)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if let notes = service.update?.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Neler değişti").font(.subheadline.bold())
                ScrollView {
                    Text(notes)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
                .padding(8)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Button("Sonra") { dismiss() }
                Spacer()
                Button {
                    Task { await service.installAndRelaunch(settings: settings) }
                } label: {
                    Label("Kur ve Yeniden Başlat", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var busyView: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text(service.phase == .downloading ? "İndiriliyor…" : "Kuruluyor, uygulama birazdan yeniden başlayacak…")
                .font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func messageView(icon: String, color: Color, title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 34)).foregroundStyle(color)
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).textSelection(.enabled)
            Button("Tamam") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}
