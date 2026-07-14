#!/usr/bin/env bash
# terraform `external` data source: resolve a stage's id by (group_name, name).
# group_name empty -> a tenant-default stage (applicationGroupId IS NULL);
# group_name set -> a group override (applicationGroupId == the group id).
#
# Protocol: reads {api_url, api_key, group_name, name} on stdin, prints
# {"id": "..."} on stdout. Plan-safe — never exits non-zero; empty id when the
# group or stage does not exist yet.
set -euo pipefail

input=$(cat)
api_url=$(printf '%s' "$input" | jq -r '.api_url')
api_key=$(printf '%s' "$input" | jq -r '.api_key')
group_name=$(printf '%s' "$input" | jq -r '.group_name // ""')
name=$(printf '%s' "$input" | jq -r '.name')

post() {
  curl -sS -X POST "$api_url" \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: ${api_key}" \
    --data "$1" 2>/dev/null || true
}

id=""
if [ -n "$group_name" ]; then
  group_resp=$(post '{"query":"query { laneGroups { id name } }"}')
  group_id=""
  if [ -n "$group_resp" ]; then
    group_id=$(printf '%s' "$group_resp" | jq -r --arg n "$group_name" \
      'first(.data.laneGroups[]? | select(.name == $n) | .id) // ""' 2>/dev/null || echo "")
  fi
  if [ -n "$group_id" ]; then
    q=$(jq -cn --arg gid "$group_id" \
      '{query: "query($gid: ID!) { stages(applicationGroupId: $gid) { id name applicationGroupId } }", variables: {gid: $gid}}')
    stage_resp=$(post "$q")
    if [ -n "$stage_resp" ]; then
      id=$(printf '%s' "$stage_resp" | jq -r --arg gid "$group_id" --arg n "$name" \
        'first(.data.stages[]? | select(.name == $n and .applicationGroupId == $gid) | .id) // ""' 2>/dev/null || echo "")
    fi
  fi
else
  stage_resp=$(post '{"query":"query { stages { id name applicationGroupId } }"}')
  if [ -n "$stage_resp" ]; then
    id=$(printf '%s' "$stage_resp" | jq -r --arg n "$name" \
      'first(.data.stages[]? | select(.name == $n and .applicationGroupId == null) | .id) // ""' 2>/dev/null || echo "")
  fi
fi

jq -cn --arg id "$id" '{id: $id}'
