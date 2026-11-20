# インフラ構築・初期セットアップ手順（Week 0 〜 Week 1）

本ディレクトリには、Google Cloud Run・Turso・Google フォームの初期構築手順書と実行スクリプトを格納しています。全体設計・本番構成（Cloudflare / Cloud Scheduler / CI/CD）は [../docs/04-infra-ops/infrastructure.md](../docs/04-infra-ops/infrastructure.md) を正本としています。

---

## ディレクトリ構成

- `forms/google-forms-setup.md` — W0-1: お問い合わせフォーム＆UGC 通報フォーム（`session_id` 事前入力 URL）作成手順
- `scripts/setup-turso-dev.sh` — W1-5: Turso `kumogakure-dev`（`aws-ap-northeast-1` 東京）作成と `0001_init.sql` 適用
- `scripts/setup-gcp-dev.sh` — W1-6: GCP API 有効化・Artifact Registry・Service Account・Secret Manager 構築
- `scripts/deploy-cloudrun-dev.sh` — W1-6: Cloud Build ＋ Cloud Run `kumogakure-api-dev` デプロイと `/health` 疎通確認

---

## オーナー実施オンボーディング手順（Week 0〜1 残作業）

ローカルリポジトリ内のコード・素材・マイグレーション SQL・スクリプトはすべて準備済みです。外部アカウントログインを伴う以下の手順を実行すると、Week 0〜1 の全 DoD が完了します。

### 1. Google フォーム 2 種の作成（W0-1）
1. [forms/google-forms-setup.md](forms/google-forms-setup.md) に従ってフォーム ①（お問い合わせ）とフォーム ②（UGC 通報）を作成。
2. 両方でメール通知を有効化し、テスト送信を行う。
3. フォーム ② から取得した `REPORT_FORM_URL_TEMPLATE` を手元に控える。

### 2. Turso `dev` DB 作成＆マイグレーション適用（W1-5）
```bash
# Turso CLI 未インストール時
curl -sSfL https://get.tur.so/install.sh | bash
turso auth login

# kumogakure-dev 作成 + 0001_init.sql 適用
./infra/scripts/setup-turso-dev.sh

# 表示された TURSO_DATABASE_URL を控え、認証トークンを発行
turso db tokens create kumogakure-dev
```

### 3. GCP `dev` 環境構築＆Cloud Run 初回デプロイ（W1-6）
```bash
# gcloud CLI ログイン後、対象プロジェクト ID を指定
gcloud auth login
export GCP_PROJECT_ID="<your-gcp-project-id>"
export TURSO_DATABASE_URL="libsql://kumogakure-dev-<org>.turso.io"

# 1) API 有効化・AR・SA・Secret Manager 作成
./infra/scripts/setup-gcp-dev.sh

# 2) Turso 認証トークンを Secret Manager へ登録（RevenueCat キーも取得済みなら同様に登録）
turso db tokens create kumogakure-dev | tr -d '\n' | \
  gcloud secrets versions add TURSO_AUTH_TOKEN --data-file=- --project="${GCP_PROJECT_ID}"

# 3) ビルド＆Cloud Run dev デプロイ＆/health?deep=1 疎通確認
./infra/scripts/deploy-cloudrun-dev.sh
```

> **コスト保護設定**: `deploy-cloudrun-dev.sh` は `min-instances=0`, `max-instances=3`, `cpu-throttling` 有効でデプロイするため、検証中のアイドル課金は発生しません。
