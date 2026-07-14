#!/usr/bin/env bash
# terraform `external` data source: resolve a lane group's id by name.
#
# Protocol: reads a JSON object {api_url, api_key, name} on stdin, prints a JSON
# object {"id": "..."} on stdout. MUST be plan-safe — it never exits non-zero
# and prints an empty id when the group does not exist yet (so `terraform plan`
# before the first apply, and refresh after an out-of-band delete, both work).
set -euo pipefail

input=$(cat)
api_url=$(printf '%s' "$input" | jq -r '.api_url')
api_key=$(printf '%s' "$input" | jq -r '.api_key')
name=$(printf '%s' "$input" | jq -r '.name')

id=""
resp=$(curl -sS -X POST "$api_url" \
  -H 'Content-Type: application/json' \
  -H "X-API-Key: ${api_key}" \
  --data '{"query":"query { laneGroups { id name } }"}' 2>/dev/null) || true
if [ -n "$resp" ]; then
  id=$(printf '%s' "$resp" | jq -r --arg n "$name" \
    'first(.data.laneGroups[]? | select(.name == $n) | .id) // ""' 2>/dev/null || echo "")
fi

jq -cn --arg id "$id" '{id: $id}'
