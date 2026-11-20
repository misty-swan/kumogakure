# インフラ・CI/CD 構築仕様書

個人開発において**月額固定運用費 0 円（無料枠内）** と **デプロイの再現性・安全性** を両立するためのインフラ定義書です。

---

## 1. 環境構成

| 環境 | 用途 | API ドメイン | Turso DB | RevenueCat 環境 |
| :--- | :--- | :--- | :--- | :--- |
| **`local`** | 開発者 PC（Docker / `cargo run` + Simulator） | `http://localhost:8080` | ローカル SQLite (`local.db` / `:memory:`) | StoreKit ローカル / Sandbox |
| **`dev`** | 開発検証（Week 1〜4） | Cloud Run デフォルト URL（例: `https://kumogakure-api-dev-xxxxxxxxxx-an.a.run.app`） | `kumogakure-dev` (`aws-ap-northeast-1`) | Sandbox |
| **`prod`** | App Store 公開本番（Week 5 構築） | `https://kumogakure.app`（第一候補・独自ドメイン取得後に接続） | `kumogakure-prod` (`aws-ap-northeast-1`) | Production + Sandbox |

---

## 2. Google Cloud Run（`asia-northeast1` 東京）設定

### 2.1 サービスパラメータ（`prod`）
無料枠（月 200 万リクエスト、360,000 GB-秒、180,000 vCPU-秒）内で最大効率を出す設定です。

| 設定項目 | 推奨値 | 理由 |
| :--- | :--- | :--- |
| **リージョン** | `asia-northeast1`（東京） | 日本ユーザーおよび Turso 東京リージョンへの最小レイテンシ |
| **CPU / メモリ** | `1 vCPU` / `512 MiB` | `resvg` PNG 生成の余裕確保とコスト最小化のバランス |
| **CPU 割り当て** | リクエスト処理中のみ（CPU throttling 有効） | アイドル課金ゼロ |
| **最小インスタンス (`min-instances`)** | `0` | 完全スケールゼロで維持費 0 円 |
| **最大インスタンス (`max-instances`)** | `3` | SNS バズ・攻撃時の予期せぬ課金爆発を防ぐ安全弁 |
| **同時実行数 (`concurrency`)** | `40` | Rust 非同期 I/O により 1 インスタンスで十分捌ける |
| **タイムアウト (`timeout`)** | `15s` | OGP/RC 検証含めても 15 秒以内に応答・フェイル |
| **認証 (`--allow-unauthenticated`)** | 公開（Cloudflare 経由含む） | Web/アプリから直接到達するため公開（`/internal/cleanup` はヘッダ秘密鍵検証） |
| **Startup / Liveness Probe** | `GET /health` | 高速起動確認 |

### 2.2 GCP Secret Manager
以下の機密情報はコード・Git・環境変数平文に置かず、GCP Secret Manager に格納し `--set-secrets` で Cloud Run へマウントする。
- `TURSO_AUTH_TOKEN`
- `REVENUECAT_SECRET_API_KEY`
- `INTERNAL_CLEANUP_SECRET`

---

## 3. Turso（エッジ SQLite）設定

- **ロケーション**: `aws-ap-northeast-1`（東京）を指定し、Cloud Run（東京）との RTT を数ミリ秒に抑える。
- **トークン管理**: `dev` / `prod` で完全に DB とトークンを分離（Read/Write トークンを Secret Manager に格納）。
- **無料枠目安**: ストレージ 9GB、Row Reads 25 億/月、Row Writes 2,500 万/月（Starter 無料プラン水準・変更可能性あり。定期確認のこと）。
- **マイグレーション実行**: デプロイ前ステップとして `turso db shell kumogakure-prod < migrations/XXXX.sql` または安全なマイグレーションランナーを実行する。

---

## 4. Cloudflare（Free プラン）設定

リリース直前（**Week 5**）に独自ドメインを取得したタイミングで、権威 DNS とリバースプロキシ（オレンジ雲 ON）を Cloudflare で構成します（Week 1〜4 の `dev` 検証は Cloud Run デフォルト `*.run.app` URL で進めます）。

