# バックエンド詳細実装仕様書（Rust / Axum）

本ドキュメントは `services/api` の Rust（Edition 2021 / MSRV 1.82+）実装ガイドラインです。API 入出力は [api-spec.md](api-spec.md)、スキーマは [database-design.md](database-design.md) を正本とします。

---

## 1. ディレクトリ・モジュール構成

```text
services/api/
├── Cargo.toml
├── Dockerfile
├── assets/
│   └── fonts/
│       ├── ShipporiMincho-Regular.ttf    # OGPレンダリング用メインフォント (SIL OFL)
│       └── NotoSerifJP-Regular.otf       # OGP文字欠け補完用フォールバックフォント (SIL OFL, 静的SubsetOTF)
├── migrations/
│   └── 0001_init.sql
├── templates/
│   ├── absence.html                      # GET /s/{id} (有効セッション)
│   ├── gone.html                         # GET /s/{id} (410 失効)
│   ├── not_found.html                    # GET /s/{id} (404)
│   ├── legal_privacy.html                # GET /legal/privacy
│   ├── legal_terms.html                  # GET /legal/terms
│   └── ogp_card.svg                      # OGP PNG元テンプレート (Askama XMLエスケープ)
└── src/
    ├── main.rs                           # 起動・フォントロード・DI・Axumサーバ起動
    ├── config.rs                         # 環境変数パース・バリデーション
    ├── error.rs                          # AppError (thiserror + IntoResponse)
    ├── routes.rs                         # ルーティング・ミドルウェア構築
    ├── domain/
    │   ├── mod.rs
    │   ├── catalog.rs                    # theme_id / card_style / presetメッセージ定義
    │   ├── sanitize.rs                   # 書記素長制限・制御文字除去・NGワード検査
    │   ├── session.rs                    # ドメインモデル・タイムゾーン日時フォーマット
    │   └── token.rs                      # nanoid生成・owner_token生成/SHA-256検証
    ├── handlers/
    │   ├── mod.rs
    │   ├── health.rs                     # GET /health
    │   ├── sessions.rs                   # POST /api/v1/sessions, /finish
    │   ├── stats.rs                      # GET /api/v1/stats/active
    │   ├── public_page.rs                # GET /s/{id}, GET /legal/*
    │   ├── ogp.rs                        # GET /ogp/{id}.png
    │   └── internal.rs                   # POST /internal/cleanup
    ├── infra/
    │   ├── mod.rs
    │   ├── db.rs                         # libsql リポジトリ実装
    │   └── revenuecat.rs                 # RevenueCat REST APIクライアント + 60秒キャッシュ
    ├── ogp/
    │   ├── mod.rs
    │   └── renderer.rs                   # Askama SVG -> usvg/resvg PNG変換 (spawn_blocking)
    └── middleware/
        ├── mod.rs
        └── security_headers.rs           # X-Robots-Tag / CSP / X-Content-Type-Options
```

---

## 2. 採用クレートと選定方針

依存を軽量に保ち、ビルド時間と Docker イメージサイズを最小化します。

