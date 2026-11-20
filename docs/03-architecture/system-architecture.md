# システムアーキテクチャ設計書

## 1. 全体構成図（単一オリジン・最小構成）

個人開発における **固定費ほぼ 0 円・高速コールドスタート・SNS バズ耐性** を実現するため、Cloudflare Proxy の背後に単一の Cloud Run サービス（Rust / Axum）を配置する単一オリジン構成を採用します。

```mermaid
flowchart TD
    UserApp["iOSアプリ (SwiftUI / iOS 17+)"]
    Viewer["閲覧者・SNSクローラー (X / LINE / Safari)"]
    AppStore["Apple StoreKit 2"]
    RC["RevenueCat (API / SDK)"]
    CF["Cloudflare Free (DNS / Proxy / Cache / WAF)"]
    CR["Google Cloud Run (Rust / Axum, asia-northeast1)"]
    Turso["Turso (libSQL / SQLite, aws-ap-northeast-1)"]
    Scheduler["Cloud Scheduler (1日1回 Cleanup)"]

    UserApp -->|"課金購入・復元"| AppStore
    UserApp -->|"Entitlement確認"| RC
    UserApp -->|"API通信 HTTPS"| CF
    Viewer -->|"不在証明HTML / OGP画像"| CF
    CF -->|"キャッシュミス時オリジン転送"| CR
    CR -->|"セッション読み書き・集計"| Turso
    CR -->|"Pro資格サーバー検証"| RC
    Scheduler -->|"POST /internal/cleanup"| CR
```

---

## 2. 主要シーケンス図

### 2.1 不在証明付き開始〜SNS シェア〜クローラー OGP 取得

```mermaid
sequenceDiagram
    actor User as "ユーザー"
    participant App as "iOSアプリ"
    participant CF as "Cloudflare"
    participant API as "Rust API (Cloud Run)"
    participant DB as "Turso"
    participant Crawler as "SNSクローラー"

    User->>App: "不在証明を作って雲隠れ"をタップ
    App->>App: Keychainからuser_uuid取得
    App->>CF: POST /api/v1/sessions (is_public: true)
    CF->>API: オリジン転送
    API->>DB: 既存activeをcanceled化し新規INSERT
    DB-->>API: 成功
    API-->>CF: 201 Created (id, owner_token, share_url, ogp_image_url)
    CF-->>App: レスポンス返却
    App->>App: owner_tokenをメモリ/SwiftDataへ保存
    App->>User: OS標準シェアシート表示 (離脱検知は一時停止)
    User->>App: シェア完了・シートを閉じる
    App->>App: S-03へ遷移しタイマーと離脱検知を開始
    Crawler->>CF: GET /s/{id}
    CF->>API: キャッシュミス時転送
    API->>DB: SELECT * FROM sessions WHERE id = ?
    DB-->>API: セッション返却
    API-->>CF: HTML (og:image=/ogp/{id}.png, max-age=30)
    CF-->>Crawler: HTML返却
    Crawler->>CF: GET /ogp/{id}.png
    CF->>API: キャッシュミス時転送
    API->>DB: SELECT セッション
    API->>API: Askama SVG生成 + resvgでPNG化 (spawn_blocking)
    API-->>CF: PNG (max-age=86400, immutable)
    CF-->>Crawler: PNG返却 (2回目以降はエッジキャッシュ応答)
```

### 2.2 完了・途中終了・オフライン時再送フロー

```mermaid
sequenceDiagram
    participant App as "iOSアプリ"
    participant Store as "SwiftData (ローカル)"
    participant API as "Rust API"
    participant DB as "Turso"

    App->>Store: セッション状態をcompleted/interruptedに更新
    alt オンラインかつAPI通信成功
        App->>API: POST /api/v1/sessions/{id}/finish (Bearer owner_token)
        API->>API: SHA-256(owner_token) == owner_token_hash 検証
        API->>DB: status=completed/canceled, finished_at=now にUPDATE
        DB-->>API: 成功
        API-->>App: 200 OK
        App->>Store: needsRemoteFinishSync = false
    else オフラインまたはタイムアウト
        App->>Store: needsRemoteFinishSync = true を保持
        Note over App,Store: ユーザー体験はブロックせず完了画面を表示
        App->>API: 次回起動・フォアグラウンド復帰時に再送
        API-->>App: 200 OK (冪等)
        App->>Store: needsRemoteFinishSync = false
    end
```

### 2.3 Pro 資格のサーバー検証フロー

```mermaid
sequenceDiagram
    participant App as "iOSアプリ"
    participant API as "Rust API"
    participant RC as "RevenueCat REST API"

    App->>API: POST /api/v1/sessions (hide_watermark: true 等)
    API->>API: Pro専用オプションの有無を判定
    alt Proオプションが含まれる
        API->>API: インメモリ60秒キャッシュ確認
        opt キャッシュミス
            API->>RC: GET /v1/subscribers/{user_uuid} (Timeout 2s)
            RC-->>API: Entitlement hermit_pro の expires_date
        end
        alt hermit_pro が有効
            API-->>App: 201 Created
        else 未加入または期限切れ
            API-->>App: 403 Forbidden (PRO_REQUIRED)
        end
    else 無料オプションのみ
        API-->>App: 201 Created (外部API呼び出しなし)
    end
```

