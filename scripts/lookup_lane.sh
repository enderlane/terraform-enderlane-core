#!/usr/bin/env bash
# terraform `external` data source: resolve a lane's id by (group_name, name).
#
# Protocol: reads {api_url, api_key, group_name, name} on stdin, prints
# {"id": "..."} on stdout. Plan-safe — never exits non-zero; empty id when the
# lane does not exist yet.
set -euo pipefail

input=$(cat)
api_url=$(printf '%s' "$input" | jq -r '.api_url')
api_key=$(printf '%s' "$input" | jq -r '.api_key')
group_name=$(printf '%s' "$input" | jq -r '.group_name')
name=$(printf '%s' "$input" | jq -r '.name')

id=""
resp=$(curl -sS -X POST "$api_url" \
  -H 'Content-Type: application/json' \
  -H "X-API-Key: ${api_key}" \
  --data '{"query":"query { lanes { id name group { id name } } }"}' 2>/dev/null) || true
if [ -n "$resp" ]; then
  id=$(printf '%s' "$resp" | jq -r --arg g "$group_name" --arg n "$name" \
    'first(.data.lanes[]? | select(.group.name == $g and .name == $n) | .id) // ""' 2>/dev/null || echo "")
fi

jq -cn --arg id "$id" '{id: $id}'
