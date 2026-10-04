#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="${PROJECT_PATH:-MOMENTO.xcodeproj}"
SCHEME="${SCHEME:-MOMENTO}"

# Momento's deployment target. A simulator older than this cannot run the app,
# so destinations below this major version are rejected rather than silently used.
MIN_IOS_MAJOR="${MIN_IOS_MAJOR:-26}"

# Set to "ipad" to resolve an iPad destination instead of an iPhone.
DEVICE_FAMILY="${DEVICE_FAMILY:-iphone}"

cd "$ROOT_DIR"

destinations="$(
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -showdestinations 2>/dev/null
)"

# One "<os>\t<name>" row per concrete iOS Simulator destination, newest OS first.
simulators="$(
  printf "%s\n" "$destinations" \
    | sed -nE 's/.*platform:iOS Simulator,.*OS:([0-9.]+), name:(.*[^[:space:]])[[:space:]]*\}.*/\1\t\2/p' \
    | awk -F'\t' -v min="$MIN_IOS_MAJOR" '{ split($1, v, "."); if (v[1] + 0 >= min + 0) print }' \
    | sort -t'	' -k1,1Vr
)"

if [[ -z "$simulators" ]]; then
  echo "No iOS Simulator destination running iOS ${MIN_IOS_MAJOR}+ was found for ${SCHEME}." >&2
  echo "Momento targets iOS ${MIN_IOS_MAJOR}.0 and cannot run on older simulators." >&2
  echo "Install an iOS ${MIN_IOS_MAJOR}+ runtime (Xcode > Settings > Components), then retry." >&2
  echo "Run xcodebuild -project ${PROJECT_PATH} -scheme ${SCHEME} -showdestinations to inspect available destinations." >&2
  exit 65
fi

if [[ "$DEVICE_FAMILY" == "ipad" ]]; then
  preferred_names=(
    "iPad Pro 13-inch (M5)"
    "iPad Pro 11-inch (M5)"
    "iPad Pro 13-inch (M4)"
    "iPad Pro 11-inch (M4)"
    "iPad Air 13-inch (M4)"
    "iPad Air 11-inch (M4)"
    "iPad mini (A17 Pro)"
  )
  family_prefix="iPad"
else
  preferred_names=(
    "iPhone 18 Pro"
    "iPhone 18 Pro Max"
    "iPhone 17 Pro"
    "iPhone 17 Pro Max"
    "iPhone 17"
    "iPhone 16 Pro"
    "iPhone 16 Pro Max"
    "iPhone Air"
    "iPhone 16"
  )
  family_prefix="iPhone"
fi

emit() {
  # $1 = OS version, $2 = simulator name. OS is pinned so the chosen runtime is
  # unambiguous when several runtimes expose the same device name.
  echo "platform=iOS Simulator,name=$2,OS=$1"
  exit 0
}

for simulator_name in "${preferred_names[@]}"; do
  match="$(printf "%s\n" "$simulators" | awk -F'\t' -v n="$simulator_name" '$2 == n { print; exit }')"
  if [[ -n "$match" ]]; then
    emit "${match%%	*}" "${match#*	}"
  fi
done

# Fall back to the newest simulator in the requested family, then to anything usable.
fallback="$(printf "%s\n" "$simulators" | awk -F'\t' -v p="$family_prefix" 'index($2, p) == 1 { print; exit }')"
if [[ -z "$fallback" ]]; then
  fallback="$(printf "%s\n" "$simulators" | head -n 1)"
fi

emit "${fallback%%	*}" "${fallback#*	}"
