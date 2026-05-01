#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="${ROOT_DIR}/build/release-smoke"
RESULT_DIR="${LOG_DIR}/xcresults"
PROJECT_PATH="${PROJECT_PATH:-MOMENTO.xcodeproj}"
SCHEME="${SCHEME:-MOMENTO}"
ARCHIVE_PATH="${ARCHIVE_PATH:-/tmp/MomentoRelease.xcarchive}"
TEST_DESTINATION="${TEST_DESTINATION:-}"

mkdir -p "$LOG_DIR"
rm -rf "$RESULT_DIR"
mkdir -p "$RESULT_DIR"
cd "$ROOT_DIR"
rm -rf "$ARCHIVE_PATH"

if [[ -z "$TEST_DESTINATION" ]]; then
  TEST_DESTINATION="$(./scripts/resolve_test_destination.sh)"
fi

run_and_log() {
  local name="$1"
  shift
  echo "== ${name} =="
  "$@" 2>&1 | tee "${LOG_DIR}/${name}.log"
}

run_and_log showdestinations \
  xcodebuild -project "$PROJECT_PATH" -scheme "$SCHEME" -showdestinations

run_and_log devices \
  xcrun devicectl list devices

run_and_log tests \
  xcodebuild test \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -destination "$TEST_DESTINATION" \
    -resultBundlePath "${RESULT_DIR}/tests.xcresult"

run_and_log generic-debug-build \
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -destination "generic/platform=iOS" \
    -resultBundlePath "${RESULT_DIR}/generic-debug-build.xcresult" \
    build

run_and_log generic-release-build \
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -resultBundlePath "${RESULT_DIR}/generic-release-build.xcresult" \
    build

run_and_log archive \
  xcodebuild archive \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE_PATH"

echo "Release smoke test completed."
echo "Logs: ${LOG_DIR}"
echo "Result bundles: ${RESULT_DIR}"
echo "Archive: ${ARCHIVE_PATH}"
echo "Test destination: ${TEST_DESTINATION}"
