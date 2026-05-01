#!/bin/zsh
set -euo pipefail

ARCHIVE_PATH="${1:-/tmp/MomentoRelease.xcarchive}"
EXPECT_DISTRIBUTION="${EXPECT_DISTRIBUTION:-0}"

if [[ ! -d "$ARCHIVE_PATH" ]]; then
  echo "Archive not found: ${ARCHIVE_PATH}"
  exit 66
fi

APP_PATH="$(find "${ARCHIVE_PATH}/Products/Applications" -maxdepth 1 -type d -name "*.app" | head -n 1)"

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "No .app found in archive: ${ARCHIVE_PATH}"
  exit 65
fi

INFO_PLIST="${APP_PATH}/Info.plist"
PRIVACY_MANIFEST="${APP_PATH}/PrivacyInfo.xcprivacy"

if [[ ! -f "$INFO_PLIST" ]]; then
  echo "Missing Info.plist in app bundle: ${APP_PATH}"
  exit 65
fi

print_value() {
  local key="$1"
  local label="$2"
  local value
  value="$(/usr/libexec/PlistBuddy -c "Print :${key}" "$INFO_PLIST" 2>/dev/null || true)"
  echo "${label}: ${value:-missing}"
}

echo "== archive =="
echo "Archive: ${ARCHIVE_PATH}"
echo "App: ${APP_PATH}"

echo ""
echo "== info-plist =="
print_value "CFBundleIdentifier" "Bundle ID"
print_value "CFBundleDisplayName" "Display Name"
print_value "CFBundleShortVersionString" "Marketing Version"
print_value "CFBundleVersion" "Build Number"
print_value "MinimumOSVersion" "Minimum OS"
print_value "ITSAppUsesNonExemptEncryption" "Uses Non-Exempt Encryption"

SUPPORTED_PLATFORMS="$(/usr/libexec/PlistBuddy -c "Print :CFBundleSupportedPlatforms" "$INFO_PLIST" 2>/dev/null || true)"
echo "Supported Platforms: ${SUPPORTED_PLATFORMS:-missing}"

echo ""
echo "== privacy =="
if [[ -f "$PRIVACY_MANIFEST" ]]; then
  echo "Privacy manifest: present"
  /usr/bin/plutil -lint "$PRIVACY_MANIFEST"
else
  echo "Privacy manifest: missing"
  exit 65
fi

echo ""
echo "== signing =="
SIGNING_SUMMARY="$(/usr/bin/codesign -dv "$APP_PATH" 2>&1 || true)"
echo "$SIGNING_SUMMARY" | grep -E "Authority=|TeamIdentifier=|Signature=|Runtime Version=" || true

ENTITLEMENTS_PLIST="$(mktemp)"
trap 'rm -f "$ENTITLEMENTS_PLIST"' EXIT

if /usr/bin/codesign -d --entitlements :- "$APP_PATH" > "$ENTITLEMENTS_PLIST" 2>/dev/null; then
  GET_TASK_ALLOW="$(/usr/libexec/PlistBuddy -c "Print :get-task-allow" "$ENTITLEMENTS_PLIST" 2>/dev/null || echo "missing")"
  APPLICATION_IDENTIFIER="$(/usr/libexec/PlistBuddy -c "Print :application-identifier" "$ENTITLEMENTS_PLIST" 2>/dev/null || echo "missing")"
  echo "application-identifier: ${APPLICATION_IDENTIFIER}"
  echo "get-task-allow: ${GET_TASK_ALLOW}"
else
  echo "Entitlements: unavailable"
fi

if [[ "$SUPPORTED_PLATFORMS" != *"iPhoneOS"* ]]; then
  echo "ERROR: Archive does not advertise iPhoneOS support."
  exit 1
fi

if [[ "$EXPECT_DISTRIBUTION" == "1" ]]; then
  if [[ "$GET_TASK_ALLOW" != "false" ]]; then
    echo "ERROR: Distribution export expected get-task-allow=false."
    exit 1
  fi

  if ! echo "$SIGNING_SUMMARY" | grep -q "Authority=Apple Distribution"; then
    echo "ERROR: Distribution export expected Apple Distribution signing."
    exit 1
  fi
fi

echo ""
echo "Archive metadata verification complete."
