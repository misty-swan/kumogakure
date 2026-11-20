# 運用・監視・障害対応ランブック

## 1. ログ・監視・アラート設計

### 1.1 構造化ログ（Cloud Logging）
Rust バックエンドは標準出力へ JSON 形式でログを出力し、Cloud Run が自動的に Cloud Logging へ収集します。

- **必須ログフィールド**: `timestamp`, `level`, `target`, `request_id`, `method`, `path`, `status`, `latency_ms`, `message`
- **個人情報・秘密値の非記録原則**:
  - `owner_token`, `Authorization` ヘッダ, `TURSO_AUTH_TOKEN`, `REVENUECAT_SECRET_API_KEY` はログに絶対に出力しない。
  - `display_name` や `message` 本文も原則 INFO ログには出さず、モデレーションや異常系調査時のみ `session_id` を記録する。

### 1.2 外形監視（Uptime Check）とアラート

| 監視対象 | チェック間隔 / 条件 | 通知先 | 閾値・狙い |
| :--- | :--- | :--- | :--- |
| **Uptime Check** | 5 分間隔（`GET /health?deep=1`） | メール / Discord / Slack Webhook | 連続 2 回失敗（HTTP != 200）でアラート |
| **5xx エラー率** | 5 分間ウィンドウ | 同上 | 5xx が 5% 超 または 10 件超で通知 |
| **Cloud Run 予算アラート** | 日次集計 | GCP Billing メール | 月額 **100 円 / 500 円 / 1,000 円** の 3 段階予算通知 |
| **Cloudflare トラフィック** | ダッシュボード確認（週次） | オーナー確認 | Cache Hit Ratio（`/ogp/*` が 90% 以上あるか） |

---

## 2. 無料枠クォータ保護（課金爆発防止）

1. **Cloud Run `max-instances = 3`**: 万一 DDoS や極端なバズが起きても、それ以上コンテナが増えず無料枠からの急激な超過を物理的に防ぐ。
2. **Cloudflare キャッシュ優先**: `/ogp/{id}.png` と `/api/v1/stats/active` は Cloudflare エッジから返るため、Cloud Run コンテナ起動回数自体を抑制する。
3. **Turso 利用量監視**: `turso db show` で月間の Row Reads / Row Writes を週 1 回確認。Cleanup 漏れでレコードが増え続けないよう `/internal/cleanup` の実行ログを確認する。

---

## 3. 障害対応ランブック（Runbooks）

### Runbook 1: SNS バズによる急激なアクセス増加
- **兆候**: Cloudflare リクエスト数急増、Cloud Run インスタンス数が上限 `3` に到達、`429` または `503` 発生。
- **確認**: Cloudflare Analytics でどのパスに集中しているか確認（通常は `/s/{id}` と `/ogp/{id}.png`）。
- **初動対応**:
  1. `/s/{id}` の `Cache-Control` 負荷が重い場合、Cloudflare Cache Rule で一時的に `/s/*` の Edge TTL を `30秒 → 5分` に引き上げ（Dashboard から即時変更可能）。
  2. iOS アプリ側には影響が出ないか確認（そもそも開始時・終了時の API がタイムアウトしてもアプリはローカル継続するため、ユーザー体験は壊れない）。
  3. 有料会員増加見込みが立っている場合のみ、`max-instances` を `3 → 10` へ一時緩和。

### Runbook 2: Turso 障害またはネットワーク不通
- **兆候**: `/health?deep=1` が `503`、`POST /api/v1/sessions` が 500 連発。
- **ユーザーへの影響と縮退動作**:
  - 同時人数表示と不在証明 URL 発行は一時利用不可となる。
  - **デトックスタイマー・霧演出・環境音・SNS 画像カード生成（`ImageRenderer`）は 100% 影響なく動作する**（iOS アプリは URL 発行失敗時「画像カードのみで共有して始める」フォールバックを提示する仕様）。
- **対応**:
  1. Turso ステータスページ確認（`aws-ap-northeast-1`）。
  2. トークン失効や期限切れの場合は新規発行し Secret Manager を更新 → Cloud Run 新リビジョン適用。

### Runbook 3: OGP 画像生成エラー・メモリ超過（OOM）
- **兆候**: Cloud Run ログに `Memory limit exceeded` または `/ogp/{id}.png` で 500。
- **原因候補**:
  - 特殊絵文字・結合文字や想定外の巨大 SVG テキストによる `resvg` 負荷。
  - 並列アクセスによる同時 `resvg` 実行。
- **対応**:
  1. セマフォ並列数（初期値 4）を 2 に下げる、または一時的に Cloud Run メモリを `512MiB → 1GiB` へ引き上げ。
  2. 問題となった特定の `session_id` のテキストデータを調査し、サニタイズ正規化ルールを強化してユニットテストを追加する。

### Runbook 4: RevenueCat API 遅延・障害
- **兆候**: Pro オプション付き `POST /api/v1/sessions` がタイムアウト（2s）または失敗。
- **フェイルセーフ動作**:
  - バックエンドは `REVENUECAT_FAIL_OPEN=true` により、RevenueCat API が 2 秒以内に応答しない・5xx を返す場合は一時的に警告ログを残してセッション発行を許可する（課金済みの正当な Pro ユーザーが巻き込まれて開始できなくなる事態を防ぐため）。
  - 障害長期化時は RevenueCat Status を確認し、復旧後にログを調査する。

---

## 4. 不適切コンテンツ（UGC）削除・キャッシュパージ手順

不在証明ページ（`/s/{id}`）下部の通報リンク（Google フォーム、`session_id` 自動事前入力）から、公序良俗に反する投稿やスパム URL の報告を受けた場合の手順です（App Store Review Guideline 1.2 対応）。

1. **該当セッションの確認**: Google フォームの回答通知に記載された `session_id`（`/s/{id}` の `{id}`）を確認。
2. **DB からの即時非公開化・削除**:
   ```sql
   -- Turso CLI から即時削除または非公開化
   DELETE FROM sessions WHERE id = '<target_id>';
   ```
3. **Cloudflare エッジキャッシュのパージ**:
   - Cloudflare Dashboard → Caching → Configuration → **Custom Purge** を選択。
   - 以下の 2 URL を即時パージする:
     - `https://kumogakure.app/s/<target_id>`
     - `https://kumogakure.app/ogp/<target_id>.png`
4. **再発防止**: 含まれていた問題語句をサーバーの NG ワード辞書に追加・デプロイする（また、24 時間後には自動失効し物理削除される設計のため長期残存はしない）。

---

## 5. バックアップ・復旧方針

- Turso 上のレコードは **最大 24〜48 時間で自動削除される一時セッションデータのみ**（ユーザーの履歴資産は端末の SwiftData に保存される）であるため、DB の大規模リストア要件は低い。
- 万一データベースインスタンスが誤削除された場合でも、`migrations/0001_init.sql` を新規 Turso DB へ適用し、Secret Manager の URL/Token を差し替えることで **15 分以内** にサービス全体を復旧できる（RTO: 15 分、RPO: 一時セッションのみ最大 24 時間消滅）。
- ソースコード・マイグレーション・法務 HTML・ドキュメントはすべて GitHub リポジトリでバージョン管理する。
