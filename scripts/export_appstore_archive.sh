#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE_PATH="${1:-/tmp/MomentoRelease.xcarchive}"
EXPORT_PATH="${2:-/tmp/MomentoAppStoreExport}"
EXPORT_OPTIONS="${ROOT_DIR}/Config/AppStoreExportOptions.plist"

cd "$ROOT_DIR"

if [[ ! -d "$ARCHIVE_PATH" ]]; then
  echo "Archive not found: ${ARCHIVE_PATH}"
  echo "Create one first with:"
  echo "xcodebuild archive -project MOMENTO.xcodeproj -scheme MOMENTO -configuration Release -destination 'generic/platform=iOS' -archivePath '${ARCHIVE_PATH}'"
  exit 1
fi

rm -rf "$EXPORT_PATH"
mkdir -p "$EXPORT_PATH"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS"

echo "Archive export complete."
echo "Export path: ${EXPORT_PATH}"
