#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="${ROOT_DIR}/build/device-diagnostics"
DEVICE_QUERY="${1:-}"

mkdir -p "$LOG_DIR"
cd "$ROOT_DIR"

run_and_log() {
  local name="$1"
  shift
  echo "== ${name} =="
  "$@" 2>&1 | tee "${LOG_DIR}/${name}.log"
}

run_and_log xcode-version xcodebuild -version
run_and_log build-settings \
  xcodebuild \
    -project MOMENTO.xcodeproj \
    -scheme MOMENTO \
    -configuration Debug \
    -showBuildSettings

run_and_log destinations \
  xcodebuild \
    -project MOMENTO.xcodeproj \
    -scheme MOMENTO \
    -configuration Debug \
    -showdestinations

run_and_log coredevice-list xcrun devicectl list devices
run_and_log xctrace-list xcrun xctrace list devices

if [[ -n "$DEVICE_QUERY" ]]; then
  run_and_log "coredevice-details-${DEVICE_QUERY}" \
    xcrun devicectl device info details --device "$DEVICE_QUERY"
fi

echo ""
echo "Device diagnostics complete."
echo "Logs: ${LOG_DIR}"
echo ""
echo "Install reminder: Product > Build only compiles. Product > Run installs and launches, but only when the iPhone appears as an available destination."
