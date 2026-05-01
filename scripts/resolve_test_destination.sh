#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="${PROJECT_PATH:-MOMENTO.xcodeproj}"
SCHEME="${SCHEME:-MOMENTO}"

cd "$ROOT_DIR"

destinations="$(
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -showdestinations 2>/dev/null
)"

preferred_names=(
  "iPhone 17 Pro"
  "iPhone 17 Pro Max"
  "iPhone 16 Pro"
  "iPhone 16 Pro Max"
  "iPhone 15 Pro"
  "iPhone 15 Pro Max"
  "iPhone 16"
  "iPhone 15"
  "iPhone 14 Pro"
)

for simulator_name in "${preferred_names[@]}"; do
  if printf "%s\n" "$destinations" | grep -q "platform:iOS Simulator,.*name:${simulator_name}[, }]"; then
    echo "platform=iOS Simulator,name=${simulator_name}"
    exit 0
  fi
done

fallback_name="$(
  printf "%s\n" "$destinations" \
    | sed -nE 's/.*platform:iOS Simulator,.*name:([^,}]+).*/\1/p' \
    | grep '^iPhone' \
    | head -n 1
)"

if [[ -n "$fallback_name" ]]; then
  echo "platform=iOS Simulator,name=${fallback_name}"
  exit 0
fi

echo "No concrete iPhone simulator destination found for ${SCHEME}." >&2
echo "Run xcodebuild -project ${PROJECT_PATH} -scheme ${SCHEME} -showdestinations to inspect available destinations." >&2
exit 65
