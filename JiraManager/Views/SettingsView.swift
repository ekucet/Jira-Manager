import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    var onClose: (() -> Void)? = nil

    @State private var testing = false
    @State private var testResult: TestResult?
    @State private var testingConfluence = false
    @State private var confluenceResult: TestResult?

    enum TestResult {
        case success(String)
        case failure(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                jiraSection
                Divider()
                bitbucketSection
                Divider()
                confluenceSection
                Divider()
                updatesSection
                Divider()
                projectSection
                Divider()
                footer
            }
            .padding(24)
        }
        .frame(minHeight: 560)
    }

    // MARK: Jira

    private var jiraSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Jira Bağlantısı", systemImage: "ladybug")
                .font(.title3.bold())

            VStack(alignment: .leading, spacing: 2) {
                Text("Kurulum tipi").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $settings.jiraDeployment) {
                    ForEach(JiraDeployment.allCases) { dep in
                        Text(dep.label).tag(dep)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            field("Jira URL", text: $settings.jiraURLString,
                  prompt: settings.jiraDeployment == .cloud
                        ? "https://sirketin.atlassian.net"
                        : "https://jira.example.com")

            if settings.jiraDeployment == .cloud {
                field("Email", text: $settings.jiraEmail, prompt: "ad@sirket.com")
            }

            secureField(settings.jiraDeployment == .cloud ? "API Token" : "Access Token",
                        text: $settings.jiraToken)

            Text(settings.jiraDeployment == .cloud
                 ? "Cloud: HTTP Basic (email + API token)."
                 : "Server/DC: Access token Bearer olarak gönderilir. Email gerekmez.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Bitbucket

    private var bitbucketSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Bitbucket Bağlantısı", systemImage: "arrow.triangle.branch")
                .font(.title3.bold())
            Text("Faz 3'te push + PR açmak için kullanılacak.")
                .font(.caption).foregroundStyle(.secondary)

            field("Bitbucket URL", text: $settings.bitbucketURLString,
                  prompt: "https://bitbucket.example.com")
            secureField("HTTP Access Token (PAT)", text: $settings.bitbucketToken)
        }
    }

    // MARK: Confluence

    private var confluenceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Confluence Bağlantısı", systemImage: "doc.richtext")
                .font(.title3.bold())
            Text("Döküman arama ve okuma için. Jira'dan ayrı bir access token gerekir.")
                .font(.caption).foregroundStyle(.secondary)

            field("Confluence URL", text: $settings.confluenceURLString,
                  prompt: "https://confluence.example.com")
            secureField("Access Token", text: $settings.confluenceToken)

            HStack {
                Button {
                    Task { await testConfluence() }
                } label: {
                    if testingConfluence {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Confluence Bağlantısını Test Et")
                    }
                }
                .disabled(testingConfluence || settings.confluenceClient == nil)

                if let result = confluenceResult {
                    switch result {
                    case .success(let msg):
                        Label(msg, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green).font(.callout)
                    case .failure(let msg):
                        Label(msg, systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red).font(.callout).textSelection(.enabled)
                    }
                }
            }
        }
    }

    // MARK: Updates

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Güncelleme", systemImage: "arrow.down.app")
                .font(.title3.bold())
            HStack {
                Text("Yüklü sürüm").font(.caption).foregroundStyle(.secondary)
                Text(appVersion).font(.caption.monospaced())
            }
            Text("Repo private olduğu için güncelleme kontrolü bir GitHub token ister (repo okuma yetkisi).")
                .font(.caption).foregroundStyle(.secondary)
            secureField("GitHub Token", text: $settings.githubToken)
            Text("Kontrol için menü: JiraManager → “Güncellemeleri Denetle…”")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Project

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Proje Klasörü", systemImage: "folder")
                .font(.title3.bold())
            HStack {
                TextField("/Users/…/proje", text: $settings.projectPath)
                    .textFieldStyle(.roundedBorder)
                Button("Seç…") { chooseFolder() }
            }
            Text("Claude Code bu klasörde çalışacak.")
                .font(.caption).foregroundStyle(.secondary)

            field("claude CLI yolu", text: $settings.claudePath, prompt: "~/.local/bin/claude")
            field("PR hedef branch", text: $settings.targetBranch, prompt: "dev")
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    Task { await testConnection() }
                } label: {
                    if testing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Jira Bağlantısını Test Et")
                    }
                }
                .disabled(testing || settings.client == nil)

                Spacer()

                if onClose != nil {
                    Button("Kapat") { onClose?() }
                        .keyboardShortcut(.defaultAction)
                }
            }

            if let result = testResult {
                switch result {
                case .success(let msg):
                    Label(msg, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.callout)
                case .failure(let msg):
                    Label(msg, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red).font(.callout)
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: Helpers

    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
        }
    }

    private func secureField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            SecureField("••••••••", text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.projectPath = url.path
        }
    }

    private func testConnection() async {
        guard let client = settings.client else { return }
        testing = true
        testResult = nil
        defer { testing = false }
        do {
            let user = try await client.myself()
            testResult = .success("Bağlandı: \(user.displayName)")
        } catch {
            testResult = .failure((error as? JiraError)?.message ?? error.localizedDescription)
        }
    }

    private func testConfluence() async {
        guard let client = settings.confluenceClient else { return }
        testingConfluence = true
        confluenceResult = nil
        defer { testingConfluence = false }
        do {
            let user = try await client.currentUser()
            confluenceResult = .success("Bağlandı: \(user.displayName ?? user.username ?? "OK")")
        } catch {
            confluenceResult = .failure((error as? ConfluenceError)?.message ?? error.localizedDescription)
        }
    }
}
