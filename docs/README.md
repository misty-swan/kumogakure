# 『雲隠れ（Kumogakure）』ドキュメントマップ

本ディレクトリ配下には、デジタルデトックス＆不在証明アプリ『雲隠れ』を MVP 開発から App Store リリース・初期運用まで一貫して推進するための設計ドキュメント一式を格納しています。

---

## 正本（Single Source of Truth）と位置づけ

- [kumogakure.md](kumogakure.md) は**原案企画・仕様書（原文アーカイブ）**であり、歴史的経緯の保持のため編集しません。
- 企画書に含まれていた曖昧な箇所や軽微な矛盾（無料/有料素材数、画面ロック時の挙動、OGP キャッシュと失効時刻、認証方式など）は、**以下のディレクトリ配下の詳細仕様を正本として解消・統一**しています。
- 解消した判断と残課題は [01-product/open-questions.md](01-product/open-questions.md) に一覧化しています。

---

## ドキュメント一覧

### 00. プロジェクト案内・規約
| ファイル | 内容・目的 | 主な読者 | 更新タイミング |
| :--- | :--- | :--- | :--- |
| [../README.md](../README.md) | リポジトリ概要・構成・技術スタック | 全員 | マイルストーン変更時 |
| [../AGENTS.md](../AGENTS.md) | AI 開発エージェント向け不変条件・実装規約 | 開発者・AI エージェント | アーキテクチャ/原則変更時 |
| [kumogakure.md](kumogakure.md) | 企画・仕様書（原文） | 全員 | **更新しない（参照専用）** |

### 01. プロダクト要件・課金・未確定事項 (`01-product/`)
| ファイル | 内容・目的 | 主な読者 | 更新タイミング |
| :--- | :--- | :--- | :--- |
| [01-product/prd.md](01-product/prd.md) | 課題・USP・機能要件（受け入れ基準付）・非機能要件・MVP vs Phase 2 スコープ | PdM・開発・QA | 要件追加・スコープ調整時 |
| [01-product/monetization.md](01-product/monetization.md) | 無料/有料マトリクス・価格・RevenueCat 設計・Paywall トリガー・MRR 試算 | PdM・iOS・Backend | 課金仕様・価格変更時 |
| [01-product/open-questions.md](01-product/open-questions.md) | 企画書からの仮決め理由・未確定事項・決定期限・意思決定ログ | 全員 | 意思決定の都度 |

### 02. デザイン・UX・不在証明仕様 (`02-design/`)
| ファイル | 内容・目的 | 主な読者 | 更新タイミング |
| :--- | :--- | :--- | :--- |
| [02-design/ux-and-screens.md](02-design/ux-and-screens.md) | UX フロー・画面遷移図・全画面（S-01〜S-08, W-01）の状態/エッジケース仕様 | デザイン・iOS・Web | UI/画面変更時 |
| [02-design/design-system.md](02-design/design-system.md) | カラー・タイポ・霧アニメーション仕様・風景/環境音アセット規格・マイクロコピー | デザイン・iOS・素材制作 | トーン＆マナー・素材調整時 |
| [02-design/absence-card-spec.md](02-design/absence-card-spec.md) | 不在証明 HTML メタタグ・1200x630 OGP レイアウト・iOS SNS カード規格 | デザイン・Backend・iOS | OGP/カードレイアウト変更時 |

