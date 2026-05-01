#!/bin/zsh
set -euo pipefail

METADATA_FILE="${1:-APP_STORE_METADATA_DRAFT.md}"

if [[ ! -f "$METADATA_FILE" ]]; then
  echo "Metadata draft not found: ${METADATA_FILE}"
  exit 66
fi

section_text() {
  local section="$1"
  awk -v section="$section" '
    $0 == "## " section { in_section = 1; next }
    /^## / && in_section { exit }
    in_section { print }
  ' "$METADATA_FILE" | sed '/^[[:space:]]*$/d'
}

identity_value() {
  local label="$1"
  awk -v label="$label" '
    index($0, "- " label ": ") == 1 {
      sub("- " label ": ", "")
      print
      exit
    }
  ' "$METADATA_FILE"
}

char_count() {
  LC_ALL=C awk '{ count += length($0) + 1 } END { if (count > 0) count -= 1; print count + 0 }'
}

failures=0

check_max() {
  local label="$1"
  local value="$2"
  local max="$3"
  local length
  length="$(printf "%s" "$value" | char_count)"

  if (( length > max )); then
    echo "FAIL ${label}: ${length}/${max} characters"
    failures=$((failures + 1))
  else
    echo "OK   ${label}: ${length}/${max} characters"
  fi
}

check_required() {
  local label="$1"
  local value="$2"

  if [[ -z "${value//[[:space:]]/}" ]]; then
    echo "FAIL ${label}: missing"
    failures=$((failures + 1))
  else
    echo "OK   ${label}: present"
  fi
}

app_name="$(identity_value "App name")"
subtitle="$(identity_value "Subtitle")"
promo_text="$(section_text "Promotional Text")"
description="$(section_text "Description")"
keywords="$(section_text "Keywords")"
whats_new="$(section_text "What's New")"
review_notes="$(section_text "Review Notes")"
privacy_label="$(section_text "Privacy Nutrition Label Draft")"

echo "== App Store metadata validation =="
echo "File: ${METADATA_FILE}"
echo ""

check_required "App name" "$app_name"
check_required "Subtitle" "$subtitle"
check_required "Promotional Text" "$promo_text"
check_required "Description" "$description"
check_required "Keywords" "$keywords"
check_required "What's New" "$whats_new"
check_required "Review Notes" "$review_notes"
check_required "Privacy Nutrition Label Draft" "$privacy_label"

echo ""
check_max "App name" "$app_name" 30
check_max "Subtitle" "$subtitle" 30
check_max "Promotional Text" "$promo_text" 170
check_max "Description" "$description" 4000
check_max "Keywords" "$keywords" 100
check_max "What's New" "$whats_new" 4000

if grep -Eiq '\b(TODO|TBD|lorem|placeholder)\b' "$METADATA_FILE"; then
  echo "FAIL Placeholder text found"
  failures=$((failures + 1))
else
  echo "OK   No placeholder text found"
fi

if (( failures > 0 )); then
  echo ""
  echo "Metadata validation failed with ${failures} issue(s)."
  exit 1
fi

echo ""
echo "Metadata validation passed."
