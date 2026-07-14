#!/usr/bin/env bash
# Soft-delete a stage by name (destroy-time), at group-override level
# (GROUP_NAME set) or tenant-default level (GROUP_NAME empty).
#
# A stage already gone is a clean no-op. deleteStage refuses while a lane
# currently declares a unit at the stage — that refusal is surfaced verbatim as
# an error rather than masked, so an operator sees why the destroy could not
# complete.
#
# Environment: ENDERLANE_API_URL, ENDERLANE_API_KEY, GROUP_NAME (may be empty), NAME.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
el_require_env
: "${NAME:?NAME is required}"
GROUP_NAME="${GROUP_NAME:-}"

if [ -n "$GROUP_NAME" ]; then
  group_id=$(el_find_lane_group_id "$GROUP_NAME")
  if [ -z "$group_id" ]; then
    echo "lane group '${GROUP_NAME}' not present; stage '${NAME}' cannot exist, nothing to delete"
    exit 0
  fi
  id=$(el_find_stage_id "$group_id" "$NAME")
  scope_label="group '${GROUP_NAME}'"
else
  id=$(el_find_tenant_stage_id "$NAME")
  scope_label="tenant default"
fi

if [ -z "$id" ]; then
  echo "stage '${NAME}' (${scope_label}) not present; nothing to delete"
  exit 0
fi

vars=$(jq -cn --arg id "$id" '{id: $id}')
if ! el_post_checked 'mutation($id: ID!) { deleteStage(id: $id) }' "$vars" >/dev/null; then
  echo "enderlane: refused to delete stage '${NAME}' (${id}) — a lane may still declare a unit here; see error above" >&2
  exit 1
fi
echo "stage '${NAME}' soft-deleted (${scope_label}, ${id})"
