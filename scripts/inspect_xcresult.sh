#!/bin/zsh
set -euo pipefail

RESULT_PATH="${1:-}"

if [[ -z "$RESULT_PATH" ]]; then
  echo "Usage: ./scripts/inspect_xcresult.sh <path-to-result.xcresult>"
  echo ""
  echo "Common release-smoke paths:"
  echo "  build/release-smoke/xcresults/tests.xcresult"
  echo "  build/release-smoke/xcresults/generic-debug-build.xcresult"
  echo "  build/release-smoke/xcresults/generic-release-build.xcresult"
  exit 64
fi

if [[ ! -d "$RESULT_PATH" ]]; then
  echo "Result bundle not found: ${RESULT_PATH}"
  exit 66
fi

echo "== content-availability =="
xcrun xcresulttool get content-availability --path "$RESULT_PATH" || true

echo ""
echo "== test-results-summary =="
xcrun xcresulttool get test-results summary --path "$RESULT_PATH" || true

echo ""
echo "== build-results =="
xcrun xcresulttool get build-results --path "$RESULT_PATH" || true
