# 雲隠れ（Kumogakure）実装ステータス管理（STATE）

本ファイルは [docs/06-plan/roadmap-and-wbs.md](docs/06-plan/roadmap-and-wbs.md)（Week 0〜Week 6）に基づく全体の実装進捗・構成済みリソース・検証ログ・次期ブロッカーを一元管理する運用トラッカーです。

> **セキュリティ原則**: API キー・認証トークン・Google フォームの編集用 `/edit` URL などの機密情報は本ファイルへ絶対に記載しません（機密値は GCP Secret Manager またはローカル `.env` のみで管理）。

---

## 1. サマリー

- **最終更新日**: `2026-11-20`
- **現在フェーズ**: `Week 1 完了 → Week 2（Rust API・OGP・不在証明 Web ページ実装）へ移行可能`
- **全体進捗**: **7 / 32 タスク完了**（**Week 0・Week 1 全完了**）

| フェーズ | 完了 | 進行中 | 未着手 | 主な状況 |
| :--- | :---: | :---: | :---: | :--- |
| **Week 0**（無料事前セットアップ） | 1 | 0 | 0 | フォーム 2 種作成・公開 URL 反映済（※メール通知 ON＆テスト送信はブラウザ確認待ち） |
| **Week 1**（初期化・素材・`dev` インフラ） | 6 | 0 | 0 | **全完了**（モノレポ・画像・音声・フォント・Turso `dev`・Cloud Run `dev` `/health?deep=1` 疎通済） |
| **Week 2**（Rust API・OGP・DB 完成） | 0 | 0 | 6 | Week 1 の `dev` 疎通後に着手 |
| **Week 3**（iOS コア体験） | 0 | 0 | 6 | Week 1 の素材準備完了・Xcode 実装待ち |
| **Week 4**（不在証明連携・ローカル課金） | 0 | 0 | 6 | — |
| **Week 5**（独自ドメイン・CF・RC 本番） | 0 | 0 | 5 | — |
| **Week 6**（TestFlight QA・App Store 審査） | 0 | 0 | 4 | — |

---

## 2. 環境・公開リソース一覧

| リソース / 識別子 | 環境 | ステータス | 公開値 / メモ |
| :--- | :--- | :--- | :--- |
| **お問い合わせ・不具合報告フォーム**（フォーム ①） | 共通 | `作成済` | `https://docs.google.com/forms/d/e/1FAIpQLScOjICc8nN83rTRGXd2oYbvBicAxNB8yvrFXsNFjE00xLIqgQ/viewform` |
| **UGC 通報フォームテンプレート**（フォーム ②） | 共通 | `作成済` | `https://docs.google.com/forms/d/e/1FAIpQLSf4jPMH3ZLLRR6u6AB4S8t5xHg3zGQDsmFG_mIDqrxwxEX2Wg/viewform?usp=pp_url&entry.1371370885={session_id}` |
| **Turso DB（`kumogakure-dev`）** | `dev` | `稼働中` | `libsql://kumogakure-dev-misty-swan.aws-ap-northeast-1.turso.io`（`aws-ap-northeast-1`, group `default`, `0001_init` 適用・`/health?deep=1` 疎通済） |
| **GCP Project / Artifact Registry** | `dev` | `構築済` | Project: `project-08414a32-51ef-4d05-af6`（`kumogakure-dev`）/ AR: `asia-northeast1-docker.pkg.dev/project-08414a32-51ef-4d05-af6/kumogakure` |
| **Cloud Run（`kumogakure-api-dev`）** | `dev` | `稼働中` | `https://kumogakure-api-dev-fpdy7efquq-an.a.run.app`（`asia-northeast1`, `1 vCPU / 512Mi`, `min=0, max=3`, `concurrency=40`, `timeout=15s`, `/health` & `/health?deep=1` `200 OK`） |
| **独自ドメイン / Cloudflare / 本番環境** | `prod` | `Week 5 予定` | 第一候補 `kumogakure.app` |
| **Apple Developer / RevenueCat 本番** | `prod` | `Week 4〜5 予定` | 仮 Bundle ID: `app.kumogakure.ios` / Entitlement: `hermit_pro` |

