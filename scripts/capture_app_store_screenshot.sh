#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${ROOT_DIR}/build/app-store-screenshots"
RAW_NAME="${1:-screenshot}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

safe_name() {
  printf "%s" "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

NAME="$(safe_name "$RAW_NAME")"
if [[ -z "$NAME" ]]; then
  NAME="screenshot"
fi

mkdir -p "$OUTPUT_DIR"

BOOTED_COUNT="$(xcrun simctl list devices booted | grep -c "(Booted)" || true)"
if [[ "$BOOTED_COUNT" == "0" ]]; then
  echo "No booted simulator found. Launch Momento in Simulator first, then rerun this script."
  exit 65
fi

if (( BOOTED_COUNT > 1 )); then
  echo "Multiple booted simulators found. Shut down extras or capture manually with xcrun simctl io <udid> screenshot."
  exit 65
fi

OUTPUT_FILE="${OUTPUT_DIR}/${TIMESTAMP}-${NAME}.png"
xcrun simctl io booted screenshot "$OUTPUT_FILE"

echo "Screenshot saved:"
echo "$OUTPUT_FILE"
