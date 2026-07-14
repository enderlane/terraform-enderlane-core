#!/usr/bin/env bash
# terraform `external` data source: resolve a gate chain config's id by
# scope + transition target.
#
# Protocol: reads {api_url, api_key, scope_kind, scope_group, scope_lane,
# is_entry, to_stage} on stdin, prints {"id": "..."} on stdout. Plan-safe —
# never exits non-zero; empty id when absent (matches strictly on ids, because
# the backend returns empty names on GateChainConfig's nested selections).
set -euo pipefail

input=$(cat)
api_url=$(printf '%s' "$input" | jq -r '.api_url')
api_key=$(printf '%s' "$input" | jq -r '.api_key')
scope_kind=$(printf '%s' "$input" | jq -r '.scope_kind')
scope_group=$(printf '%s' "$input" | jq -r '.scope_group // ""')
scope_lane=$(printf '%s' "$input" | jq -r '.scope_lane // ""')
is_entry=$(printf '%s' "$input" | jq -r '.is_entry')
to_stage=$(printf '%s' "$input" | jq -r '.to_stage // ""')

post() {
  curl -sS -X POST "$api_url" -H 'Content-Type: application/json' \
    -H "X-API-Key: ${api_key}" --data "$1" 2>/dev/null || true
}
jqr() { printf '%s' "$1" | jq -r "$2" 2>/dev/null || echo ""; }

id=""

# Resolve scope id.
scope_id=""
case "$scope_kind" in
  group)
    r=$(post '{"query":"query { laneGroups { id name } }"}')
    scope_id=$(jqr "$r" "$(printf 'first(.data.laneGroups[]? | select(.name == \"%s\") | .id) // ""' "$scope_group")") ;;
  lane)
    r=$(post '{"query":"query { lanes { id name group { name } } }"}')
    scope_id=$(jqr "$r" "$(printf 'first(.data.lanes[]? | select(.group.name == \"%s\" and .name == \"%s\") | .id) // ""' "$scope_group" "$scope_lane")") ;;
esac

# Resolve target stage id (group override, else tenant default).
to_stage_id=""
if [ "$is_entry" != "true" ] && [ -n "$to_stage" ]; then
  if [ -n "$scope_group" ] && [ -n "$scope_id" ] && [ "$scope_kind" = "group" ]; then
    q=$(jq -cn --arg gid "$scope_id" '{query:"query($gid:ID!){stages(applicationGroupId:$gid){id name applicationGroupId}}",variables:{gid:$gid}}')
    r=$(post "$q")
    to_stage_id=$(jqr "$r" "$(printf 'first(.data.stages[]? | select(.name == \"%s\") | .id) // ""' "$to_stage")")
  fi
  if [ -z "$to_stage_id" ]; then
    r=$(post '{"query":"query { stages { id name applicationGroupId } }"}')
    to_stage_id=$(jqr "$r" "$(printf 'first(.data.stages[]? | select(.name == \"%s\" and .applicationGroupId == null) | .id) // ""' "$to_stage")")
  fi
fi

# Match a gate chain config by scope + target on ids only.
r=$(post '{"query":"query { gateChainConfigs { id isEntryTransition toStage { id } laneGroup { id } lane { id } } }"}')
if [ -n "$r" ]; then
  id=$(printf '%s' "$r" | jq -r \
    --arg sk "$scope_kind" --arg sid "$scope_id" --arg entry "$is_entry" --arg ts "$to_stage_id" \
    '
    def scope_ok:
      if $sk == "group" then (.laneGroup.id == $sid and .lane == null)
      elif $sk == "lane" then (.lane.id == $sid)
      else (.laneGroup == null and .lane == null) end;
    def target_ok:
      if $entry == "true" then (.isEntryTransition == true)
      else (.isEntryTransition == false and (.toStage.id // "") == $ts) end;
    first(.data.gateChainConfigs[]? | select(scope_ok and target_ok) | .id) // ""
    ' 2>/dev/null || echo "")
fi

jq -cn --arg id "$id" '{id: $id}'
