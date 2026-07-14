#!/usr/bin/env bash
# Map a unit kind (BUILD|CONFIG) to a field-set preset at a chosen scope.
#
# Scope: SCOPE_GROUP set -> a lane-group override (laneGroupId); SCOPE_LANE set
# (within SCOPE_GROUP) -> a lane override (laneId); neither -> tenant-wide.
# Naming both a group and a lane is refused by the API (scope exclusivity).
# configureUnitKindFieldSet is an upsert, so this is naturally idempotent.
#
# PRESET names the target preset; it may be one of the tenant's own presets or a
# seeded system preset ("Build" / "Config version").
#
# Environment: ENDERLANE_API_URL, ENDERLANE_API_KEY, KIND, PRESET, SCOPE_GROUP
#   (may be empty), SCOPE_LANE (may be empty).
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
el_require_env
: "${KIND:?KIND is required}"
: "${PRESET:?PRESET is required}"
SCOPE_GROUP="${SCOPE_GROUP:-}"
SCOPE_LANE="${SCOPE_LANE:-}"

# Resolve a preset by name across tenant + system presets (prefer a tenant
# preset when a name collides).
resolve_preset_id() {
  local name="$1" resp
  resp=$(el_post_checked 'query { fieldSetPresets { id name system } }') || return 1
  printf '%s' "$resp" | jq -r --arg n "$name" '
    [.data.fieldSetPresets[]? | select(.name == $n)] as $m
    | ( ($m[] | select(.system == false) | .id)
        // ($m[0].id) // empty )' | head -n1
}

preset_id=$(resolve_preset_id "$PRESET")
if [ -z "$preset_id" ]; then
  echo "enderlane: field-set preset '${PRESET}' not found" >&2
  exit 1
fi

input=$(jq -n --arg k "$KIND" --arg p "$preset_id" '{kind: $k, presetId: $p}')
if [ -n "$SCOPE_LANE" ]; then
  lane_id=$(el_find_lane_id "$SCOPE_GROUP" "$SCOPE_LANE")
  [ -z "$lane_id" ] && { echo "enderlane: lane '${SCOPE_LANE}' in '${SCOPE_GROUP}' not found" >&2; exit 1; }
  input=$(printf '%s' "$input" | jq --arg l "$lane_id" '. + {laneId: $l}')
elif [ -n "$SCOPE_GROUP" ]; then
  group_id=$(el_find_lane_group_id "$SCOPE_GROUP")
  [ -z "$group_id" ] && { echo "enderlane: lane group '${SCOPE_GROUP}' not found" >&2; exit 1; }
  input=$(printf '%s' "$input" | jq --arg g "$group_id" '. + {laneGroupId: $g}')
fi
vars=$(jq -cn --argjson input "$input" '{input: $input}')

if ! el_post_checked \
  'mutation($input: ConfigureUnitKindFieldSetInput!) { configureUnitKindFieldSet(input: $input) { kind configured } }' \
  "$vars" >/dev/null; then
  echo "enderlane: failed to configure unit-kind field set (${KIND} -> ${PRESET})" >&2
  exit 1
fi
echo "unit-kind field set configured (${KIND} -> ${PRESET}, scope=${SCOPE_LANE:-${SCOPE_GROUP:-tenant}})"
