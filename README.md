# JiraManager

Geliştiricinin günlük **Jira / Bitbucket / Confluence** akışını tek bir yerden yöneten, kodlama ve review işini **Claude Code**'a devreden native macOS uygulaması (SwiftUI).

## Özellikler

- **📋 İşlerim** — Üstüne atanmış Jira issue'larını listeler (Server/DC veya Cloud), detayıyla gösterir.
  - **Efor girişi** — Seçili task'a hızlı worklog (varsayılan: 09:00'dan başlayan tam gün 8 saat).
  - **Claude Code ile çalış** — Feedback'ini al, Claude Code proje klasöründe değişiklikleri yapsın, diff'i onayla, ardından **commit + push + Bitbucket PR** — her adım senin onayınla.
- **🔀 PR Review** — Açık Bitbucket PR'larını listeler, Claude Code'a diff'i inceletir, bulguları önem derecesine göre (Blocker/Major/Minor/Nit) renkli kartlarla gösterir, istersen review'ı PR'a yorum olarak ekler.
- **📄 Confluence** — Döküman arama ve uygulama içinde okuma.

## İndir & Kur

1. [**Releases**](../../releases) sayfasından en güncel `JiraManager-x.y.z.dmg` dosyasını indir.
2. DMG'yi aç, **JiraManager**'ı **Applications** klasörüne sürükle.
3. Uygulamayı aç. DMG Apple tarafından **notarize + imzalı** olduğundan çift tıkla, ekstra bir adım gerekmeden açılır.

> Uygulama hiçbir veriyi dışarı göndermez; tüm token'lar yalnızca senin **macOS Keychain**'inde saklanır.

## Gereksinimler

- macOS 14+
- [Claude Code CLI](https://claude.com/claude-code) kurulu ve giriş yapılmış (`claude login`) — kodlama ve review akışları bunu kullanır.
- Jira / Bitbucket / Confluence için erişim token'ları (uygulama içinde **Ayarlar**'dan girilir).

## Ayarlar

Uygulamada **Ayarlar**'ı aç ve doldur:

- **Jira** — kurulum tipi (Server/DC veya Cloud), URL, access token (Cloud ayrıca email ister).
- **Bitbucket** — URL ve HTTP access token.
- **Confluence** — URL ve access token (Jira'nınkinden ayrı bir token).
- **Proje klasörü** — Claude Code'un çalışacağı yerel git deposu.
- **claude CLI yolu** ve **PR hedef branch**.

## Kaynaktan Derleme

```bash
git clone https://github.com/ekucet/Jira-Manager.git
cd Jira-Manager
open JiraManager.xcodeproj   # Xcode'da Run (⌘R)
```

DMG üretmek için:

```bash
./scripts/build-dmg.sh              # ad-hoc imzalı (yerel test için)
./scripts/build-notarized-dmg.sh    # Developer ID imzalı + Apple notarize (dağıtım için)
```

Notarize'lı derleme için gereken (bir kez): login keychain'de bir **Developer ID Application** sertifikası ve `JiraManager-notary` adıyla kayıtlı bir `notarytool` kimliği (`xcrun notarytool store-credentials`).

## Mimari

- `Services/` — `JiraClient`, `BitbucketClient`, `ConfluenceClient`, `GitRunner`, `ClaudeRunner`, `ProcessRunner`, `KeychainStore`, `AppSettings`.
- `ViewModels/` — sekme bazlı durum (`IssuesViewModel`, `PRReviewViewModel`, `ConfluenceViewModel`, `WorkViewModel`).
- `Views/` — SwiftUI ekranları (`RootView` sekme kabuğu, issue liste/detay, PR review, Confluence, ayarlar, çalışma sayfası).

## Lisans

MIT