| クレート | 用途 | 採用上の注意 |
| :--- | :--- | :--- |
| `axum` (0.7+) | HTTP ルーティング・Extractor | `tower-http`（Trace, Timeout, Compression, CatchPanic）と併用 |
| `tokio` | 非同期ランタイム | `rt-multi-thread`, `macros`, `signal`, `sync` を有効化 |
| `libsql` | Turso / ローカル SQLite 接続 | リモート（`libsql://` + token）とテスト用ローカルインメモリ両対応 |
| `resvg`, `usvg`, `fontdb` | SVG → PNG（1200x630）レンダリング | 同一メジャー系列（例: `resvg 0.43+` 系）で統一し型不整合を防ぐ |
| `askama` | HTML / SVG テンプレートエンジン | `.html` と `.svg` の自動エスケープ（HTML/XML）が効くこと |
| `serde`, `serde_json` | JSON シリアライズ | `#[serde(deny_unknown_fields)]` は将来互換のため原則使わず厳密検証を自前実装 |
| `nanoid` | セッション ID 生成 | URL 安全文字セット `[A-Za-z0-9_-]`、長さ 10 |
| `chrono`, `chrono-tz` | UTC UNIX 秒変換・タイムゾーン表示 | `Asia/Tokyo` 等の有効性検証および `HH:mm` フォーマット |
| `sha2`, `hex`, `rand`, `subtle` | `owner_token` 生成・SHA-256 ハッシュ・定数時間比較 | `subtle::ConstantTimeEq` でタイミング攻撃を防止 |
| `reqwest` | RevenueCat REST API 呼び出し | `rustls-tls` を指定し OpenSSL 依存を排除（Docker イメージ軽量化） |
| `unicode-segmentation` | 書記素クラスタ単位のテキスト制御 | 日本語・絵文字の安全なカウントと折り返し |
| `tracing`, `tracing-subscriber` | 構造化 JSON ログ | Cloud Logging 対応の JSON フォーマッタを使用 |
| `thiserror` | ドメイン・ハンドラエラー型 | 1 箇所で HTTP ステータスとエラー JSON へ変換 |

---

## 3. OGP 画像生成パイプライン設計

### 3.1 起動時フォントプリロード
Cloud Run のリクエスト毎のファイル I/O とパース遅延を排除するため、`main.rs` の起動時にフォント DB を 1 回だけ構築し、`AppState` に `Arc<fontdb::Database>` として保持します。

1. コンテナ内の `assets/fonts/ShipporiMincho-Regular.ttf` および `assets/fonts/NotoSerifJP-Regular.otf`（`resvg` が静的ウェイトを安定描画でき、ファイルサイズも軽量な `noto-cjk` SubsetOTF Regular を採用）を `fontdb::Database` へロード。
2. `db.set_serif_family("Shippori Mincho")` を設定し、SVG の `font-family` に `"Shippori Mincho, Noto Serif JP, serif"` を指定する（Shippori Mincho で未収録の文字のみ Noto Serif JP へ自動フォールバック）。
3. 起動完了までに 150〜250ms 程度で完了する（コールドスタート最小化）。

### 3.2 `spawn_blocking` と並列数制限（OOM 防止）
`resvg` のラスタライズは同期 CPU バウンド処理であり、1 枚あたり作業用バッファを含め約 `1200 * 630 * 4 bytes ≒ 3MB` + α のメモリを消費します。

- Tokio の非同期ワーカースレッドをブロックしないよう、必ず **`tokio::task::spawn_blocking`** 内で実行する。
- Cloud Run（512MiB RAM）環境で同時多発のキャッシュミスが起きても OOM にならないよう、`AppState` に **`Arc<tokio::sync::Semaphore>`（例: `permits = 4`）** を持ち、同時 PNG レンダリング数を最大 4 並列に制限する。

### 3.3 SVG テンプレートの XML エスケープと折り返し
- `ogp_card.svg` は Askama テンプレートとしてコンパイル時に型検証し、埋め込む文字列はすべて自動的に XML エスケープ（`<`, `>`, `&`, `"`, `'`）する。
- 一言メッセージ（最大 40 文字）の折り返しは `unicode-segmentation` で書記素単位に分割し、全角換算幅（ASCII=1, 非 ASCII=2）を計算して **1 行あたり全角約 18〜20 文字** で `line1`, `line2` の 2 本の `<text>` 要素に分割してテンプレートへ渡す（SVG 1.1 に自動折り返しがないため、ドメイン層で確実に折り返す）。

---

## 4. テキストサニタイズ & NG ワード検査

`display_name` および `message` に対して以下の順序で処理を行います。

1. **Unicode 正規化・トリム**: 前後の空白除去。空文字になった場合は `None` として扱う。
2. **制御文字の除去/拒否**: `\0`, `\r`, `\n` 以外の制御文字（bidi 制御文字 U+202E 等含む）を含む場合は `422 VALIDATION_ERROR`。改行は空白 1 文字へ正規化。
3. **長さ検査（書記素クラスタ）**:
   - `display_name`: 最大 `20` 書記素
   - `message`: 最大 `40` 書記素