---

## 3. 週次 WBS 進捗詳細

### Week 0: 無料事前セットアップ

| ID | タスク | ステータス | 成果物・確認メモ |
| :--- | :--- | :--- | :--- |
| **W0-1** | Google フォーム 2 種作成（お問い合わせ・UGC 通報 `entry.1371370885={session_id}`） | `✅ 完了` | [create-google-forms.gs](infra/forms/create-google-forms.gs) 実行で作成し、公開 URL を [.env.example](services/api/.env.example)・[deploy-cloudrun-dev.sh](infra/scripts/deploy-cloudrun-dev.sh)・[legal-drafts.md](docs/05-release/legal-drafts.md)・[google-forms-setup.md](infra/forms/google-forms-setup.md) へ反映済（※両 `/edit` 画面でのメール通知 ON＆テスト送信はオーナー最終確認待ち） |

### Week 1: 環境構築・素材制作・`dev` インフラ構築

| ID | タスク | ステータス | 成果物・確認メモ |
| :--- | :--- | :--- | :--- |
| **W1-1** | モノレポ初期化（`apps/ios`, `services/api`, `infra`） | `✅ 完了` | `git init -b main`、[.gitignore](.gitignore)、[apps/ios/README.md](apps/ios/README.md)、基本ディレクトリ構成を作成済 |
| **W1-2** | 風景画像 4 種制作（`1290x2796`・600KB 以下） | `✅ 完了` | `misty_mountain` (`278,859 B`), `rainy_bamboo` (`504,263 B`), `moonlit_lake` (`228,625 B`), `dawn_shrine` (`277,824 B`) を `Assets.xcassets/Landscapes/` と [ASSETS_CREDITS.md](apps/ios/Kumogakure/Resources/ASSETS_CREDITS.md) に配置済 |
| **W1-3** | 環境音 3 種ループ編集（-18〜-20 LUFS・1.5MB 以下） | `✅ 完了` | `rain.m4a` (`-19.11 LUFS`, `971,876 B`), `night_wind.m4a` (`-19.01 LUFS`, `971,883 B`), `bonfire.m4a` (`-19.19 LUFS`, `971,926 B`)（各 60.0s, AAC-LC 44.1kHz Stereo 128kbps）を `Sounds/` へ配置・試聴検証済 |
| **W1-4** | OGP 用和文フォント 2 種＋SIL OFL 配置 | `✅ 完了` | [ShipporiMincho-Regular.ttf](services/api/assets/fonts/ShipporiMincho-Regular.ttf), [NotoSerifJP-Regular.otf](services/api/assets/fonts/NotoSerifJP-Regular.otf), 両 SIL OFL ライセンスと [fonts/README.md](services/api/assets/fonts/README.md) を配置・[backend-spec.md](docs/03-architecture/backend-spec.md) 同期済 |
| **W1-5** | Turso DB 作成（`kumogakure-dev`）＋ `0001_init.sql` 適用 | `✅ 完了` | `libsql://kumogakure-dev-misty-swan.aws-ap-northeast-1.turso.io`（`aws-ap-northeast-1`）作成、`0001_init` 適用・テーブル/インデックス確認、ローカルおよび Cloud Run からライブ `GET /health?deep=1` (`200 OK`, `db: "ok"`) 疎通済 |
| **W1-6** | GCP・AR・Secret Manager・Cloud Run `dev` 初期構築 | `✅ 完了` | `project-08414a32-51ef-4d05-af6` 上で AR / SA / Secret Manager（`TURSO_AUTH_TOKEN` 登録済）を構築し、`kumogakure-api-dev`（`kumogakure-api-dev-00004-6vr`）をデプロイ。`https://kumogakure-api-dev-fpdy7efquq-an.a.run.app/health` と `?deep=1` で `200 OK` 確認済（GFE 予約パス回避のため `/healthz` から `/health` へ統一・[api-spec.md](docs/03-architecture/api-spec.md) 等同期済） |

