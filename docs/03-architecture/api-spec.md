# REST API / Web エンドポイント仕様書

本ドキュメントは Rust（Axum）バックエンドと iOS クライアント／Web 閲覧者の契約（正本）を定義します。

---

## 1. 共通規約

### Base URL
- **本番環境**: `https://kumogakure.app`（第一候補・Week 5 の独自ドメイン取得＆Cloudflare 接続時に確定）
- **開発（`dev`）環境**: Cloud Run デフォルト URL（例: `https://kumogakure-api-dev-xxxxxxxxxx-an.a.run.app`）※開発フェーズは独自ドメインなしで運用
- **ローカル開発**: `http://localhost:8080`

### リクエスト / レスポンス共通ヘッダ
- JSON API リクエスト: `Content-Type: application/json`, `Accept: application/json`
- 時刻フォーマット: 原則すべて **UTC UNIX 秒（`integer` / `i64`）** で送受信し、表示時のみ `timezone`（IANA タイムゾーン名、例: `Asia/Tokyo`）を用いてローカライズする。

### 共通エラーレスポンス形式
すべての `4xx` / `5xx` JSON API レスポンスは以下のフォーマットで返却します（HTML エンドポイント `/s/{id}` および `/legal/*` は HTML を返却）。

```json
{
  "error": {
    "code": "PRO_REQUIRED",
    "message": "この機能を利用するには隠者プラン（Pro）が必要です。",
    "details": {
      "field": "hide_watermark"
    }
  }
}
```

### エラーコード一覧

| HTTP Status | `error.code` | 説明 |
| :--- | :--- | :--- |
| `400` | `INVALID_REQUEST` | JSON パース不可・必須項目欠落 |
| `422` | `VALIDATION_ERROR` | 文字数超過・時間範囲外（15〜720分）・未知の `theme_id` / `card_style` / 不正タイムゾーン |
| `401` | `UNAUTHORIZED` | `owner_token` 未指定または不正（不一致） |
| `403` | `PRO_REQUIRED` | Pro 限定オプション指定時に RevenueCat 上で `hermit_pro` が無効 |
| `403` | `CONTENT_POLICY_VIOLATION` | 表示名または一言メッセージが禁止ワード/URLフィルタに抵触 |
| `404` | `SESSION_NOT_FOUND` | セッションが存在しない、または非公開（`is_public = 0`） |
| `410` | `SESSION_EXPIRED` | `expires_at` 経過済み（主に `/s/{id}` 等） |
| `429` | `RATE_LIMITED` | レート制限超過（Cloudflare WAF またはアプリ側制限） |
| `500` | `INTERNAL_ERROR` | 予期しないサーバー内部エラー |

### レート制限（目安）
- `POST /api/v1/sessions`: 同一 IP あたり **10 req / 分**
- `GET /ogp/{id}.png`: オリジン未キャッシュ時 同一 IP あたり **30 req / 分**
- `GET /api/v1/stats/active`: Cloudflare エッジで 30 秒キャッシュ

---

## 2. エンドポイント詳細

### 2.1 `GET /health`
Cloud Run スタートアップ/ライブネスプローブおよび外部死活監視用（※ Google Cloud Run の Google Front End が `*.run.app` 上で `/healthz` 等の `*z` パスを予約遮断するため `/health` を採用）。

- **クエリパラメータ**: `?deep=1`（省略時はアプリプロセス確認のみ、`deep=1` 時は Turso に `SELECT 1` を実行）
- **レスポンス `200 OK`**:
```json
{
  "status": "ok",
  "db": "ok",
  "version": "0.1.0"
}
```
- **レスポンス `503 Service Unavailable`**（`deep=1` で DB 不通時）:
```json
{
  "status": "degraded",
  "db": "error"
}
```

---

### 2.2 `POST /api/v1/sessions`
新しい雲隠れセッションを作成・開始する。同一 `user_uuid` に既存の `status = 'active'` セッションが存在する場合は、自動的に `status = 'canceled'`, `finished_at = now` へ更新してから新規作成する。

- **Request Body (`application/json`)**:
```json
{
  "user_uuid": "550e8400-e29b-41d4-a716-446655440000",
  "duration_minutes": 120,
  "theme_id": "misty_mountain",
  "card_style": "washi_classic",
  "hide_watermark": false,
  "is_public": true,
  "is_custom_message": false,
  "display_name": "霧崎",
  "message": "読書してきます",
  "timezone": "Asia/Tokyo"
}
```

- **バリデーション規則**:
  - `user_uuid`: 必須、有効な UUID v4 文字列。
  - `duration_minutes`: 必須、整数 `15..=720`（15 分〜12 時間）。
  - `theme_id`: 必須、`"misty_mountain" | "rainy_bamboo" | "moonlit_lake" | "dawn_shrine"`。
    - `moonlit_lake` / `dawn_shrine` は Pro 必須。
  - `card_style`: 任意（デフォルト `"washi_classic"`）、`"washi_classic" | "sumi_night" | "indigo_mist"`。
    - `sumi_night` / `indigo_mist` は Pro 必須。
  - `hide_watermark`: 任意（デフォルト `false`）。`true` は Pro 必須。
  - `is_public`: 必須、`boolean`。`false` の場合は `/s/{id}` および `/ogp/{id}.png` で非公開（404）。
  - `is_custom_message`: 任意（デフォルト `false`）。`true` は Pro 必須。
  - `display_name`: 任意、`null` またはトリム後 1〜20 書記素クラスタ（制御文字禁止・NG ワード検査対象）。
  - `message`: 任意、`null` またはトリム後 1〜40 書記素クラスタ（`is_custom_message: false` の場合はサーバー定義のプリセット文言一覧または空のみ許可、または Pro 検証）。
  - `timezone`: 任意（デフォルト `"Asia/Tokyo"`）、`chrono-tz` で解釈可能な有効 IANA タイムゾーン名。

