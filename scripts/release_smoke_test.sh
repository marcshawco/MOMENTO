#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="${ROOT_DIR}/build/release-smoke"
ARCHIVE_PATH="/tmp/MomentoRelease.xcarchive"

mkdir -p "$LOG_DIR"
cd "$ROOT_DIR"
rm -rf "$ARCHIVE_PATH"

run_and_log() {
  local name="$1"
  shift
  echo "== ${name} =="
  "$@" 2>&1 | tee "${LOG_DIR}/${name}.log"
}

run_and_log showdestinations \
  xcodebuild -project MOMENTO.xcodeproj -scheme MOMENTO -showdestinations

run_and_log devices \
  xcrun devicectl list devices

run_and_log tests \
  xcodebuild test \
    -project MOMENTO.xcodeproj \
    -scheme MOMENTO \
    -destination "platform=iOS Simulator,name=iPhone 17 Pro"

run_and_log generic-debug-build \
  xcodebuild \
    -project MOMENTO.xcodeproj \
    -scheme MOMENTO \
    -destination "generic/platform=iOS" \
    build

run_and_log generic-release-build \
  xcodebuild \
    -project MOMENTO.xcodeproj \
    -scheme MOMENTO \
    -configuration Release \
    -destination "generic/platform=iOS" \
    build

run_and_log archive \
  xcodebuild archive \
    -project MOMENTO.xcodeproj \
    -scheme MOMENTO \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE_PATH"

echo "Release smoke test completed."
echo "Logs: ${LOG_DIR}"
echo "Archive: ${ARCHIVE_PATH}"