### 03. システム設計・ADR・詳細仕様 (`03-architecture/`)
| ファイル | 内容・目的 | 主な読者 | 更新タイミング |
| :--- | :--- | :--- | :--- |
| [03-architecture/system-architecture.md](03-architecture/system-architecture.md) | 全体構成図・主要シーケンス図・責務分界・セキュリティ/UGC 脅威モデル | 全エンジニア | 構成変更・脅威追加時 |
| [03-architecture/adr/001-tech-stack.md](03-architecture/adr/001-tech-stack.md) | ADR-001: SwiftUI・Rust/Axum・Cloud Run・Turso・Cloudflare 選定理由 | 全エンジニア | 技術方針見直し時 |
| [03-architecture/adr/002-timer-and-lock.md](03-architecture/adr/002-timer-and-lock.md) | ADR-002: iOS 画面ロック許容・10 秒猶予離脱検知・`Date` ベース計測方針 | iOS・PdM | タイマー制約変更時 |
| [03-architecture/adr/003-auth-and-ogp-cache.md](03-architecture/adr/003-auth-and-ogp-cache.md) | ADR-003: `owner_token` 認証・10 文字 nanoid・OGP キャッシュ分離設計 | Backend・Infra・iOS | 認証/キャッシュ方針変更時 |
| [03-architecture/api-spec.md](03-architecture/api-spec.md) | 全 8 エンドポイントの HTTP/JSON 入出力・バリデーション・エラーコード正本 | Backend・iOS・QA | API 契約変更時 |
| [03-architecture/database-design.md](03-architecture/database-design.md) | Turso DDL/インデックス・SwiftData エンティティ・Keychain・保持ポリシー正本 | Backend・iOS | スキーマ変更時 |
| [03-architecture/backend-spec.md](03-architecture/backend-spec.md) | Rust (Axum) モジュール構成・`resvg` パイプライン・Dockerfile・テスト方針 | Backend | サーバー実装変更時 |
| [03-architecture/ios-app-spec.md](03-architecture/ios-app-spec.md) | SwiftUI (iOS 17+) 構成・状態機械・ライフサイクル監視・音声・テスト方針 | iOS | アプリ実装変更時 |

### 04. インフラ・運用 (`04-infra-ops/`)
| ファイル | 内容・目的 | 主な読者 | 更新タイミング |
| :--- | :--- | :--- | :--- |
| [04-infra-ops/infrastructure.md](04-infra-ops/infrastructure.md) | Cloud Run・Turso・Cloudflare・Cloud Scheduler・Secret Manager・CI/CD | Infra・Backend・iOS | インフラ構成変更時 |
| [04-infra-ops/operations-and-monitoring.md](04-infra-ops/operations-and-monitoring.md) | ログ・アラート・無料枠上限監視・障害ランブック・UGC 削除/キャッシュパージ | 運用・Backend | アラート・手順見直し時 |

### 05. リリース準備・法務 (`05-release/`)
| ファイル | 内容・目的 | 主な読者 | 更新タイミング |
| :--- | :--- | :--- | :--- |
| [05-release/app-store-checklist.md](05-release/app-store-checklist.md) | App Store Connect 設定・審査注意点・ASO 原稿・TestFlight 実機 QA 項目 | PdM・iOS・QA | 審査提出前・バージョン毎 |
| [05-release/legal-drafts.md](05-release/legal-drafts.md) | プライバシーポリシー・利用規約・特商法/EULA ドラフト（`[要記入]` 付き） | PdM・法務確認 | 公開前・仕様変更時 |

### 06. 開発計画 (`06-plan/`)
| ファイル | 内容・目的 | 主な読者 | 更新タイミング |
| :--- | :--- | :--- | :--- |
| [06-plan/roadmap-and-wbs.md](06-plan/roadmap-and-wbs.md) | Week 0〜6 の WBS・クリティカルパス・完了条件（DoD）・Phase 2 判断基準 | 全員 | 週次進捗レビュー時 |

---

## 推奨リーディング順序（新規参画者・AI エージェント向け）

1. **全体像を掴む**: [01-product/prd.md](01-product/prd.md) → [02-design/ux-and-screens.md](02-design/ux-and-screens.md) → [03-architecture/system-architecture.md](03-architecture/system-architecture.md)
2. **Backend を実装する**: [../AGENTS.md](../AGENTS.md) → [03-architecture/api-spec.md](03-architecture/api-spec.md) → [03-architecture/database-design.md](03-architecture/database-design.md) → [03-architecture/backend-spec.md](03-architecture/backend-spec.md) → [02-design/absence-card-spec.md](02-design/absence-card-spec.md)
3. **iOS アプリを実装する**: [../AGENTS.md](../AGENTS.md) → [02-design/ux-and-screens.md](02-design/ux-and-screens.md) → [02-design/design-system.md](02-design/design-system.md) → [03-architecture/ios-app-spec.md](03-architecture/ios-app-spec.md) → [03-architecture/api-spec.md](03-architecture/api-spec.md) → [01-product/monetization.md](01-product/monetization.md)
4. **インフラ構築・リリースする**: [04-infra-ops/infrastructure.md](04-infra-ops/infrastructure.md) → [04-infra-ops/operations-and-monitoring.md](04-infra-ops/operations-and-monitoring.md) → [05-release/legal-drafts.md](05-release/legal-drafts.md) → [05-release/app-store-checklist.md](05-release/app-store-checklist.md)