### 4.1 SSL / セキュリティ
- **SSL/TLS 暗号化モード**: **Full (strict)**（Cloud Run の有効証明書と完全暗号化）。
- **Always Use HTTPS**: ON。
- **TLS 最小バージョン**: TLS 1.2 以上。

### 4.2 Cache Rules（無料枠最適化とクローラー保護）
Cloudflare の Cache Rules で以下を設定します（オリジンの `Cache-Control` ヘッダを尊重しつつエッジキャッシュを効かせる）。

1. **OGP 画像キャッシュ**:
   - 条件: `URI Path starts with "/ogp/"`
   - Cache eligibility: **Eligible for cache**
   - Edge TTL: Honor origin (`Cache-Control: public, max-age=86400, s-maxage=86400, immutable`)
   - Browser TTL: Honor origin
   - ※ `404` / `410` はキャッシュしないか短期キャッシュ（オリジンが `no-store` を返すため尊重される）。
2. **同時人数キャッシュ**:
   - 条件: `URI Path equals "/api/v1/stats/active"`
   - Edge TTL: Respect origin（30 秒）
3. **不在証明 Web ページ**:
   - 条件: `URI Path starts with "/s/"`
   - Edge TTL: Respect origin（30 秒）
4. **セッション作成/終了・内部エンドポイント**:
   - `/api/v1/*`（`stats/active` 除く）および `/internal/*` は **Bypass cache**。

### 4.3 WAF / Rate Limiting（Free プラン範囲）
- **Rate Limiting Rule**（Free 枠の 1 ルールを利用、または対象パス保護）:
  - `POST /api/v1/sessions` に対し同一 IP から **1 分あたり 15 リクエスト超過** で 10 秒間ブロック（`429`）。
- **Bot Fight Mode**: 注意！SNS クローラー（Twitterbot, LINE, FacebookExternalHit, Slackbot）を誤ブロックすると OGP 展開が壊れるため、**Super Bot Fight / Bot Fight Mode が SNS クローラーをブロックしないか Staging で事前実機テスト** するか、`/s/*` と `/ogp/*` は WAF スキップルールでクローラーを許容する。

---

## 5. Google Cloud Scheduler（日次クリーンアップ）

- **ジョブ名**: `kumogakure-cleanup-prod`
- **スケジュール**: `0 4 * * *`（`Asia/Tokyo` 毎日 04:00）
- **ターゲット**: `POST https://kumogakure.app/internal/cleanup`（または Cloud Run 直接 URL）
- **ヘッダ**: `X-Internal-Secret: <Secret Manager または Scheduler 設定値>`
- **リトライ**: 最大 2 回

---

## 6. CI/CD パイプライン（GitHub Actions）

### 6.1 バックエンドパイプライン（`services/api/**` 変更時）
1. **Pull Request 時（CI）**:
   - `cargo fmt --check`
   - `cargo clippy --all-targets -- -D warnings`
   - `cargo test`（インメモリ SQLite 統合テスト + OGP 生成検証）
   - `docker build`（ビルド成立チェックのみ）
2. **`main` マージ時（`dev` 自動デプロイ） / タグ `api-v*` 時（`prod` デプロイ）**:
   - Workload Identity Federation（キーレス認証）で GCP Artifact Registry へ Docker イメージ push。
   - 必要時 Turso マイグレーション適用。
   - `gcloud run deploy` で新リビジョン展開。
   - デプロイ直後に `curl -sf https://.../health?deep=1` で疎通スモークテスト。

### 6.2 iOS パイプライン（`apps/ios/**` 変更時）
1. **Pull Request 時（CI）**:
   - macOS runner 上で `xcodebuild test -scheme Kumogakure -destination 'platform=iOS Simulator,name=iPhone 16'` 実行。
2. **リリース時（タグ `ios-v*` または手動トリガー）**:
   - Xcode Cloud または Fastlane / `xcodebuild archive` で署名済み `.ipa` を作成し、TestFlight へアップロード（個人開発の初期段階ではローカル Xcode Archive → Organizer 送信でも可とし、CI 負荷を抑える）。
