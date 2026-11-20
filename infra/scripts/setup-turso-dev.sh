#!/usr/bin/env bash
# W1-5: Turso dev データベース作成・初期マイグレーション適用・検証スクリプト
# 正本: docs/04-infra-ops/infrastructure.md, docs/03-architecture/database-design.md

set -euo pipefail

DB_NAME="${TURSO_DEV_DB_NAME:-kumogakure-dev}"
DB_GROUP="${TURSO_DEV_GROUP:-default}"
DB_LOCATION="${TURSO_DEV_LOCATION:-aws-ap-northeast-1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MIGRATION_FILE="${REPO_ROOT}/services/api/migrations/0001_init.sql"

if ! command -v turso >/dev/null 2>&1; then
  echo "[ERROR] turso CLI が見つかりません。https://docs.turso.tech/cli/installation を参照してインストールしてください。" >&2
  exit 1
fi

if ! turso auth whoami >/dev/null 2>&1; then
  echo "[ERROR] turso CLI にログインしていません。先に 'turso auth login' を実行してください。" >&2
  exit 1
fi

if [ ! -f "${MIGRATION_FILE}" ]; then
  echo "[ERROR] マイグレーションファイルが見つかりません: ${MIGRATION_FILE}" >&2
  exit 1
fi

echo "==> Checking Turso DB '${DB_NAME}'..."
if turso db show "${DB_NAME}" >/dev/null 2>&1; then
  echo "    DB '${DB_NAME}' は既に存在します。作成をスキップします。"
else
  echo "    Creating DB '${DB_NAME}' in location '${DB_LOCATION}' (group '${DB_GROUP}')..."
  turso db create "${DB_NAME}" --location "${DB_LOCATION}" --group "${DB_GROUP}" --wait || \
    turso db create "${DB_NAME}" --location "${DB_LOCATION}" --wait
fi

echo "==> Applying migration: ${MIGRATION_FILE}"
turso db shell "${DB_NAME}" < "${MIGRATION_FILE}"

echo "==> Verifying tables and indexes in '${DB_NAME}'..."
turso db shell "${DB_NAME}" \
  "SELECT type, name FROM sqlite_master WHERE name IN ('sessions', '_schema_migrations', 'idx_sessions_active', 'idx_sessions_user_active', 'idx_sessions_expires_at') ORDER BY type, name;"

DB_URL="$(turso db show "${DB_NAME}" --url)"
echo ""
echo "================================================================"
echo "Turso dev DB 準備完了"
echo "  DB Name            : ${DB_NAME}"
echo "  TURSO_DATABASE_URL : ${DB_URL}"
echo ""
echo "次のステップ（Secret Manager 格納用の認証トークン発行）:"
echo "  turso db tokens create ${DB_NAME}"
echo "================================================================"
