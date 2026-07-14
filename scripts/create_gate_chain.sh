#!/usr/bin/env bash
# Create or update a gate chain config, identified by its scope + transition
# target (gate chains carry no name).
#
# Scope: SCOPE_KIND is tenant | group | lane.
#   group -> laneGroupId (SCOPE_GROUP resolved to its id)
#   lane  -> laneId (SCOPE_LANE within SCOPE_GROUP resolved to its id)
#   tenant-> neither (tenant-wide default)
# Target: IS_ENTRY true -> the entry transition (toStage null); false -> a hop to
#   TO_STAGE (resolved within the scope's group, or tenant default).
#
# STEPS_JSON is a JSON array of steps: [{ mode, conditions: [{ kind, subject?,
#   durationMinutes?, dependencyLane?, dependencyStage? }] }]. DEPENDENCY
#   conditions name another lane + stage; this script resolves those names to
#   dependencyLaneId/dependencyStageId within the chain's group.
#
# Environment: ENDERLANE_API_URL, ENDERLANE_API_KEY, SCOPE_KIND, SCOPE_GROUP
#   (may be empty), SCOPE_LANE (may be empty), IS_ENTRY (true|false), TO_STAGE
#   (may be empty), INITIATION_MODE (MANUAL|AUTO), STEPS_JSON.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
el_require_env
: "${SCOPE_KIND:?SCOPE_KIND is required}"
: "${IS_ENTRY:?IS_ENTRY is required}"
: "${INITIATION_MODE:?INITIATION_MODE is required}"
: "${STEPS_JSON:?STEPS_JSON is required}"
SCOPE_GROUP="${SCOPE_GROUP:-}"
SCOPE_LANE="${SCOPE_LANE:-}"
TO_STAGE="${TO_STAGE:-}"

# Resolve a stage name to an id within the chain's group (override), falling
# back to a tenant-default stage of the same name.
resolve_stage() {
  local group="$1" stage="$2" gid sid
  if [ -n "$group" ]; then
    gid=$(el_find_lane_group_id "$group")
    if [ -n "$gid" ]; then
      sid=$(el_find_stage_id "$gid" "$stage")
      [ -n "$sid" ] && { printf '%s' "$sid"; return 0; }
    fi
  fi
  el_find_tenant_stage_id "$stage"
}

# ── resolve scope id ──
scope_id=""
case "$SCOPE_KIND" in
  group)
    : "${SCOPE_GROUP:?SCOPE_GROUP required for group scope}"
    scope_id=$(el_find_lane_group_id "$SCOPE_GROUP")
    [ -z "$scope_id" ] && { echo "enderlane: lane group '${SCOPE_GROUP}' not found" >&2; exit 1; } ;;
  lane)
    : "${SCOPE_GROUP:?SCOPE_GROUP required for lane scope}"
    : "${SCOPE_LANE:?SCOPE_LANE required for lane scope}"
    scope_id=$(el_find_lane_id "$SCOPE_GROUP" "$SCOPE_LANE")
    [ -z "$scope_id" ] && { echo "enderlane: lane '${SCOPE_LANE}' in '${SCOPE_GROUP}' not found" >&2; exit 1; } ;;
  tenant) scope_id="" ;;
  *) echo "enderlane: invalid SCOPE_KIND '${SCOPE_KIND}'" >&2; exit 1 ;;
esac

# ── resolve target stage ──
to_stage_id=""
if [ "$IS_ENTRY" != "true" ]; then
  : "${TO_STAGE:?TO_STAGE required when IS_ENTRY is false}"
  to_stage_id=$(resolve_stage "$SCOPE_GROUP" "$TO_STAGE")
  [ -z "$to_stage_id" ] && { echo "enderlane: target stage '${TO_STAGE}' not found" >&2; exit 1; }
fi