### Week 2: Rust（Axum）バックエンド実装・`dev` デプロイ

| ID | タスク | ステータス | メモ |
| :--- | :--- | :--- | :--- |
| **W2-1** | ドメイン層（nanoid / `owner_token` / 書記素サニタイズ / NG ワード / TZ） | `⏳ 未着手` | 仕様正本: [backend-spec.md](docs/03-architecture/backend-spec.md) |
| **W2-2** | セッション API（`POST /sessions`, `POST /finish`, `GET /stats/active`） | `⏳ 未着手` | 仕様正本: [api-spec.md](docs/03-architecture/api-spec.md) |
| **W2-3** | RevenueCat REST API 検証クライアント（60 秒キャッシュ + Fail-Open） | `⏳ 未着手` | — |
| **W2-4** | 不在証明 HTML（`/s/{id}`）＋ 法務静的ページ ＋ 410/404 | `⏳ 未着手` | フォーム ② の `REPORT_FORM_URL_TEMPLATE` を埋込予定 |
| **W2-5** | 動的 OGP 生成（`ogp_card.svg` + `resvg` + `spawn_blocking` + セマフォ） | `⏳ 未着手` | 仕様正本: [absence-card-spec.md](docs/02-design/absence-card-spec.md) |
| **W2-6** | `/internal/cleanup` + GitHub Actions CI + Cloud Scheduler | `⏳ 未着手` | — |

### Week 3: iOS アプリ（MVP コア体験）実装

| ID | タスク | ステータス | メモ |
| :--- | :--- | :--- | :--- |
| **W3-1** | Xcode プロジェクト・`AppConfig`・デザインシステム | `⏳ 未着手` | 仕様正本: [ios-app-spec.md](docs/03-architecture/ios-app-spec.md) |
| **W3-2** | `KeychainHelper` ＋ SwiftData `DetoxSessionRecord` ＋ `UserDefaults` | `⏳ 未着手` | — |
| **W3-3** | `DetoxTimerEngine` ＋ `AppLifecycleMonitor`（10 秒猶予・ロック許容） | `⏳ 未着手` | — |
| **W3-4** | `FogView`（多層霧＋Reduce Motion）＋ ハプティクス | `⏳ 未着手` | — |
| **W3-5** | `AmbientAudioManager`（無音時非起動・フェード・着信割り込み） | `⏳ 未着手` | — |
| **W3-6** | 画面 S-01 / S-03 / S-04 / S-05 実装 | `⏳ 未着手` | — |

### Week 4〜Week 6: 連携・ストア申請・本番構築

| 週 | ID | タスク概要 | ステータス |
| :--- | :--- | :--- | :--- |
| Week 4 | **W4-1** | `KumogakureAPIClient` ＋ `OfflineFinishQueue` | `⏳ 未着手` |
| Week 4 | **W4-2** | S-02 不在証明作成 ＋ `ShareCardRenderer`（1:1 / 9:16） | `⏳ 未着手` |
| Week 4 | **W4-3** | S-06 雲隠れ帳（7 日制限・Swift Charts）＋ S-08 設定 | `⏳ 未着手` |
| Week 4 | **W4-4** | S-07 Paywall ＋ `.storekit` ローカル課金検証 | `⏳ 未着手` |
| Week 4 | **W4-5** | 同時雲隠れ人数（0 人代替コピー）＋ タスクキル復帰判定 | `⏳ 未着手` |
| Week 4 | **W4-6** | Apple Developer Program ＆ Small Business Program 申請 | `⏳ 未着手` |
| Week 5 | **W5-1** | 独自ドメイン取得 ＋ Cloudflare DNS / Cache / WAF | `⏳ 未着手` |
| Week 5 | **W5-2** | Bundle ID 確定・ASC 課金商品・RevenueCat 本番連携 | `⏳ 未着手` |
| Week 5 | **W5-3** | 法務ドキュメント確定版 HTML 反映（`/legal/privacy`, `/legal/terms`） | `⏳ 未着手` |
| Week 5 | **W5-4** | アプリアイコン ＋ App Store スクリーンショット・ASO 原稿 | `⏳ 未着手` |
| Week 5 | **W5-5** | Build in Public 用デモ動画撮影・告知準備 | `⏳ 未着手` |
| Week 6 | **W6-1** | `prod` 本番環境（Cloud Run / Turso / Scheduler / 予算アラート） | `⏳ 未着手` |
| Week 6 | **W6-2** | TestFlight 配信・[実機 QA チェックリスト](docs/05-release/app-store-checklist.md) 完了 | `⏳ 未着手` |
| Week 6 | **W6-3** | App Store 審査提出 → Ready for Sale | `⏳ 未着手` |
| Week 6 | **W6-4** | リリース公開・アクセス監視 | `⏳ 未着手` |

