# AGENTS.md — AI 開発エージェント向け開発規約

本ファイルは『雲隠れ（Kumogakure）』リポジトリで作業するすべての AI コーディングエージェントおよびコントリビュータが遵守すべき設計原則・正本（Single Source of Truth）ルール・不変条件を定めます。

---

## 1. ドキュメント参照ルール（Single Source of Truth）

実装や仕様変更を行う際は、企画原案（[docs/kumogakure.md](docs/kumogakure.md)）ではなく、以下の**正本ドキュメント**を参照し、齟齬がある場合はコードと正本を同時に更新してください。なお、[docs/kumogakure.md](docs/kumogakure.md) 自体は企画アーカイブとして**編集禁止**です。

| 変更・確認したい対象 | 正本ドキュメント |
| :--- | :--- |
| プロダクト要件・MVP/Phase 2 境界 | [docs/01-product/prd.md](docs/01-product/prd.md) |
| 料金プラン・Entitlement・Product ID | [docs/01-product/monetization.md](docs/01-product/monetization.md) |
| 仮決め事項・未確定事項のステータス | [docs/01-product/open-questions.md](docs/01-product/open-questions.md) |
| 画面遷移・各画面の振る舞い・マイクロコピー | [docs/02-design/ux-and-screens.md](docs/02-design/ux-and-screens.md) |
| カラー・タイポ・霧アニメーション・素材規格 | [docs/02-design/design-system.md](docs/02-design/design-system.md) |
| 不在証明 Web・OGP 画像・SNS カードレイアウト | [docs/02-design/absence-card-spec.md](docs/02-design/absence-card-spec.md) |
| 全体構成・脅威モデル・技術選定理由（ADR） | [docs/03-architecture/system-architecture.md](docs/03-architecture/system-architecture.md) / `docs/03-architecture/adr/` |
| API エンドポイント・JSON スキーマ・エラーコード | [docs/03-architecture/api-spec.md](docs/03-architecture/api-spec.md) |
| Turso DDL・SwiftData モデル・Keychain 項目 | [docs/03-architecture/database-design.md](docs/03-architecture/database-design.md) |
| Rust バックエンド実装・クレート・SVG/resvg | [docs/03-architecture/backend-spec.md](docs/03-architecture/backend-spec.md) |
| SwiftUI アプリ実装・状態遷移・離脱検知 | [docs/03-architecture/ios-app-spec.md](docs/03-architecture/ios-app-spec.md) |
| Cloud Run・Turso・Cloudflare・CI/CD | [docs/04-infra-ops/infrastructure.md](docs/04-infra-ops/infrastructure.md) |
| ログ・アラート・障害時ランブック | [docs/04-infra-ops/operations-and-monitoring.md](docs/04-infra-ops/operations-and-monitoring.md) |
| App Store 審査・ASO・法務ドラフト | [docs/05-release/app-store-checklist.md](docs/05-release/app-store-checklist.md) / [docs/05-release/legal-drafts.md](docs/05-release/legal-drafts.md) |

---

## 2. 絶対に守るべき技術的・プロダクト的不変条件（Invariants）

1. **ログイン不要・匿名 UUID 原則**
   - メールアドレス・パスワード・SNS ログイン等の個人認証を MVP で追加しない。
   - 端末初回起動時に UUID v4 を生成して Keychain（`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`）に保存し、API および RevenueCat の `appUserID` として共通利用する。
2. **セッション所有権の検証（`owner_token`）**
   - `POST /api/v1/sessions` 発行時に生成したランダム `owner_token` はレスポンスで 1 回のみ返却し、DB には SHA-256 ハッシュ（`owner_token_hash`）のみを保存する。
   - `POST /api/v1/sessions/{id}/finish` は `Authorization: Bearer <owner_token>` の定数時間比較検証を必須とし、`user_uuid` だけで他人のセッションを終了させない。
3. **非公開セッションの保護（`is_public`）**
   - ユーザーが不在証明をシェアせずに開始した場合（`is_public = false`）、同時人数集計のみに使用し、`/s/{id}` および `/ogp/{id}.png` へのアクセスは必ず `404` を返す。
4. **Pro 機能のサーバー検証と不変な識別子**
   - Entitlement ID は `hermit_pro`、Offering ID は `default`、Product ID は `app.kumogakure.pro.monthly` / `app.kumogakure.pro.yearly` とする。
   - `hide_watermark: true` や Pro 限定 `theme_id` / `card_style` / カスタム文言をサーバー送信する場合、バックエンドで必ず RevenueCat REST API により `hermit_pro` の有効性を検証する（クライアント自己申告を信用しない）。
