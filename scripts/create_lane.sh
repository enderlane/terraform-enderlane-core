#!/usr/bin/env bash
# Create (or adopt) a lane by name within its lane group.
#
# The owning group is resolved by name at run time — the group's null_resource
# is created first (module dependency ordering), so the lookup succeeds. Same
# find-or-create + masked-dup recovery as create_lane_group.sh.
#
# Environment: ENDERLANE_API_URL, ENDERLANE_API_KEY, GROUP_NAME, NAME,
#   DESCRIPTION (may be empty), DEPLOYMENT_TYPE (may be empty).
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
el_require_env
: "${GROUP_NAME:?GROUP_NAME is required}"
: "${NAME:?NAME is required}"

group_id=$(el_find_lane_group_id "$GROUP_NAME")
if [ -z "$group_id" ]; then
  echo "enderlane: lane group '${GROUP_NAME}' not found; cannot create lane '${NAME}'" >&2
  exit 1
fi

existing=$(el_find_lane_id "$GROUP_NAME" "$NAME")
if [ -n "$existing" ]; then
  echo "lane '${NAME}' already exists in '${GROUP_NAME}' (${existing}); adopting"
  exit 0
fi

input=$(jq -n --arg name "$NAME" --arg gid "$group_id" '{name: $name, laneGroupId: $gid}')
if [ -n "${DESCRIPTION:-}" ]; then
  input=$(printf '%s' "$input" | jq --arg d "$DESCRIPTION" '. + {description: $d}')
fi
if [ -n "${DEPLOYMENT_TYPE:-}" ]; then
  input=$(printf '%s' "$input" | jq --arg t "$DEPLOYMENT_TYPE" '. + {deploymentType: $t}')
fi
vars=$(jq -cn --argjson input "$input" '{input: $input}')

id=""
if resp=$(el_post_checked \
  'mutation($input: CreateLaneInput!) { createLane(input: $input) { id name } }' \
  "$vars"); then
  id=$(printf '%s' "$resp" | jq -r '.data.createLane.id // empty')
fi

if [ -z "$id" ]; then
  id=$(el_find_lane_id "$GROUP_NAME" "$NAME")
fi

if [ -z "$id" ]; then
  echo "enderlane: failed to create or find lane '${NAME}' in '${GROUP_NAME}'" >&2
  exit 1
fi
echo "lane '${NAME}' ready (${id})"
