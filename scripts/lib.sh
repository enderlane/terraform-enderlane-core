# shellcheck shell=bash
# Shared helpers for the Enderlane tenant Terraform module (v0).
#
# Every script that talks to the Enderlane GraphQL v2 API sources this file.
# The API key is read from the ENDERLANE_API_KEY environment variable and is
# NEVER written to stdout/stderr or interpolated onto a command line. Edge
# provider secrets are likewise passed only through the environment.
#
# Required environment for the GraphQL helpers:
#   ENDERLANE_API_URL   the GraphQL endpoint (e.g. https://app.enderlane.com/graphql)
#   ENDERLANE_API_KEY   the machine key, sent as the X-API-Key header
#
# Idempotency: the v2 API has no by-name lookups, so every "find" here lists the
# entities and filters with jq. That is the module's idempotency mechanism, and
# the recovery path for the backend's masked duplicate-name error (END-85): on a
# failed create we re-list and adopt whatever appeared, never matching on error
# text.

# Post a GraphQL operation. $1 = query string, $2 = variables JSON (default {}).
# Prints the raw HTTP response body on stdout. Returns curl's exit status.
el_post() {
  local query="$1" vars="${2-}" payload
  [ -z "$vars" ] && vars='{}'
  payload=$(jq -cn --arg q "$query" --argjson v "$vars" '{query: $q, variables: $v}')
  curl -sS --fail-with-body \
    -X POST "$ENDERLANE_API_URL" \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: ${ENDERLANE_API_KEY}" \
    --data "$payload"
}

# Post and enforce that the response carries no GraphQL "errors" array.
# On a GraphQL error prints a readable message to stderr and returns 1.
# On success prints the response body on stdout.
el_post_checked() {
  local resp
  if ! resp=$(el_post "$1" "${2-}"); then
    echo "enderlane: HTTP request failed against ${ENDERLANE_API_URL}" >&2
    return 1
  fi
  if printf '%s' "$resp" | jq -e '.errors' >/dev/null 2>&1; then
    echo "enderlane: GraphQL error: $(printf '%s' "$resp" | jq -c '.errors')" >&2
    return 1
  fi
  printf '%s' "$resp"
}

el_require_env() {
  : "${ENDERLANE_API_URL:?ENDERLANE_API_URL is required}"
  : "${ENDERLANE_API_KEY:?ENDERLANE_API_KEY is required}"
}

# ── name → id finders ────────────────────────────────────────────────────────

# The ambient tenant's id (the API-key caller's tenant). Prints the id.
el_tenant_id() {
  local resp
  resp=$(el_post_checked 'query { tenants { id } }') || return 1
  printf '%s' "$resp" | jq -r 'first(.data.tenants[]?.id) // empty'
}

el_find_edge_config_id() {
  local name="$1" resp
  resp=$(el_post_checked 'query { edgeProviderConfigs { id name } }') || return 1
  printf '%s' "$resp" | jq -r --arg n "$name" \
    'first(.data.edgeProviderConfigs[]? | select(.name == $n) | .id) // empty'
}

# Prints the edge config's provider enum (CLOUDFLARE / CLOUDFRONT) for a name.
el_edge_config_provider() {
  local name="$1" resp
  resp=$(el_post_checked 'query { edgeProviderConfigs { name provider } }') || return 1
  printf '%s' "$resp" | jq -r --arg n "$name" \
    'first(.data.edgeProviderConfigs[]? | select(.name == $n) | .provider) // empty'
}

el_find_lane_group_id() {
  local name="$1" resp
  resp=$(el_post_checked 'query { laneGroups { id name } }') || return 1
  printf '%s' "$resp" | jq -r --arg n "$name" \
    'first(.data.laneGroups[]? | select(.name == $n) | .id) // empty'
}

el_find_lane_id() {
  local group_name="$1" lane_name="$2" resp
  resp=$(el_post_checked 'query { lanes { id name group { id name } } }') || return 1
  printf '%s' "$resp" | jq -r --arg g "$group_name" --arg n "$lane_name" \
    'first(.data.lanes[]? | select(.group.name == $g and .name == $n) | .id) // empty'
}

# A group-scoped stage (override), matched by (group id, name).
el_find_stage_id() {
  local group_id="$1" stage_name="$2" resp vars
  vars=$(jq -cn --arg gid "$group_id" '{gid: $gid}')
  resp=$(el_post_checked \
    'query($gid: ID!) { stages(applicationGroupId: $gid) { id name applicationGroupId } }' \
    "$vars") || return 1
  printf '%s' "$resp" | jq -r --arg gid "$group_id" --arg n "$stage_name" \
    'first(.data.stages[]? | select(.name == $n and .applicationGroupId == $gid) | .id) // empty'
}

# A tenant-default stage, matched by name (applicationGroupId IS NULL).
el_find_tenant_stage_id() {
  local stage_name="$1" resp
  resp=$(el_post_checked 'query { stages { id name applicationGroupId } }') || return 1
  printf '%s' "$resp" | jq -r --arg n "$stage_name" \
    'first(.data.stages[]? | select(.name == $n and .applicationGroupId == null) | .id) // empty'
}

# Resolve a stage by name at whichever level applies: if GROUP is non-empty, a
# group override; otherwise a tenant default. Prints the id (empty if absent).
el_resolve_stage_id() {
  local group_name="$1" stage_name="$2" gid
  if [ -n "$group_name" ]; then
    gid=$(el_find_lane_group_id "$group_name") || return 1
    [ -z "$gid" ] && { echo ""; return 0; }
    el_find_stage_id "$gid" "$stage_name"
  else
    el_find_tenant_stage_id "$stage_name"
  fi
}

# A tenant-created field-set preset, matched by name. System (seeded) presets
# are EXCLUDED — they are immutable and shared across tenants, never adopted or
# managed by this module.
el_find_field_set_preset_id() {
  local name="$1" resp
  resp=$(el_post_checked 'query { fieldSetPresets { id name system } }') || return 1
  printf '%s' "$resp" | jq -r --arg n "$name" \
    'first(.data.fieldSetPresets[]? | select(.name == $n and .system == false) | .id) // empty'
}

# A gate chain config, matched by its identity: scope (SCOPE_KIND one of
# "group"/"lane"/"tenant" + SCOPE_ID) plus the transition target (IS_ENTRY
# "true"/"false" + TO_STAGE_ID, empty for entry). Prints the id.
# Note: the backend's GateChainConfig.laneGroup/lane/toStage nested selections
# return an id but an EMPTY name, so this matches strictly on ids.
el_find_gate_chain_id() {
  local scope_kind="$1" scope_id="$2" is_entry="$3" to_stage_id="$4" resp
  resp=$(el_post_checked \
    'query { gateChainConfigs { id isEntryTransition toStage { id } laneGroup { id } lane { id } } }') || return 1
  printf '%s' "$resp" | jq -r \
    --arg sk "$scope_kind" --arg sid "$scope_id" \
    --arg entry "$is_entry" --arg ts "$to_stage_id" \
    '
    def scope_ok:
      if $sk == "group" then (.laneGroup.id == $sid and .lane == null)
      elif $sk == "lane" then (.lane.id == $sid)
      else (.laneGroup == null and .lane == null) end;
    def target_ok:
      if $entry == "true" then (.isEntryTransition == true)
      else (.isEntryTransition == false and (.toStage.id // "") == $ts) end;
    first(.data.gateChainConfigs[]? | select(scope_ok and target_ok) | .id) // empty
    '
}