5. **XSS / SVG インジェクション / 検索インデックス防止**
   - ユーザー入力（`display_name`, `message`）は文字数制限（書記素クラスタ単位で 20 文字 / 40 文字）と制御文字除去・NG ワード判定を行い、HTML・SVG レンダリング時は Askama 等の自動エスケープを絶対に無効化しない。
   - 不在証明ページ `/s/{id}` には必ず `<meta name="robots" content="noindex, nofollow">` および `X-Robots-Tag: noindex, nofollow` を付与する。
6. **iOS タイマーの画面ロック許容・オフライン耐性**
   - タイマー残り時間は減算カウンタではなく `plannedEndsAt: Date` との差分で計算する。
   - 画面ロック（`protectedDataWillBecomeUnavailableNotification` 発火）ではリセットしない。他アプリ遷移時は 10 秒の猶予期間を設け、復帰しなければ `interrupted` とする。
   - シェアシート（`UIActivityViewController`）表示中は離脱検知を有効化しない。
   - ネットワーク不通時でもローカルタイマー・霧演出・環境音・SNS 画像カード生成（`ImageRenderer`）は必ず完走できること。
7. **固定費ゼロ前提のキャッシュ・負荷設計**
   - `GET /ogp/{id}.png` は `resvg` + 起動時ロード済みフォント（`Arc<fontdb::Database>`）を `tokio::task::spawn_blocking` で生成し、`Cache-Control: public, max-age=86400, s-maxage=86400, immutable` を返して Cloudflare でキャッシュする。
   - Cloud Run のメモリ制限（512MiB）と最大インスタンス数上限を前提とし、ヘッドレスブラウザ等の重量依存を持ち込まない。
8. **責めない UX トーン**
   - 途中帰還や離脱リセット時もユーザーに罪悪感を与えない静謐な表現（例：「霧の中へ戻りました」「また一息つきたくなったらお越しください」）を維持する。
   - 同時雲隠れ人数（自分以外）が 0 人のときに「0 人」と表示せず、「静寂が広がっています」等の肯定的な文言に切り替える。

---

## 3. 技術スタック・ディレクトリ規約

- **モノレポ構成**:
  - `apps/ios`: SwiftUI（iOS 17.0+、Swift 5.10+、SwiftData、`@Observable`、Swift Concurrency）。サードパーティ依存は原則 RevenueCat SDK のみに抑える。
  - `services/api`: Rust（Edition 2021 / MSRV 1.82+、Axum 0.7+、Tokio、`libsql`、`resvg` / `usvg` / `fontdb`、Askama）。
  - `infra`: Terraform / gcloud CLI スクリプト / Cloud Run 設定 / Cloudflare 設定手順 / SQL マイグレーション管理。
- **識別子・カタログ値の統一**:
  - `theme_id`: `misty_mountain` | `rainy_bamboo` | `moonlit_lake` | `dawn_shrine`
  - `sound_id`: `none` | `rain` | `night_wind` | `bonfire`
  - `card_style`: `washi_classic` | `sumi_night` | `indigo_mist`
  - DB / API の時刻はすべて **UTC UNIX 秒（INTEGER）** で保持し、表示時のみ `timezone`（IANA 文字列、デフォルト `Asia/Tokyo`）に変換する。

---

## 4. 実装時のテスト・検証・PR 規約

- **API / DB 変更時**:
  - [docs/03-architecture/api-spec.md](docs/03-architecture/api-spec.md) および [docs/03-architecture/database-design.md](docs/03-architecture/database-design.md) を先に更新し、iOS クライアントと Rust サーバーの契約を一致させる。
  - Rust コードでは `cargo fmt --check`、`cargo clippy --all-targets -- -D warnings`、`cargo test`（インメモリ SQLite 統合テスト・OGP PNG 生成検証を含む）をすべてパスさせる。
- **iOS 変更時**:
  - 状態機械（`DetoxTimerEngine` / `DetoxSessionStore`）および離脱判定ロジックは Protocol 経由で時間・ライフサイクルをモック可能に設計し、XCTest ユニットテストを必ず追加する。
  - 画面ロック・着信・シェアシート・機内モード・VoiceOver の確認項目は [docs/05-release/app-store-checklist.md](docs/05-release/app-store-checklist.md) に従う。
- **ドキュメント変更時**:
  - 相対リンク切れ、サポート外 Mermaid 構文（`gantt` 等は使用禁止）、正本識別子（Entitlement ID やテーブル列名など）の表記揺れがないことを確認する。
