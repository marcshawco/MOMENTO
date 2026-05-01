#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE_PATH="${ARCHIVE_PATH:-/tmp/MomentoRelease.xcarchive}"

cd "$ROOT_DIR"

echo "== validate-app-store-metadata =="
./scripts/validate_app_store_metadata.sh

echo ""
echo "== release-smoke-test =="
./scripts/release_smoke_test.sh

echo ""
echo "== verify-archive-metadata =="
./scripts/verify_archive_metadata.sh "$ARCHIVE_PATH"

echo ""
echo "Preflight release checks completed."
echo "Archive: ${ARCHIVE_PATH}"
