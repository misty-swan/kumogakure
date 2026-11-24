#!/usr/bin/env bash
# W1-6: Cloud Run dev サービスビルド・デプロイ・/health 疎通確認スクリプト
# 正本: docs/04-infra-ops/infrastructure.md, docs/03-architecture/api-spec.md

set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:-}"
TURSO_URL="${TURSO_DATABASE_URL:-}"
REGION="${GCP_REGION:-asia-northeast1}"
AR_REPO="${GCP_AR_REPO:-kumogakure}"
SERVICE_NAME="${CLOUD_RUN_SERVICE_NAME:-kumogakure-api-dev}"
SA_NAME="${GCP_CLOUD_RUN_SA:-kumogakure-api-dev}"
IMAGE_TAG="${IMAGE_TAG:-dev-$(date -u +%Y%m%d%H%M%S)}"
REPORT_FORM_URL_TEMPLATE="${REPORT_FORM_URL_TEMPLATE:-https://docs.google.com/forms/d/e/1FAIpQLSf4jPMH3ZLLRR6u6AB4S8t5xHg3zGQDsmFG_mIDqrxwxEX2Wg/viewform?usp=pp_url&entry.1371370885={session_id}}"

if [ -z "${PROJECT_ID}" ] || [ -z "${TURSO_URL}" ]; then
  echo "使い方: GCP_PROJECT_ID=<id> TURSO_DATABASE_URL=libsql://... [REPORT_FORM_URL_TEMPLATE=...] $0" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
API_DIR="${REPO_ROOT}/services/api"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
IMAGE_URI="${REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPO}/api:${IMAGE_TAG}"

echo "==> Building container image via Cloud Build: ${IMAGE_URI}"
gcloud builds submit "${API_DIR}" \
  --tag="${IMAGE_URI}" \
  --project="${PROJECT_ID}"

ENV_VARS="^@^APP_ENV=dev@TURSO_DATABASE_URL=${TURSO_URL}@REVENUECAT_FAIL_OPEN=true@RUST_LOG=info,kumogakure_api=debug@REPORT_FORM_URL_TEMPLATE=${REPORT_FORM_URL_TEMPLATE}"

echo "==> Deploying Cloud Run service '${SERVICE_NAME}' in '${REGION}'..."
gcloud run deploy "${SERVICE_NAME}" \
  --image="${IMAGE_URI}" \
  --region="${REGION}" \
  --allow-unauthenticated \
  --service-account="${SA_EMAIL}" \
  --cpu=1 \
  --memory=512Mi \
  --cpu-throttling \
  --min-instances=0 \
  --max-instances=3 \
  --concurrency=40 \
  --timeout=15s \
  --set-env-vars="${ENV_VARS}" \
  --set-secrets="TURSO_AUTH_TOKEN=TURSO_AUTH_TOKEN:latest,REVENUECAT_SECRET_API_KEY=REVENUECAT_SECRET_API_KEY:latest,INTERNAL_CLEANUP_SECRET=INTERNAL_CLEANUP_SECRET:latest" \
  --project="${PROJECT_ID}"

SERVICE_URL="$(gcloud run services describe "${SERVICE_NAME}" \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --format='value(status.url)')"

echo "==> Updating BASE_URL=${SERVICE_URL} on '${SERVICE_NAME}'..."
gcloud run services update "${SERVICE_NAME}" \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --update-env-vars="BASE_URL=${SERVICE_URL}" >/dev/null

echo "==> Running smoke tests against ${SERVICE_URL}..."
echo "--- GET /health ---"
curl -fsS "${SERVICE_URL}/health"
echo ""
echo "--- GET /health?deep=1 ---"
curl -fsS "${SERVICE_URL}/health?deep=1"
echo ""
echo "--- GET /api/v1/stats/active ---"
curl -fsS "${SERVICE_URL}/api/v1/stats/active"
echo ""
echo "--- GET /legal/privacy (status) ---"
curl -fsS -o /dev/null -w "HTTP %{http_code}\n" "${SERVICE_URL}/legal/privacy"
echo "--- GET /legal/terms (status) ---"
curl -fsS -o /dev/null -w "HTTP %{http_code}\n" "${SERVICE_URL}/legal/terms"
echo "================================================================"
echo "Cloud Run dev デプロイ＆疎通確認完了: ${SERVICE_URL}"
echo "================================================================"
