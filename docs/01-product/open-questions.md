# 確定事項・意思決定一覧（Open Questions 解消済み）

原案企画書（[../kumogakure.md](../kumogakure.md)）から詳細仕様書を作成する過程で判明した論点および未確定事項 **全 17 項目について合意・確定済み（2026-11-20）** です。

- **初期費用ゼロ先行方針**: Apple Developer Program 登録および独自ドメイン取得・Cloudflare 接続は、アプリと API の主要実装に目処が立つ **Week 4〜5** に実施し、Week 1〜4 はシミュレータ＋Xcode ローカル `.storekit` 設定＋Cloud Run デフォルト URL で開発を進めます。

---

## 1. 企画書からの矛盾解消（OQ-01〜07：すべて確定済）

| ID | テーマ | 確定仕様（正本反映済み） | 企画書との差分・決定理由 | 影響ドキュメント | ステータス |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **OQ-01** | **風景・環境音の素材数** | 風景 **4 種**（無料 2 / Pro 2）<br>環境音 **3 種 + 無音**（無料 2 / Pro 1） | 企画書 §3「風景 3 種・環境音 2 種」と §6「無料は基本 2 種のみ・有料は全解放」の矛盾を解消し、Pro の解放価値を明確化。 | [prd.md](prd.md), [monetization.md](monetization.md), [../02-design/design-system.md](../02-design/design-system.md) | `確定済` |
| **OQ-02** | **無料ユーザーの「一言メッセージ」** | 無料はプリセット 5 種から選択（表示名のみ任意入力可）。自由記述（`custom`）は Pro 限定。 | 差別化と無料ユーザーの UGC リスク低減・モデレーション負荷抑制を両立。 | [prd.md](prd.md), [monetization.md](monetization.md), [../03-architecture/api-spec.md](../03-architecture/api-spec.md) | `確定済` |
| **OQ-03** | **画面ロックと離脱検知の仕様** | `protectedDataWillBecomeUnavailable` 発火時は画面ロックとして許容。他アプリ遷移時は 10 秒猶予後にリセット。画面オン維持トグル併用。 | 最長 12 時間「明日の朝まで」の睡眠利用と Forest 型集中体験を iOS 標準 API 内で両立（ADR-002）。 | [../03-architecture/adr/002-timer-and-lock.md](../03-architecture/adr/002-timer-and-lock.md), [../03-architecture/ios-app-spec.md](../03-architecture/ios-app-spec.md) | `確定済` |
| **OQ-04** | **セッション失効時刻（`expires_at`）基準** | `started_at + 86400`（発行から 24 時間） | 企画書の「24 時間で自動失効」に沿い、最長 12 時間セッション後でも最低 12 時間は帰還確認可能としつつサーバー保持期間を短縮。 | [../03-architecture/database-design.md](../03-architecture/database-design.md), [../03-architecture/api-spec.md](../03-architecture/api-spec.md) | `確定済` |
| **OQ-05** | **OGP 画像キャッシュと状態変化** | `/ogp/{id}.png` は `max-age=86400, immutable`（出発宣言カード固定）。ライブ状態（帰還済・失効）は `/s/{id}`（`max-age=30`）で表現。 | SNS クローラーのキャッシュ特性に合わせつつ、リンク先 Web で最新状態を伝える（ADR-003）。 | [../03-architecture/adr/003-auth-and-ogp-cache.md](../03-architecture/adr/003-auth-and-ogp-cache.md), [../02-design/absence-card-spec.md](../02-design/absence-card-spec.md) | `確定済` |
| **OQ-06** | **iOS 最低対応 OS バージョン** | **iOS 17.0+** | SwiftData・`@Observable`・`SensoryFeedback`・`ImageRenderer` を活用し 6 週間での MVP 完成を優先。 | [../03-architecture/adr/001-tech-stack.md](../03-architecture/adr/001-tech-stack.md), [../03-architecture/ios-app-spec.md](../03-architecture/ios-app-spec.md) | `確定済` |
| **OQ-07** | **同時雲隠れ人数が 0 人の表示** | 自分以外の人数が 0 人の時は「0 人」を表示せず、「いま、深い静寂が広がっています」を表示。 | 初期リリース直後の過疎感・孤独感を回避し世界観を維持。 | [../02-design/ux-and-screens.md](../02-design/ux-and-screens.md), [../02-design/design-system.md](../02-design/design-system.md) | `確定済` |

---

## 2. 実装・公開事項の意思決定（OQ-08〜17：すべて確定済）

