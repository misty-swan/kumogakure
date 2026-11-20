#!/usr/bin/env bash
# W1-6: GCP dev 環境初期構築（API 有効化 / Artifact Registry / Service Account / Secret Manager）
# 正本: docs/04-infra-ops/infrastructure.md

set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:-${1:-}}"
REGION="${GCP_REGION:-asia-northeast1}"
AR_REPO="${GCP_AR_REPO:-kumogakure}"
SA_NAME="${GCP_CLOUD_RUN_SA:-kumogakure-api-dev}"

if [ -z "${PROJECT_ID}" ]; then
  echo "使い方: GCP_PROJECT_ID=<your-gcp-project-id> $0" >&2
  exit 1
fi

if ! command -v gcloud >/dev/null 2>&1; then
  echo "[ERROR] gcloud CLI が見つかりません。Google Cloud SDK をインストールしてください。" >&2
  exit 1
fi

ACTIVE_ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' || true)"
if [ -z "${ACTIVE_ACCOUNT}" ]; then
  echo "[ERROR] gcloud にログインしていません。先に 'gcloud auth login' を実行してください。" >&2
  exit 1
fi

echo "==> Setting active project: ${PROJECT_ID} (account: ${ACTIVE_ACCOUNT})"
gcloud config set project "${PROJECT_ID}" >/dev/null

echo "==> Enabling required GCP APIs..."
gcloud services enable \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  secretmanager.googleapis.com \
  cloudbuild.googleapis.com \
  --project="${PROJECT_ID}"

PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')"
COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
echo "==> Ensuring Cloud Build default SA '${COMPUTE_SA}' has roles/cloudbuild.builds.builder..."
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${COMPUTE_SA}" \
  --role="roles/cloudbuild.builds.builder" \
  --condition=None >/dev/null

echo "==> Ensuring Artifact Registry Docker repository '${AR_REPO}' in '${REGION}'..."
if gcloud artifacts repositories describe "${AR_REPO}" \
  --location="${REGION}" \
  --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "    Artifact Registry repository '${AR_REPO}' は既に存在します。"
else
  gcloud artifacts repositories create "${AR_REPO}" \
    --repository-format=docker \
    --location="${REGION}" \
    --description="Kumogakure backend container images" \
    --project="${PROJECT_ID}"
fi

SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
echo "==> Ensuring Cloud Run runtime Service Account '${SA_EMAIL}'..."
if gcloud iam service-accounts describe "${SA_EMAIL}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "    Service Account '${SA_EMAIL}' は既に存在します。"
else
  gcloud iam service-accounts create "${SA_NAME}" \
    --display-name="Kumogakure API dev runtime" \
    --project="${PROJECT_ID}"
fi

SECRETS=(
  "TURSO_AUTH_TOKEN"
  "REVENUECAT_SECRET_API_KEY"
  "INTERNAL_CLEANUP_SECRET"
)

echo "==> Ensuring Secret Manager secrets and granting secretAccessor to '${SA_EMAIL}'..."
for secret in "${SECRETS[@]}"; do
  if gcloud secrets describe "${secret}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    echo "    Secret '${secret}' は既に存在します。"
  else
    gcloud secrets create "${secret}" \
      --replication-policy="automatic" \
      --project="${PROJECT_ID}"
  fi

  gcloud secrets add-iam-policy-binding "${secret}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/secretmanager.secretAccessor" \
    --project="${PROJECT_ID}" >/dev/null

  VERSION_COUNT="$(gcloud secrets versions list "${secret}" --project="${PROJECT_ID}" --format='value(name)' | wc -l | tr -d ' ')"
  if [ "${VERSION_COUNT}" = "0" ]; then
    echo "    [INFO] Secret '${secret}' に初期バージョンを登録します（後で実値で上書きしてください）。"
    if [ "${secret}" = "INTERNAL_CLEANUP_SECRET" ]; then
      # dev 用初期ランダムシークレット生成
      head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' | \
        gcloud secrets versions add "${secret}" --data-file=- --project="${PROJECT_ID}" >/dev/null
    else
      printf 'PLACEHOLDER_REPLACE_ME' | \
        gcloud secrets versions add "${secret}" --data-file=- --project="${PROJECT_ID}" >/dev/null
    fi
  fi
done

echo ""
echo "================================================================"
echo "GCP dev 基盤セットアップ完了"
echo "  Project        : ${PROJECT_ID}"
echo "  Region         : ${REGION}"
echo "  AR Repository  : ${REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPO}"
echo "  Runtime SA     : ${SA_EMAIL}"
echo ""
echo "次のステップ: Turso トークン等の実値を Secret Manager へ登録してください:"
echo "  turso db tokens create kumogakure-dev | tr -d '\\n' | \\"
echo "    gcloud secrets versions add TURSO_AUTH_TOKEN --data-file=- --project=${PROJECT_ID}"
echo "  printf '<RC_SECRET_KEY>' | \\"
echo "    gcloud secrets versions add REVENUECAT_SECRET_API_KEY --data-file=- --project=${PROJECT_ID}"
echo "================================================================"
