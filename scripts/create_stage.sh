#!/usr/bin/env bash
# Create (or adopt) a stage by name, at one of two levels:
#   - GROUP_NAME set   -> a GROUP OVERRIDE: applicationGroupId = the group's id,
#     an ordered progression owned by (overriding for) that lane group.
#   - GROUP_NAME empty -> a TENANT DEFAULT: applicationGroupId omitted, joining
#     the shared tenant-default progression.
# A LaneGroup IS the ApplicationGroup (same entity, same id). The owning group,
# when named, is resolved by name at run time.
#
# Environment: ENDERLANE_API_URL, ENDERLANE_API_KEY, GROUP_NAME (may be empty),
#   NAME, ORDER_INDEX, KV_PREFIX (may be empty), DESCRIPTION (may be empty).
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
el_require_env
: "${NAME:?NAME is required}"
: "${ORDER_INDEX:?ORDER_INDEX is required}"
GROUP_NAME="${GROUP_NAME:-}"

group_id=""
if [ -n "$GROUP_NAME" ]; then
  group_id=$(el_find_lane_group_id "$GROUP_NAME")
  if [ -z "$group_id" ]; then
    echo "enderlane: lane group '${GROUP_NAME}' not found; cannot create stage '${NAME}'" >&2
    exit 1
  fi
  scope_label="group '${GROUP_NAME}'"
else
  scope_label="tenant default"
fi

find_id() {
  if [ -n "$group_id" ]; then el_find_stage_id "$group_id" "$NAME"; else el_find_tenant_stage_id "$NAME"; fi
}

existing=$(find_id)
if [ -n "$existing" ]; then
  echo "stage '${NAME}' already exists (${scope_label}, ${existing}); adopting"
  exit 0
fi

input=$(jq -n --arg name "$NAME" --argjson oi "$ORDER_INDEX" '{name: $name, orderIndex: $oi}')
if [ -n "$group_id" ]; then
  input=$(printf '%s' "$input" | jq --arg gid "$group_id" '. + {applicationGroupId: $gid}')
fi
if [ -n "${KV_PREFIX:-}" ]; then
  input=$(printf '%s' "$input" | jq --arg k "$KV_PREFIX" '. + {kvPrefix: $k}')
fi
if [ -n "${DESCRIPTION:-}" ]; then
  input=$(printf '%s' "$input" | jq --arg d "$DESCRIPTION" '. + {description: $d}')
fi
vars=$(jq -cn --argjson input "$input" '{input: $input}')

id=""
if resp=$(el_post_checked \
  'mutation($input: CreateStageInput!) { createStage(input: $input) { id name } }' \
  "$vars"); then
  id=$(printf '%s' "$resp" | jq -r '.data.createStage.id // empty')
fi

if [ -z "$id" ]; then
  id=$(find_id)
fi

if [ -z "$id" ]; then
  echo "enderlane: failed to create or find stage '${NAME}' (${scope_label})" >&2
  exit 1
fi
echo "stage '${NAME}' ready (${scope_label}, ${id})"
