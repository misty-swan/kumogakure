#!/usr/bin/env bash
# W2-6: GitHub Actions CI/CD 用 GCP Workload Identity Federation (キーレス認証) 構築
# 正本: docs/04-infra-ops/infrastructure.md

set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:-${1:-}}"
GITHUB_REPO="${GITHUB_REPO:-misty-swan/kumogakure}"
REGION="${GCP_REGION:-asia-northeast1}"
AR_REPO="${GCP_AR_REPO:-kumogakure}"
POOL_ID="${WIF_POOL_ID:-github-actions}"
PROVIDER_ID="${WIF_PROVIDER_ID:-github-repo}"
DEPLOY_SA_NAME="${GCP_DEPLOY_SA_NAME:-kumogakure-github-deployer}"
RUNTIME_SA_NAME="${GCP_CLOUD_RUN_SA:-kumogakure-api-dev}"
TURSO_URL="${TURSO_DATABASE_URL:-libsql://kumogakure-dev-misty-swan.aws-ap-northeast-1.turso.io}"
REPORT_FORM_URL_TEMPLATE="${REPORT_FORM_URL_TEMPLATE:-https://docs.google.com/forms/d/e/1FAIpQLSf4jPMH3ZLLRR6u6AB4S8t5xHg3zGQDsmFG_mIDqrxwxEX2Wg/viewform?usp=pp_url&entry.1371370885={session_id}}"

if [ -z "${PROJECT_ID}" ]; then
  echo "使い方: GCP_PROJECT_ID=<your-gcp-project-id> [GITHUB_REPO=owner/repo] $0" >&2
  exit 1
fi

PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')"
DEPLOY_SA_EMAIL="${DEPLOY_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
RUNTIME_SA_EMAIL="${RUNTIME_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "==> Ensuring deploy Service Account '${DEPLOY_SA_EMAIL}'..."
if ! gcloud iam service-accounts describe "${DEPLOY_SA_EMAIL}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud iam service-accounts create "${DEPLOY_SA_NAME}" \
    --display-name="Kumogakure GitHub Actions Deployer" \
    --project="${PROJECT_ID}"
fi

for role in roles/run.admin roles/artifactregistry.writer; do
  for attempt in 1 2 3 4 5; do
    if gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
      --member="serviceAccount:${DEPLOY_SA_EMAIL}" \
      --role="${role}" \
      --condition=None >/dev/null 2>&1; then
      break
    fi
    if [ "${attempt}" = "5" ]; then
      gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${DEPLOY_SA_EMAIL}" \
        --role="${role}" \
        --condition=None
    fi
    sleep 2
  done
done

gcloud iam service-accounts add-iam-policy-binding "${RUNTIME_SA_EMAIL}" \
  --member="serviceAccount:${DEPLOY_SA_EMAIL}" \
  --role="roles/iam.serviceAccountUser" \
  --project="${PROJECT_ID}" >/dev/null

echo "==> Ensuring Workload Identity Pool '${POOL_ID}'..."
if ! gcloud iam workload-identity-pools describe "${POOL_ID}" \
  --location="global" \
  --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud iam workload-identity-pools create "${POOL_ID}" \
    --location="global" \
    --display-name="GitHub Actions Pool" \
    --project="${PROJECT_ID}"
fi

echo "==> Ensuring Workload Identity Provider '${PROVIDER_ID}' for '${GITHUB_REPO}'..."
if ! gcloud iam workload-identity-pools providers describe "${PROVIDER_ID}" \
  --workload-identity-pool="${POOL_ID}" \
  --location="global" \
  --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud iam workload-identity-pools providers create-oidc "${PROVIDER_ID}" \
    --workload-identity-pool="${POOL_ID}" \
    --location="global" \
    --display-name="GitHub Repository Provider" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.ref=assertion.ref" \
    --attribute-condition="assertion.repository == '${GITHUB_REPO}'" \
    --project="${PROJECT_ID}"
fi

WIF_MEMBER="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/attribute.repository/${GITHUB_REPO}"
gcloud iam service-accounts add-iam-policy-binding "${DEPLOY_SA_EMAIL}" \
  --member="${WIF_MEMBER}" \
  --role="roles/iam.workloadIdentityUser" \
  --project="${PROJECT_ID}" >/dev/null

WIF_PROVIDER_FULL="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}"

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  echo "==> Setting GitHub repository Actions variables (non-secret values) on '${GITHUB_REPO}'..."
  gh variable set GCP_PROJECT_ID --repo "${GITHUB_REPO}" --body "${PROJECT_ID}"
  gh variable set GCP_REGION --repo "${GITHUB_REPO}" --body "${REGION}"
  gh variable set GCP_AR_REPO --repo "${GITHUB_REPO}" --body "${AR_REPO}"
  gh variable set GCP_WORKLOAD_IDENTITY_PROVIDER --repo "${GITHUB_REPO}" --body "${WIF_PROVIDER_FULL}"
  gh variable set GCP_DEPLOY_SA --repo "${GITHUB_REPO}" --body "${DEPLOY_SA_EMAIL}"
  gh variable set TURSO_DATABASE_URL_DEV --repo "${GITHUB_REPO}" --body "${TURSO_URL}"
  gh variable set REPORT_FORM_URL_TEMPLATE --repo "${GITHUB_REPO}" --body "${REPORT_FORM_URL_TEMPLATE}"
fi

echo "================================================================"
echo "GitHub Actions WIF 設定完了"
echo "  Provider : ${WIF_PROVIDER_FULL}"
echo "  Deploy SA: ${DEPLOY_SA_EMAIL}"
echo "================================================================"
