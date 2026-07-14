#!/usr/bin/env bash
# Clear a unit-kind → field-set-preset mapping at its scope (destroy-time),
# letting resolution fall through to the next level (lane -> group -> tenant ->
# system default).
#
# Environment: ENDERLANE_API_URL, ENDERLANE_API_KEY, KIND, SCOPE_GROUP (may be
#   empty), SCOPE_LANE (may be empty).
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
el_require_env
: "${KIND:?KIND is required}"
SCOPE_GROUP="${SCOPE_GROUP:-}"
SCOPE_LANE="${SCOPE_LANE:-}"

input=$(jq -n --arg k "$KIND" '{kind: $k}')
if [ -n "$SCOPE_LANE" ]; then
  lane_id=$(el_find_lane_id "$SCOPE_GROUP" "$SCOPE_LANE")
  if [ -z "$lane_id" ]; then
    echo "lane '${SCOPE_LANE}' in '${SCOPE_GROUP}' not present; mapping already gone"
    exit 0
  fi
  input=$(printf '%s' "$input" | jq --arg l "$lane_id" '. + {laneId: $l}')
elif [ -n "$SCOPE_GROUP" ]; then
  group_id=$(el_find_lane_group_id "$SCOPE_GROUP")
  if [ -z "$group_id" ]; then
    echo "lane group '${SCOPE_GROUP}' not present; mapping already gone"
    exit 0
  fi
  input=$(printf '%s' "$input" | jq --arg g "$group_id" '. + {laneGroupId: $g}')
fi
vars=$(jq -cn --argjson input "$input" '{input: $input}')

if ! el_post_checked \
  'mutation($input: ClearUnitKindFieldSetInput!) { clearUnitKindFieldSet(input: $input) { kind configured } }' \
  "$vars" >/dev/null; then
  echo "enderlane: failed to clear unit-kind field set (${KIND}); see error above" >&2
  exit 1
fi
echo "unit-kind field set cleared (${KIND}, scope=${SCOPE_LANE:-${SCOPE_GROUP:-tenant}})"
