#!/usr/bin/env bash
# Create or update a field-set preset by name.
#
# Find-or-create by name among the tenant's OWN presets (system/seeded presets
# — "Build", "Config version" — are excluded: they are immutable and shared, so
# never name a managed preset after one). If the preset exists we update it so
# field changes apply; otherwise we create it.
#
# FIELDS_JSON is a JSON array of field objects in GraphQL shape
# ({name, required, description?, allowedValues?}); null-valued keys are stripped
# so omitted optionals are truly absent. Field ORDER is preserved as given.
#
# Environment: ENDERLANE_API_URL, ENDERLANE_API_KEY, NAME, DESCRIPTION (may be
#   empty), FIELDS_JSON.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
el_require_env
: "${NAME:?NAME is required}"
: "${FIELDS_JSON:?FIELDS_JSON is required}"

fields=$(printf '%s' "$FIELDS_JSON" | jq 'map(with_entries(select(.value != null)))')

existing=$(el_find_field_set_preset_id "$NAME")

if [ -n "$existing" ]; then
  input=$(jq -n --arg id "$existing" --argjson f "$fields" '{id: $id, fields: $f}')
  [ -n "${DESCRIPTION:-}" ] && input=$(printf '%s' "$input" | jq --arg d "$DESCRIPTION" '. + {description: $d}')
  vars=$(jq -cn --argjson input "$input" '{input: $input}')
  if ! el_post_checked \
    'mutation($input: UpdateFieldSetPresetInput!) { updateFieldSetPreset(input: $input) { id } }' \
    "$vars" >/dev/null; then
    echo "enderlane: failed to update field-set preset '${NAME}'" >&2
    exit 1
  fi
  echo "field-set preset '${NAME}' updated (${existing})"
  exit 0
fi

input=$(jq -n --arg n "$NAME" --argjson f "$fields" '{name: $n, fields: $f}')
[ -n "${DESCRIPTION:-}" ] && input=$(printf '%s' "$input" | jq --arg d "$DESCRIPTION" '. + {description: $d}')
vars=$(jq -cn --argjson input "$input" '{input: $input}')

id=""
if resp=$(el_post_checked \
  'mutation($input: CreateFieldSetPresetInput!) { createFieldSetPreset(input: $input) { id name } }' \
  "$vars"); then
  id=$(printf '%s' "$resp" | jq -r '.data.createFieldSetPreset.id // empty')
fi

if [ -z "$id" ]; then
  id=$(el_find_field_set_preset_id "$NAME")
fi

if [ -z "$id" ]; then
  echo "enderlane: failed to create or find field-set preset '${NAME}'" >&2
  exit 1
fi
echo "field-set preset '${NAME}' ready (${id})"