---

## 4. 直近の検証ログ

- **Cloud Run `dev` ライブ疎通検証 (`2026-11-20`)**: `project-08414a32-51ef-4d05-af6`（`asia-northeast1`）の `https://kumogakure-api-dev-fpdy7efquq-an.a.run.app`（`kumogakure-api-dev-00004-6vr`）に対し、`GET /health` および `GET /health?deep=1` が `{"status":"ok","db":"ok","version":"0.1.0"}` を返却。パラメータ（`1 vCPU`, `512Mi`, `maxScale=3`, `cpu-throttling=true`, `containerConcurrency=40`, `timeoutSeconds=15`）確認済。なお Cloud Run GFE が `*.run.app` 上で `/healthz` を予約遮断するため、コード・正本仕様ともに `/health` へ統一。
- **Turso ライブ接続検証 (`2026-11-20`)**: `turso db create`（`aws-ap-northeast-1`）・[0001_init.sql](services/api/migrations/0001_init.sql) 適用後、`kumogakure-api` を `libsql://kumogakure-dev-misty-swan.aws-ap-northeast-1.turso.io` へ接続して `GET /health?deep=1` が `HTTP 200`（`{"status":"ok","db":"ok","version":"0.1.0"}`）を返すことを確認済。
- **Rust API (`2026-11-20`)**: `services/api` で `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings`, `cargo test` がすべて成功（[week1_foundation.rs](services/api/tests/week1_foundation.rs) 4 件全パス）。
- **素材・フォント検証 (`2026-11-20`)**:
  - 風景画像 4 種: `(1290, 2796)` RGB JPEG・EXIF なし・すべて `<= 600 KiB` 確認済。
  - 環境音 3 種: `60.0s` / `aac-LC` / `44.1kHz` / `2ch` / `<= 1.5 MiB` / `-19.01〜-19.19 LUFS` 確認済。
  - フォント: `ShipporiMincho-Regular.ttf` / `NotoSerifJP-Regular.otf` が `fontdb` で両方解決することをテスト確認済。
- **インフラスクリプト・フォーム検証 (`2026-11-20`)**: `bash -n infra/scripts/*.sh` パス、`create-google-forms.gs` 構文チェックパス、`/edit` URL のリポジトリ非混入を確認済。

---

## 5. 次のアクション

1. **W0-1 最終確認（オーナー操作）**: フォーム ①・② 両方のメール通知 ON と 1 回ずつのテスト送信受信確認（手順: [infra/forms/google-forms-setup.md](infra/forms/google-forms-setup.md)）。
2. **Week 2 着手（`W2-1`〜`W2-6`）**: Rust バックエンドの本実装（ドメインサニタイズ、セッション API、RevenueCat REST 検証、不在証明 HTML `/s/{id}`、動的 OGP 画像 `/ogp/{id}.png`、`/internal/cleanup` ＋ CI/CD）を進め、`kumogakure-api-dev` へ反映する。
3. **Week 3 着手（`W3-1`〜`W3-6`）**: 並行して `apps/ios`（SwiftUI / Xcode プロジェクト・コアタイマー・霧演出・環境音）の実装へ進める。
