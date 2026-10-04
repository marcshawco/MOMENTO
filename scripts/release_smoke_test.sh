#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="${ROOT_DIR}/build/release-smoke"
RESULT_DIR="${LOG_DIR}/xcresults"
PROJECT_PATH="${PROJECT_PATH:-MOMENTO.xcodeproj}"
SCHEME="${SCHEME:-MOMENTO}"
ARCHIVE_PATH="${ARCHIVE_PATH:-/tmp/MomentoRelease.xcarchive}"
TEST_DESTINATION="${TEST_DESTINATION:-}"
TEST_DESTINATION_IPAD="${TEST_DESTINATION_IPAD:-}"
# Momento ships for both iPhone and iPad (TARGETED_DEVICE_FAMILY 1,2).
# Set RUN_IPAD_TESTS=0 to skip the iPad leg locally.
RUN_IPAD_TESTS="${RUN_IPAD_TESTS:-1}"
# Device-targeted builds and the archive normally need a provisioning profile.
# CI runners have no signing assets, so set CODE_SIGNING=0 there to build and
# archive unsigned. Simulator tests never need signing either way.
CODE_SIGNING="${CODE_SIGNING:-1}"

mkdir -p "$LOG_DIR"
rm -rf "$RESULT_DIR"
mkdir -p "$RESULT_DIR"
cd "$ROOT_DIR"
rm -rf "$ARCHIVE_PATH"

if [[ -z "$TEST_DESTINATION" ]]; then
  TEST_DESTINATION="$(./scripts/resolve_test_destination.sh)"
fi

if [[ "$RUN_IPAD_TESTS" != "0" && -z "$TEST_DESTINATION_IPAD" ]]; then
  TEST_DESTINATION_IPAD="$(DEVICE_FAMILY=ipad ./scripts/resolve_test_destination.sh)"
fi

run_and_log() {
  local name="$1"
  shift
  echo "== ${name} =="
  "$@" 2>&1 | tee "${LOG_DIR}/${name}.log"
}

signing_args=()
if [[ "$CODE_SIGNING" == "0" ]]; then
  signing_args=(
    CODE_SIGNING_ALLOWED=NO
    CODE_SIGNING_REQUIRED=NO
    CODE_SIGN_IDENTITY=""
  )
  echo "Code signing disabled for device builds and archive."
fi

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

if [[ "$RUN_IPAD_TESTS" != "0" ]]; then
  run_and_log tests-ipad \
    xcodebuild test \
      -project "$PROJECT_PATH" \
      -scheme "$SCHEME" \
      -destination "$TEST_DESTINATION_IPAD" \
      -resultBundlePath "${RESULT_DIR}/tests-ipad.xcresult"
fi

run_and_log generic-debug-build \
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -destination "generic/platform=iOS" \
    -resultBundlePath "${RESULT_DIR}/generic-debug-build.xcresult" \
    "${signing_args[@]}" \
    build

run_and_log generic-release-build \
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -resultBundlePath "${RESULT_DIR}/generic-release-build.xcresult" \
    "${signing_args[@]}" \
    build

run_and_log archive \
  xcodebuild archive \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE_PATH" \
    "${signing_args[@]}"

echo "Release smoke test completed."
echo "Logs: ${LOG_DIR}"
echo "Result bundles: ${RESULT_DIR}"
echo "Archive: ${ARCHIVE_PATH}"
echo "Test destination (iPhone): ${TEST_DESTINATION}"
if [[ "$RUN_IPAD_TESTS" != "0" ]]; then
  echo "Test destination (iPad): ${TEST_DESTINATION_IPAD}"
fi
