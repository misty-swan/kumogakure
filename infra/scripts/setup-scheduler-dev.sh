#!/usr/bin/env bash
# W2-6: Cloud Scheduler dev クリーンアップジョブ構築（毎日 JST 04:00）
# 正本: docs/04-infra-ops/infrastructure.md, docs/03-architecture/api-spec.md

set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:-${1:-}}"
REGION="${GCP_REGION:-asia-northeast1}"
SERVICE_NAME="${CLOUD_RUN_SERVICE_NAME:-kumogakure-api-dev}"
JOB_NAME="${CLOUD_SCHEDULER_JOB_NAME:-kumogakure-cleanup-dev}"
SCHEDULE="${CLEANUP_SCHEDULE:-0 4 * * *}"
TIME_ZONE="${CLEANUP_TIME_ZONE:-Asia/Tokyo}"

if [ -z "${PROJECT_ID}" ]; then
  echo "使い方: GCP_PROJECT_ID=<your-gcp-project-id> $0" >&2
  exit 1
fi

echo "==> Enabling Cloud Scheduler API..."
gcloud services enable cloudscheduler.googleapis.com --project="${PROJECT_ID}"

SERVICE_URL="$(gcloud run services describe "${SERVICE_NAME}" \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --format='value(status.url)')"

if [ -z "${SERVICE_URL}" ]; then
  echo "[ERROR] Cloud Run service '${SERVICE_NAME}' URL could not be resolved." >&2
  exit 1
fi

TARGET_URI="${SERVICE_URL}/internal/cleanup"
CLEANUP_SECRET="$(gcloud secrets versions access latest \
  --secret=INTERNAL_CLEANUP_SECRET \
  --project="${PROJECT_ID}" | tr -d '\r\n')"

if [ -z "${CLEANUP_SECRET}" ]; then
  echo "[ERROR] INTERNAL_CLEANUP_SECRET is empty in Secret Manager." >&2
  exit 1
fi

if gcloud scheduler jobs describe "${JOB_NAME}" \
  --location="${REGION}" \
  --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "==> Updating Cloud Scheduler job '${JOB_NAME}' -> ${TARGET_URI}..."
  gcloud scheduler jobs update http "${JOB_NAME}" \
    --location="${REGION}" \
    --project="${PROJECT_ID}" \
    --schedule="${SCHEDULE}" \
    --time-zone="${TIME_ZONE}" \
    --uri="${TARGET_URI}" \
    --http-method=POST \
    --update-headers="X-Internal-Secret=${CLEANUP_SECRET}" \
    --max-retry-attempts=2 \
    --attempt-deadline=30s >/dev/null
else
  echo "==> Creating Cloud Scheduler job '${JOB_NAME}' -> ${TARGET_URI}..."
  gcloud scheduler jobs create http "${JOB_NAME}" \
    --location="${REGION}" \
    --project="${PROJECT_ID}" \
    --schedule="${SCHEDULE}" \
    --time-zone="${TIME_ZONE}" \
    --uri="${TARGET_URI}" \
    --http-method=POST \
    --headers="X-Internal-Secret=${CLEANUP_SECRET}" \
    --max-retry-attempts=2 \
    --attempt-deadline=30s >/dev/null
fi

unset CLEANUP_SECRET

echo "================================================================"
echo "Cloud Scheduler dev 設定完了: ${JOB_NAME} (${SCHEDULE} ${TIME_ZONE})"
echo "Target: POST ${TARGET_URI}"
echo "================================================================"