# ── resolve DEPENDENCY condition name references to ids, build steps ──
steps_out='[]'
n_steps=$(printf '%s' "$STEPS_JSON" | jq 'length')
for ((i = 0; i < n_steps; i++)); do
  step=$(printf '%s' "$STEPS_JSON" | jq -c ".[$i]")
  mode=$(printf '%s' "$step" | jq -r '.mode')
  conds_out='[]'
  n_c=$(printf '%s' "$step" | jq '.conditions | length')
  for ((j = 0; j < n_c; j++)); do
    c=$(printf '%s' "$step" | jq -c ".conditions[$j]")
    kind=$(printf '%s' "$c" | jq -r '.kind')
    if [ "$kind" = "DEPENDENCY" ]; then
      dep_lane=$(printf '%s' "$c" | jq -r '.dependencyLane // ""')
      dep_stage=$(printf '%s' "$c" | jq -r '.dependencyStage // ""')
      dl_id=$(el_find_lane_id "$SCOPE_GROUP" "$dep_lane")
      ds_id=$(resolve_stage "$SCOPE_GROUP" "$dep_stage")
      if [ -z "$dl_id" ] || [ -z "$ds_id" ]; then
        echo "enderlane: DEPENDENCY condition references unknown lane '${dep_lane}' or stage '${dep_stage}' in group '${SCOPE_GROUP}'" >&2
        exit 1
      fi
      cout=$(jq -cn --arg l "$dl_id" --arg s "$ds_id" \
        '{kind: "DEPENDENCY", dependencyLaneId: $l, dependencyStageId: $s}')
    else
      cout=$(printf '%s' "$c" | jq -c \
        '{kind} + (if .subject != null then {subject} else {} end) + (if .durationMinutes != null then {durationMinutes} else {} end)')
    fi
    conds_out=$(printf '%s' "$conds_out" | jq -c --argjson x "$cout" '. + [$x]')
  done
  step_out=$(jq -cn --arg m "$mode" --argjson c "$conds_out" '{mode: $m, conditions: $c}')
  steps_out=$(printf '%s' "$steps_out" | jq -c --argjson x "$step_out" '. + [$x]')
done

# ── find existing by scope + target ──
existing=$(el_find_gate_chain_id "$SCOPE_KIND" "$scope_id" "$IS_ENTRY" "$to_stage_id")

if [ -n "$existing" ]; then
  vars=$(jq -cn --arg id "$existing" '{id: $id}')
  etag=$(el_post_checked 'query($id: ID!) { gateChainConfig(id: $id) { etag } }' "$vars" \
    | jq -r '.data.gateChainConfig.etag // empty')
  input=$(jq -cn --argjson s "$steps_out" --arg im "$INITIATION_MODE" --arg e "$etag" \
    '{steps: $s, initiationMode: $im, etag: $e}')
  uvars=$(jq -cn --arg id "$existing" --argjson input "$input" '{id: $id, input: $input}')
  if ! el_post_checked \
    'mutation($id: ID!, $input: UpdateGateChainConfigInput!) { updateGateChainConfig(id: $id, input: $input) { id } }' \
    "$uvars" >/dev/null; then
    echo "enderlane: failed to update gate chain config (${existing})" >&2
    exit 1
  fi
  echo "gate chain config updated (${existing})"
  exit 0
fi

# ── create ──
input=$(jq -n --argjson entry "$([ "$IS_ENTRY" = "true" ] && echo true || echo false)" \
  --argjson steps "$steps_out" --arg im "$INITIATION_MODE" \
  '{isEntryTransition: $entry, steps: $steps, initiationMode: $im}')
case "$SCOPE_KIND" in
  group) input=$(printf '%s' "$input" | jq --arg g "$scope_id" '. + {laneGroupId: $g}') ;;
  lane)  input=$(printf '%s' "$input" | jq --arg l "$scope_id" '. + {laneId: $l}') ;;
esac
[ "$IS_ENTRY" != "true" ] && input=$(printf '%s' "$input" | jq --arg t "$to_stage_id" '. + {toStageId: $t}')
vars=$(jq -cn --argjson input "$input" '{input: $input}')

if ! el_post_checked \
  'mutation($input: CreateGateChainConfigInput!) { createGateChainConfig(input: $input) { id } }' \
  "$vars" >/dev/null; then
  # Recover: another run may have created it (masked dup) — re-find.
  existing=$(el_find_gate_chain_id "$SCOPE_KIND" "$scope_id" "$IS_ENTRY" "$to_stage_id")
  [ -z "$existing" ] && { echo "enderlane: failed to create gate chain config" >&2; exit 1; }
fi
echo "gate chain config ready (scope=${SCOPE_KIND}, entry=${IS_ENTRY}, toStage=${TO_STAGE:-none})"
