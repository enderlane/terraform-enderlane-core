#!/usr/bin/env bash
# terraform `external` data source: resolve a tenant field-set preset's id by
# name (system presets excluded).
#
# Protocol: reads {api_url, api_key, name} on stdin, prints {"id": "..."} on
# stdout. Plan-safe — never exits non-zero; empty id when absent.
set -euo pipefail

input=$(cat)
api_url=$(printf '%s' "$input" | jq -r '.api_url')
api_key=$(printf '%s' "$input" | jq -r '.api_key')
name=$(printf '%s' "$input" | jq -r '.name')

id=""
resp=$(curl -sS -X POST "$api_url" \
  -H 'Content-Type: application/json' \
  -H "X-API-Key: ${api_key}" \
  --data '{"query":"query { fieldSetPresets { id name system } }"}' 2>/dev/null) || true
if [ -n "$resp" ]; then
  id=$(printf '%s' "$resp" | jq -r --arg n "$name" \
    'first(.data.fieldSetPresets[]? | select(.name == $n and .system == false) | .id) // ""' 2>/dev/null || echo "")
fi

jq -cn --arg id "$id" '{id: $id}'
