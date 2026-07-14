#!/usr/bin/env bash
# Soft-delete a tenant field-set preset by name (destroy-time).
#
# Resolves the id among the tenant's own (non-system) presets. Already gone is a
# clean no-op. deleteFieldSetPreset soft-deletes (sets deletedAt; restorable via
# the API). System presets are never matched, so this never touches them.
#
# Environment: ENDERLANE_API_URL, ENDERLANE_API_KEY, NAME.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
el_require_env
: "${NAME:?NAME is required}"

id=$(el_find_field_set_preset_id "$NAME")
if [ -z "$id" ]; then
  echo "field-set preset '${NAME}' not present; nothing to delete"
  exit 0
fi

vars=$(jq -cn --arg id "$id" '{id: $id}')
if ! el_post_checked 'mutation($id: ID!) { deleteFieldSetPreset(id: $id) { id } }' "$vars" >/dev/null; then
  echo "enderlane: failed to delete field-set preset '${NAME}' (${id}); see error above" >&2
  exit 1
fi
echo "field-set preset '${NAME}' soft-deleted (${id})"