4. **URL / スパム簡易ブロック**: `http://`, `https://` を含む文言はスパム防止のため `403 CONTENT_POLICY_VIOLATION` で拒否。
5. **NG ワード辞書検査**: 環境変数または同梱辞書（差別語・誹謗中傷・公序良俗違反語句リスト）に対して部分一致チェックを行い、抵触時は `403 CONTENT_POLICY_VIOLATION` を返す。

---

## 5. 環境変数一覧

| 変数名 | 必須 | 例 / デフォルト | 説明 |
| :--- | :--- | :--- | :--- |
| `PORT` | 任意 | `8080` | Cloud Run から注入される待受ポート |
| `APP_ENV` | 必須 | `prod` / `dev` / `local` | 動作環境 |
| `BASE_URL` | 必須 | `https://kumogakure.app` | `share_url` / `og:url` 生成用ベース URL |
| `TURSO_DATABASE_URL` | 必須 | `libsql://kumogakure-prod.turso.io` | Turso 接続 URL（ローカルは `file:./local.db` 可） |
| `TURSO_AUTH_TOKEN` | 本番必須 | `eyJ...` | Turso 認証トークン（Secret Manager 管理） |
| `REVENUECAT_SECRET_API_KEY` | 本番必須 | `sk_...` | RevenueCat REST API v1 検証用シークレットキー |
| `REVENUECAT_FAIL_OPEN` | 任意 | `true` | RC 障害時にユーザーをブロックしない設定（本番推奨 `true`） |
| `INTERNAL_CLEANUP_SECRET` | 本番必須 | ランダム 64 文字 | `POST /internal/cleanup` 認証用シークレット |
| `REPORT_FORM_URL_TEMPLATE` | 任意 | `https://docs.google.com/forms/d/e/.../viewform?entry.123={session_id}` | `/s/{id}` ページ下部の UGC 通報 Google フォーム URL テンプレート |
| `RUST_LOG` | 任意 | `info,kumogakure_api=debug` | ログレベル |

---

## 6. Dockerfile 方針（マルチステージ・非 root）

```dockerfile
# Stage 1: Builder (cargo-chef + rust:1.82-bookworm)
# - 依存クレートをキャッシュしつつ --release ビルド

# Stage 2: Runtime (gcr.io/distroless/cc-debian12 または debian:bookworm-slim)
# - ca-certificates (TLS通信用) のみ同梱
# - /app/kumogakure-api バイナリと /app/assets/fonts/ を配置
# - 非特権ユーザー (uid 10001) で実行
```

- **期待イメージサイズ**: `debian:bookworm-slim` または `distroless/cc` ベースで **約 40〜65 MB**（2 フォント同梱込み）。

---

## 7. テスト戦略

1. **ユニットテスト（`cargo test`）**:
   - `domain::sanitize`: 絵文字・結合文字（例: 👨‍👩‍👧）を含む書記素カウント、XSS ペイロード `<script>alert(1)</script>`、URL ブロック、NG ワード判定。
   - `domain::token`: `owner_token` ハッシュ検証の正常・不一致ケース。
   - `domain::session`: `Asia/Tokyo` / `America/New_York` 変換、24 時間 TTL 境界、状態判定。
2. **統合テスト（ローカル SQLite インメモリ DB 使用）**:
   - `libsql::Builder::new_local(":memory:")` とマイグレーション SQL を適用した `axum::Router` に対し、`tower::ServiceExt::oneshot` で全 8 エンドポイントを網羅テスト。
   - `is_public = false` のときに `/s/{id}` と `/ogp/{id}.png` が `404` になること。
   - 同一 `user_uuid` で連続作成時に古い `active` が `canceled` になること。
   - `/finish` のトークン検証・冪等性（2 回連続で `200`）。
   - `GET /ogp/{id}.png` が有効な PNG マジックバイト（`\x89PNG\r\n\x1a\n`）かつ 1200x630 で返ること。
   - SVG スナップショットに `<script>` 等の生タグが出力されないこと（XML エスケープ検証）。