---

## 3. モノレポ構成案と責務分界

```text
Kumogakure/
├── README.md
├── AGENTS.md
├── docs/                      # 設計ドキュメント一式 (本ディレクトリ)
├── apps/
│   └── ios/                   # SwiftUI iOS アプリ (iOS 17.0+)
│       ├── Kumogakure.xcodeproj
│       ├── Kumogakure/        # アプリソースコード
│       └── KumogakureTests/   # XCTest ユニット・状態機械テスト
├── services/
│   └── api/                   # Rust (Axum) 単一バイナリ
│       ├── Cargo.toml
│       ├── Dockerfile
│       ├── assets/fonts/      # Shippori Mincho 等 OGP 用フォント
│       ├── templates/         # Askama HTML & SVG テンプレート
│       ├── migrations/        # Turso / SQLite SQL マイグレーション
│       └── src/
└── infra/
    ├── cloudflare/            # キャッシュ・WAF ルール定義メモ / IaC
    ├── gcp/                   # Cloud Run / Scheduler / Secret Manager 構築スクリプト
    └── github/                # CI/CD ワークフローテンプレート
```

### コンポーネント責務分界

| コンポーネント | 担う責務 | 担わない責務（割り切り） |
| :--- | :--- | :--- |
| **iOS アプリ** | タイマー精密計測、霧アニメーション、環境音再生、離脱検知、ローカル履歴保存（SwiftData）、SNS カード描画、RevenueCat 購入 | OGP 画像の Web 配信、他ユーザーの同時人数集計、Web ページホスティング |
| **Rust API** | セッション ID 発行、不在証明 HTML、動的 OGP PNG 生成、同時人数集計、Pro サーバー検証、法務静的 HTML、期限切れ掃除 | ユーザーアカウント・パスワード管理、履歴の恒久バックアップ、通知送信（APNs） |
| **Turso** | 24 時間以内のアクティブ/公開セッション永続化 | 長期分析データウェアハウス、画像バイナリ保存 |
| **Cloudflare** | SSL 終端、OGP/集計キャッシュ、IP ベースレート制限・Bot 保護 | 動的 HTML の生成、認証チェック |
| **RevenueCat** | App Store レシート検証、購読状態管理、REST 照会 | アプリ機能フラグの UI 制御 |

---

## 4. セキュリティ & UGC 脅威モデル

| 脅威カテゴリ | 攻撃シナリオ・リスク | 採用した対策（正本仕様） |
| :--- | :--- | :--- |
| **ID 推測・総当たり** | `/s/{id}` や `/ogp/{id}.png` を連番スキャンして他人の発言を盗み見る | 10 文字 URL 安全 nanoid（約 60bit エントロピー）を採用し推測困難化。さらに `is_public = 0` のセッションは `/s/{id}` と `/ogp/{id}.png` で必ず `404` を返す。 |
| **セッション乗っ取り** | 他人の `id` や漏洩した `user_uuid` を使って勝手に `/finish` で終了させる | 発行時に 32byte ランダム `owner_token` を生成し SHA-256 ハッシュのみ DB 保存。`/finish` 時は `Bearer owner_token` の定数時間比較を必須化。 |
| **XSS / SVG インジェクション** | `display_name` や `message` に `<script>` や `<svg onload=...>`・不正 XML 属性を混入 | ①書記素単位で文字数制限（20/40文字）②制御文字除去 ③Askama の HTML/XML 自動エスケープ強制 ④厳格な CSP ヘッダ付与。 |
| **不適切投稿・スパム（UGC）** | 差別表現・卑猥語・スパム URL を含む不在証明 URL を生成して拡散 | ①サーバー側 NG ワード＆URL スキーム簡易フィルタ ②無料プランはプリセット文言のみに制限 ③`/s/{id}` に `noindex, nofollow` 付与 ④Web ページ下部に通報導線を設置し、管理者手順で即時削除＆CF キャッシュパージ可能にする。 |
| **OGP 生成による DoS / 課金爆発** | 存在しない ID や大量の並列 `/ogp/{id}.png` リクエストで Cloud Run メモリ枯渇・課金増加 | ①DB に存在する公開セッションのみ描画（不存在は即 `404`）②Cloudflare エッジキャッシュ（`max-age=86400, immutable`）③Cloudflare WAF レート制限 ④Cloud Run `max-instances=3` 上限設定 ⑤`spawn_blocking` 並列上限セマフォ。 |
| **Pro 機能クライアント偽装** | リバースエンジニアリングで `hide_watermark: true` を直接 POST する | サーバー側で `hermit_pro` Entitlement を RevenueCat REST API で検証し、未課金なら `403 PRO_REQUIRED` を返す。 |
| **個人情報の漏洩・検索露出** | ユーザーの休息履歴や匿名 UUID が外部検索エンジンや DB に残存する | DB にメールアドレス・端末名等を一切保存せず、`expires_at`（24 時間）経過後は `410 Gone` としたうえで日次ジョブで物理削除する。 |
