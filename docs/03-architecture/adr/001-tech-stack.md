# ADR-001: MVP 技術スタックの選定

- **Status**: Accepted
- **Date**: 2026-11-20
- **Decision Makers**: オーナー / アーキテクト

---

## Context（背景・課題）

『雲隠れ（Kumogakure）』は個人開発プロジェクトであり、6 週間以内での MVP リリースを目標にしている。技術選定にあたっては以下を同時に満たす必要があった。

1. **固定費ほぼゼロ**: 初期ユーザーが少ない段階での月額インフラ維持費を 0 円（Apple Developer 費・ドメイン代を除く）に抑える。
2. **SNS バズ耐性**: 不在証明 URL が X や LINE で拡散された際、クローラーや閲覧アクセス急増でサーバーが落ちない・高額請求にならない。
3. **将来の iOS 深い機能への拡張性**: Phase 2 で Live Activities（WidgetKit）および Screen Time API（`FamilyControls`）を確実に実装できる。
4. **開発の楽しさと保守性**: 1 名＋AI エージェントで完結できる型安全で明快な技術構成。

---

## Decision（決定）

以下のスタックを採用する。

1. **モバイルアプリ**: **SwiftUI（iOS 先行 / iOS 17.0+）**
   - SwiftData、Observable マクロ、`ImageRenderer`、`SensoryFeedback` を標準 API のみで活用し、サードパーティ依存を RevenueCat SDK のみに抑える。
2. **バックエンド API**: **Rust（Axum, Edition 2021 / MSRV 1.82+）** + **Askama + `resvg`**
   - 動的 OGP 画像（1200x630 PNG）をヘッドレスブラウザ（Chromium 等）なしでインプロセス生成する。
3. **ホスティング**: **Google Cloud Run（`asia-northeast1` 東京・スケールゼロ設定）**
4. **データベース**: **Turso（libSQL / SQLite 互換・`aws-ap-northeast-1`）**
5. **CDN / WAF**: **Cloudflare（Free プラン）**
6. **課金**: **RevenueCat（月間売上 $2,500 まで無料）**

---

## Consequences（結果・トレードオフ）

### メリット
- Rust バイナリはコンテナサイズ・起動時間ともに極めて小さく、Cloud Run のスケールゼロ（`min-instances = 0`）からのコールドスタートを 1 秒未満に抑えられる。
- `resvg` による SVG→PNG 変換により 512MiB メモリ構成で高速かつ安定して OGP を生成でき、GCP 無料枠に収まりやすい。
- SwiftUI ネイティブ採用により、霧の表現、バックグラウンド音声、および Phase 2 の Screen Time API / Live Activities でブリッジコストが発生しない。

### デメリット・注意点
- **Android 非対応**: MVP は iOS のみとなる（日本市場のサブスク課金率・ターゲット適合性を優先した意図的トレードオフ）。
- **和文フォント同梱サイズ**: OGP 生成コンテナ内に Shippori Mincho 等の TTF/OTF（5〜8MB）を同梱する必要がある。
- **iOS 17.0+ 限定**: iOS 16 以前は切り捨てることで SwiftData と最新 SwiftUI API をフル活用し、6 週間工期を守る。

---

## Alternatives Considered（検討した代替案）

| 領域 | 代替案 | 不採用理由 |
| :--- | :--- | :--- |
| **モバイル** | Flutter | クロスプラットフォームは魅力だが、Phase 2 の Screen Time API（`FamilyControls` / `DeviceActivity`）や Live Activities では結局 Swift ネイティブコードと MethodChannel 保守が必要になるため。 |
| **Backend** | Cloudflare Workers + `@vercel/og` (Satori/Wasm) | 無料枠が広く魅力的だが、和文フォント（数 MB）のバンドルサイズ制限（Workers Free 1MB〜有料 10MB 制限）とメモリ 128MB 制約が重く、Wasm OGP レンダリングで制限に達しやすい。 |
| **Backend** | Node.js + Playwright / Puppeteer | コンテナが 500MB〜1GB 超となりメモリ・コールドスタート面で Cloud Run 無料枠と相性が悪い。 |
| **DB** | Firestore / Supabase | Turso は SQLite 互換でローカル単体テスト（インメモリ DB）との親和性が高く、読み書き無料枠も十分大きいため。 |