- **Response `201 Created`**:
```json
{
  "id": "k9x2m7p4q8",
  "owner_token": "8f4e2a1c9b7d034f56a12c8e7b90d31f4a2b6c8d0e1f2a3b4c5d6e7f8a9b0c1d",
  "status": "active",
  "started_at": 1795153200,
  "ends_at": 1795160400,
  "expires_at": 1795239600,
  "share_url": "https://kumogakure.app/s/k9x2m7p4q8",
  "ogp_image_url": "https://kumogakure.app/ogp/k9x2m7p4q8.png"
}
```
  - 注記: `is_public: false` の場合も `id` と `owner_token` は返却するが、`share_url` と `ogp_image_url` は `null` とする。
  - `owner_token` はこのレスポンスでのみ返却する（DB には SHA-256 ハッシュのみ保存）。

---

### 2.3 `POST /api/v1/sessions/{id}/finish`
進行中のセッションを「完了（`completed`）」または「途中終了・離脱（`canceled`）」に更新し、同時雲隠れ人数から除外する。

- **認証ヘッダ（必須）**: `Authorization: Bearer <owner_token>`
- **Path Parameter**: `id`（10 文字 nanoid）
- **Request Body (`application/json`)**:
```json
{
  "outcome": "completed"
}
```
  - `outcome`: `"completed" | "canceled"`

- **冪等性・振る舞い**:
  - `SHA-256(owner_token)` が DB の `owner_token_hash` と一致しない場合は `401 UNAUTHORIZED`。
  - 既に `completed` または `canceled` の場合、トークンが正しければステータスを上書きせず **`200 OK` で現在状態を返却**（クライアントのリトライ・オフライン再送を安全に受容するため）。
- **Response `200 OK`**:
```json
{
  "id": "k9x2m7p4q8",
  "status": "completed",
  "finished_at": 1795160402
}
```

---

### 2.4 `GET /api/v1/stats/active`
現在雲隠れ中のユーザー総数を返す。

- **レスポンスヘッダ**: `Cache-Control: public, max-age=30, s-maxage=30`
- **集計条件**: `WHERE status = 'active' AND ends_at > unixepoch()`
- **Response `200 OK`**:
```json
{
  "active_count": 42,
  "sampled_at": 1795154000
}
```
  - クライアント側で自分が雲隠れ中（かつサーバー登録成功済み）の場合は `max(0, active_count - 1)` を「あなたのほかに ○○ 人」として表示する。

---

### 2.5 `GET /s/{id}`
不在証明 Web ページ（HTML）。人間（LINE / X からのタップ）および OGP クローラーがアクセスする。

- **セキュリティ/SEO ヘッダ（全レスポンス共通）**:
  - `X-Robots-Tag: noindex, nofollow`
  - `Content-Type: text/html; charset=utf-8`
  - `Content-Security-Policy: default-src 'self'; img-src 'self' https:; style-src 'self' 'unsafe-inline'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'`
- **状態別レスポンス**:
  1. レコード不存在 OR `is_public == 0`: **`404 Not Found`**（非公開・不存在用 HTML、`Cache-Control: no-store`）
  2. `expires_at <= now`: **`410 Gone`**（「この不在証明は霧に溶けました」失効画面 HTML、`Cache-Control: public, max-age=3600`）
  3. 有効レコード（`active` / `completed` / `canceled`）: **`200 OK`**（ライブ状態 HTML + OGP メタタグ、`Cache-Control: public, max-age=30, s-maxage=30`）
- **HTML エスケープ**: Askama テンプレートで `display_name` と `message` を完全自動エスケープ。

---

### 2.6 `GET /ogp/{id}.png`
1200 x 630 px の動的 OGP 画像（PNG）を生成・返却する。

- **状態別レスポンス**:
  1. レコード不存在 OR `is_public == 0`: **`404 Not Found`**（`Cache-Control: no-store`）
  2. `expires_at <= now`: **`410 Gone`**（失効済みは画像も返さない）
  3. 有効レコード: **`200 OK`**
     - `Content-Type: image/png`
     - `Cache-Control: public, max-age=86400, s-maxage=86400, immutable`
     - `X-Robots-Tag: noindex, nofollow`
- **描画仕様**: [../02-design/absence-card-spec.md](../02-design/absence-card-spec.md) および [backend-spec.md](backend-spec.md) に準拠。

---

### 2.7 `POST /internal/cleanup`
期限切れレコードの物理削除用内部エンドポイント。Google Cloud Scheduler から 1 日 1 回呼び出す。

- **認証ヘッダ（必須）**: `X-Internal-Secret: <INTERNAL_CLEANUP_SECRET>`（定数時間比較。不一致は `401`）
- **処理内容**: `DELETE FROM sessions WHERE expires_at < (unixepoch() - 86400)`（410 失効案内をさらに 24 時間返せる猶予を残し、発行 48 時間後に完全削除）
- **Response `200 OK`**:
```json
{
  "deleted_count": 128,
  "executed_at": 1795273200
}
```

---

### 2.8 `GET /legal/privacy` & `GET /legal/terms`
App Store 申請・Paywall 内リンク・不在証明ページフッターから参照される静的 HTML ページ。

- **Content-Type**: `text/html; charset=utf-8`
- **Cache-Control**: `public, max-age=3600, s-maxage=3600`
- **内容**: [../05-release/legal-drafts.md](../05-release/legal-drafts.md) をベースに確定版 HTML をバンドル配信する。
