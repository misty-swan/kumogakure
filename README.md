# 雲隠れ（Kumogakure）

> **「罪悪感ゼロで、優雅に世間から姿を消す」デジタルデトックス＆不在証明アプリ**

『雲隠れ（Kumogakure）』は、SNS疲れや通知疲れを感じるユーザーが「今から少し離れます」と周囲にスマートに宣言（不在証明URL・和モダン画像カード発行）した上で、霧が晴れて美しい日本の風景が現れる静かな時間を楽しめる iOS アプリおよび軽量 Web API プロジェクトです。

---

## プロダクトの特徴

1. **不在証明による免罪符とバイラルループ**
   - 開始時に 24 時間で自動失効する不在証明 Web ページ（`/s/{id}`）と動的 OGP 画像（`/ogp/{id}.png`）、および端末内生成の SNS カードを発行。
   - LINE / X / Instagram ストーリー等に 1 タップで共有でき、罪悪感なくデジタルデトックスに入れます。
2. **「霧が晴れる」逆説的なご褒美 UI**
   - 放置時間に応じて画面を覆う濃い霧がゆっくりと晴れ、和モダンな日本の風景（霧の山並み・雨の竹林・月夜の湖畔・夜明けの社）が姿を現します。
   - 画面ロックは許容しつつ他アプリへの離脱のみを 10 秒猶予付きで検知し、離脱すると霧がリセットされます。
3. **静かな連帯感と「雲隠れ帳」**
   - 画面隅に「現在、あなたのほかに ○○ 人が雲隠れしています」を表示し、孤独な我慢を心地よい休息に変えます。
   - 端末内の SwiftData に全セッションを記録し、直近履歴と累計時間を振り返ることができます。
4. **ログイン不要・固定費ほぼゼロの個人開発設計**
   - 端末生成・Keychain 保存の匿名 UUID で起動から 3 秒で開始可能。
   - Rust（Axum）+ Google Cloud Run + Turso + Cloudflare + RevenueCat の無料枠前提構成でスモールスタートします。

---

## 想定モノレポ構成

本リポジトリは現在ドキュメント整備フェーズにあり、実装フェーズで以下のモノレポ構造に展開します。

```text
Kumogakure/
├── README.md                  # 本ファイル（プロジェクト全体案内）
├── AGENTS.md                  # AI 開発エージェント向け不変条件・作業規約
├── apps/
│   └── ios/                   # [予定] SwiftUI (iOS 17.0+) ネイティブアプリ
├── services/
│   └── api/                   # [予定] Rust (Axum) バックエンド + OGP 生成 + 不在証明 HTML
├── infra/                     # [予定] Cloud Run / Cloudflare / Turso / Cloud Scheduler 設定・スクリプト
└── docs/                      # プロダクト企画・要件・UI/UX・アーキテクチャ・運用・リリース計画
    ├── kumogakure.md          # 原案プロダクト企画・仕様書（原文保持）
    ├── README.md              # ドキュメントマップ・正本（Single Source of Truth）一覧
    ├── 01-product/            # PRD・マネタイズ設計・未確定事項（Open Questions）
    ├── 02-design/             # UX/画面設計・デザインシステム・不在証明カード仕様
    ├── 03-architecture/       # システム構成・ADR・API仕様・DB設計・Backend/iOS実装仕様
    ├── 04-infra-ops/          # インフラ構築・CI/CD・監視・障害対応ランブック
    ├── 05-release/            # App Store審査チェックリスト・法務ドラフト
    └── 06-plan/               # 6週間ロードマップ・WBS
```

---

## 技術スタック（MVP）

| レイヤー | 採用技術 | 選定理由（要約） |
| :--- | :--- | :--- |
| **モバイルアプリ** | SwiftUI / Swift 5.10+（iOS 17.0+） | SwiftData・`@Observable`・`ImageRenderer` 活用、Phase 2 の Screen Time API / Live Activities 対応を見据えたネイティブ採用 |
| **課金基盤** | RevenueCat SDK + StoreKit 2 | 匿名 UUID でのレシート検証・Entitlement（`hermit_pro`）管理・Webhook/REST API によるサーバー検証 |
| **バックエンド API** | Rust（Edition 2021 / MSRV 1.82+）・Axum | 高速なコールドスタート、低メモリ、型安全なエラーハンドリング |
| **動的 OGP 生成** | Askama（XML エスケープ SVG）+ `resvg` + `fontdb` | Chromium 等の重いブラウザ依存なしで 1200x630 PNG を高速レンダリング |
| **データベース** | Turso（libSQL / SQLite 互換、`aws-ap-northeast-1`） | Cloud Run のステートレス制約に対応しつつ無料枠が大きく低遅延 |
| **ホスティング** | Google Cloud Run（`asia-northeast1` 東京） | スケールゼロ対応・無料枠内で月額 0 円運用が可能 |
| **CDN / WAF** | Cloudflare（Free プラン） | OGP 画像・アクティブ人数エンドポイントのエッジキャッシュ、クローラー保護、レート制限 |

---

## ドキュメントの読み方

開発・デザイン・レビューの目的に応じて、[docs/README.md](docs/README.md) から対象ドキュメントを参照してください。

- **企画原案を確認したい**: [docs/kumogakure.md](docs/kumogakure.md)
- **要件・スコープ・課金仕様を確認したい**: [docs/01-product/prd.md](docs/01-product/prd.md) / [docs/01-product/monetization.md](docs/01-product/monetization.md)
- **未確定事項・仮決めの一覧を見たい**: [docs/01-product/open-questions.md](docs/01-product/open-questions.md)
- **画面仕様・霧演出・カードデザインを見たい**: [docs/02-design/ux-and-screens.md](docs/02-design/ux-and-screens.md) / [docs/02-design/design-system.md](docs/02-design/design-system.md) / [docs/02-design/absence-card-spec.md](docs/02-design/absence-card-spec.md)
- **API / DB / Rust / SwiftUI の詳細実装を始める**: [docs/03-architecture/api-spec.md](docs/03-architecture/api-spec.md) / [docs/03-architecture/database-design.md](docs/03-architecture/database-design.md) / [docs/03-architecture/backend-spec.md](docs/03-architecture/backend-spec.md) / [docs/03-architecture/ios-app-spec.md](docs/03-architecture/ios-app-spec.md)
- **インフラ構築・監視・App Store 申請を進める**: [docs/04-infra-ops/infrastructure.md](docs/04-infra-ops/infrastructure.md) / [docs/05-release/app-store-checklist.md](docs/05-release/app-store-checklist.md) / [docs/06-plan/roadmap-and-wbs.md](docs/06-plan/roadmap-and-wbs.md)
- **AI エージェントで実装する場合**: 最初に [AGENTS.md](AGENTS.md) を必読のこと。

---

## 開発クイックスタート（実装フェーズ向け予定コマンド）

> 現時点ではドキュメントのみ配置されています。各サブディレクトリ作成後は以下のツールチェーンを想定しています。

- **Rust バックエンド（`services/api` 予定）**
  - 前提: Rust 1.82+ (`cargo`), Turso CLI (`turso`) またはローカル SQLite/libSQL
  - 基本コマンド: `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings`, `cargo test`, `cargo run`
- **iOS アプリ（`apps/ios` 予定）**
  - 前提: Xcode 15.4+ / iOS 17.0+ SDK
  - 基本コマンド: XcodeGen（採用時）または `.xcodeproj` からビルド・`xcodebuild test` 実行