| ID | テーマ | 確定方針（正本反映済み） | 実施タイミング・備考 | 影響ドキュメント | ステータス |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **OQ-08** | **独自ドメイン取得** | **開発中（`dev`）は Cloud Run デフォルト URL（`*.run.app`）で進め、リリース直前（Week 5）に独自ドメイン（第一候補 `kumogakure.app`）を取得・Cloudflare 接続・差し替え**。 | `BASE_URL` 環境変数と iOS `AppConfig` で即切替可能に設計。 | [../03-architecture/api-spec.md](../03-architecture/api-spec.md), [../04-infra-ops/infrastructure.md](../04-infra-ops/infrastructure.md), [../06-plan/roadmap-and-wbs.md](../06-plan/roadmap-and-wbs.md) | `確定済（Week 5 取得）` |
| **OQ-09** | **Bundle ID / App ID** | **開発中は仮値 `app.kumogakure.ios`（`AppConfig` 1 箇所管理）で進め、App Store Connect 登録時（Week 5）に空き確認して最終確定**。 | Keychain Service 名や Product ID プレフィックスも `AppConfig` 定数参照で統一。 | [monetization.md](monetization.md), [../03-architecture/ios-app-spec.md](../03-architecture/ios-app-spec.md), [../05-release/app-store-checklist.md](../05-release/app-store-checklist.md) | `確定済（Week 5 確定）` |
| **OQ-10** | **OGP 同梱和文フォント** | **Shippori Mincho（メイン）＋ Noto Serif JP（フォールバック）** の 2 フォント構成（いずれも SIL OFL）。 | `services/api/assets/fonts/` に両方同梱し、起動時 `fontdb` へロード。文字化けを防止。 | [../02-design/design-system.md](../02-design/design-system.md), [../02-design/absence-card-spec.md](../02-design/absence-card-spec.md), [../03-architecture/backend-spec.md](../03-architecture/backend-spec.md) | `確定済` |
| **OQ-11** | **風景画像・環境音素材の調達** | **風景 4 種**: 画像生成 AI で統一トーン制作＋レタッチ<br>**環境音 3 種**: CC0・商用利用可フリー音源をループ編集 | 出典・生成履歴・ライセンスメモをリポジトリへ保存し権利クリアランスを担保。 | [../02-design/design-system.md](../02-design/design-system.md), [../06-plan/roadmap-and-wbs.md](../06-plan/roadmap-and-wbs.md) | `確定済` |
| **OQ-12** | **無料トライアルの有無** | **年額プラン（2,400 円）のみ「7 日間無料トライアル」を付与**（月額 300 円は即課金）。 | Paywall では StoreKit `introductoryOffer` を動的取得・表示（3.1.2 遵守）。 | [monetization.md](monetization.md), [../02-design/ux-and-screens.md](../02-design/ux-and-screens.md), [../05-release/app-store-checklist.md](../05-release/app-store-checklist.md) | `確定済` |
| **OQ-13** | **RevenueCat サーバー検証方式** | **都度 REST API 照会 ＋ インメモリ 60 秒キャッシュ ＋ 障害時 Fail-Open**。 | Webhook 不要で最小実装しつつ、外部障害で課金済みユーザーをブロックしない。 | [monetization.md](monetization.md), [../03-architecture/backend-spec.md](../03-architecture/backend-spec.md) | `確定済` |
| **OQ-14** | **Apple Developer / Small Business 登録** | **主要実装の目処が立つ Week 4〜5 まで登録保留**。Week 1〜4 はシミュレータ＋Xcode ローカル `.storekit` 設定ファイルで開発・課金検証。 | Small Business Program（15%）の審査リードタイムを考慮し **Week 4** での登録・申請着手を推奨。 | [../03-architecture/ios-app-spec.md](../03-architecture/ios-app-spec.md), [../05-release/app-store-checklist.md](../05-release/app-store-checklist.md), [../06-plan/roadmap-and-wbs.md](../06-plan/roadmap-and-wbs.md) | `確定済（Week 4〜5 実施）` |
| **OQ-15** | **お問い合わせ・UGC 通報窓口** | **Google フォーム（無料）のみで完結**（個人メールアドレスは非公開）。 | `/s/{id}` の「不適切な内容を報告」リンクでは `session_id` をクエリで自動事前入力。 | [../02-design/absence-card-spec.md](../02-design/absence-card-spec.md), [../04-infra-ops/operations-and-monitoring.md](../04-infra-ops/operations-and-monitoring.md), [../05-release/legal-drafts.md](../05-release/legal-drafts.md) | `確定済` |
| **OQ-16** | **「明日の朝まで」の境界時刻仕様** | **デフォルト 07:00 目標・15〜720 分クランプ（実際の帰還予定時刻を UI 明示）＋ 設定画面（S-08）で朝時刻（05:00〜10:00）を変更可能**。 | `UserDefaults`（`pref_morning_target_minutes` = 420 初期値）に保存。 | [prd.md](prd.md), [../02-design/ux-and-screens.md](../02-design/ux-and-screens.md), [../03-architecture/database-design.md](../03-architecture/database-design.md) | `確定済` |
| **OQ-17** | **最小インスタンス数（コールドスタート）** | **MVP は `min-instances = 0`（完全スケールゼロ）固定**。 | インフラ固定費 0 円を優先し、Rust バイナリによる ~1 秒のコールドスタートは許容。 | [../04-infra-ops/infrastructure.md](../04-infra-ops/infrastructure.md) | `確定済` |
