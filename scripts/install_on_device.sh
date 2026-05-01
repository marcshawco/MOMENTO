#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="${PROJECT_PATH:-MOMENTO.xcodeproj}"
SCHEME="${SCHEME:-MOMENTO}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DEVICE_ID="${DEVICE_ID:-}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/MomentoDeviceDerivedData}"
BUNDLE_ID="${BUNDLE_ID:-marcshaw.MOMENTO}"

cd "$ROOT_DIR"

if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="$(
    xcodebuild \
      -project "$PROJECT_PATH" \
      -scheme "$SCHEME" \
      -showdestinations 2>/dev/null \
      | sed -nE 's/.*platform:iOS, arch:arm64, id:([^,}]+).*/\1/p' \
      | head -n 1
  )"
fi

if [[ -z "$DEVICE_ID" ]]; then
  echo "No connected iPhone found."
  echo "Connect and unlock the iPhone, trust this Mac, then run ./scripts/device_diagnostics.sh."
  exit 65
fi

echo "== build-for-device =="
echo "Device: ${DEVICE_ID}"
echo "DerivedData: ${DERIVED_DATA_PATH}"
rm -rf "$DERIVED_DATA_PATH"

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "id=${DEVICE_ID}" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}-iphoneos/${SCHEME}.app"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app not found: ${APP_PATH}"
  exit 66
fi

echo ""
echo "== install-on-device =="
xcrun devicectl device install app \
  --device "$DEVICE_ID" \
  "$APP_PATH"

echo ""
echo "== launch-on-device =="
xcrun devicectl device process launch \
  --device "$DEVICE_ID" \
  "$BUNDLE_ID" \
  --terminate-existing \
  --activate

echo ""
echo "Installed and launched ${BUNDLE_ID} on ${DEVICE_ID}."
