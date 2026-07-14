#!/usr/bin/env bash
# terraform `external` data source: resolve an edge provider config's id by name.
#
# Protocol: reads {api_url, api_key, name} on stdin, prints {"id": "..."} on
# stdout. Plan-safe — never exits non-zero; empty id when absent. Secret values
# are never requested nor returned (only the id).
set -euo pipefail

input=$(cat)
api_url=$(printf '%s' "$input" | jq -r '.api_url')
api_key=$(printf '%s' "$input" | jq -r '.api_key')
name=$(printf '%s' "$input" | jq -r '.name')

id=""
resp=$(curl -sS -X POST "$api_url" \
  -H 'Content-Type: application/json' \
  -H "X-API-Key: ${api_key}" \
  --data '{"query":"query { edgeProviderConfigs { id name } }"}' 2>/dev/null) || true
if [ -n "$resp" ]; then
  id=$(printf '%s' "$resp" | jq -r --arg n "$name" \
    'first(.data.edgeProviderConfigs[]? | select(.name == $n) | .id) // ""' 2>/dev/null || echo "")
fi

jq -cn --arg id "$id" '{id: $id}'
