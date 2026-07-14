#!/usr/bin/env bash
# Create (or adopt, if it already exists) a lane group by name.
#
# Idempotency: v2 has no by-name query, so we list-and-filter. If the group
# already exists we adopt it; only when it is absent do we create it. The
# backend masks a duplicate-name create as a generic "Unexpected Execution
# Error" (END-85), so on any create failure we re-list by name and adopt a
# group that appeared — never matching on error text.
#
# Environment: ENDERLANE_API_URL, ENDERLANE_API_KEY, NAME, KV_NAMESPACE_ID (may
#   be empty), EDGE_CONFIG (may be empty — name of an edge provider config to
#   bind this group to; resolved to its id, and the group's provider is set to
#   match the referenced config's provider).
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
el_require_env
: "${NAME:?NAME is required}"

existing=$(el_find_lane_group_id "$NAME")
if [ -n "$existing" ]; then
  echo "lane group '${NAME}' already exists (${existing}); adopting"
  exit 0
fi

input=$(jq -n --arg name "$NAME" '{name: $name}')
if [ -n "${KV_NAMESPACE_ID:-}" ]; then
  input=$(printf '%s' "$input" | jq --arg kv "$KV_NAMESPACE_ID" '. + {kvNamespaceId: $kv}')
fi
if [ -n "${EDGE_CONFIG:-}" ]; then
  ec_id=$(el_find_edge_config_id "$EDGE_CONFIG")
  if [ -z "$ec_id" ]; then
    echo "enderlane: edge provider config '${EDGE_CONFIG}' not found; cannot bind lane group '${NAME}'" >&2
    exit 1
  fi
  ec_provider=$(el_edge_config_provider "$EDGE_CONFIG")
  input=$(printf '%s' "$input" | jq --arg e "$ec_id" --arg p "$ec_provider" \
    '. + {edgeProviderConfigId: $e, provider: $p}')
fi
vars=$(jq -cn --argjson input "$input" '{input: $input}')

id=""
if resp=$(el_post_checked \
  'mutation($input: CreateLaneGroupInput!) { createLaneGroup(input: $input) { id name } }' \
  "$vars"); then
  id=$(printf '%s' "$resp" | jq -r '.data.createLaneGroup.id // empty')
fi

if [ -z "$id" ]; then
  # Create reported nothing usable — recover by list-lookup (masked-dup path).
  id=$(el_find_lane_group_id "$NAME")
fi

if [ -z "$id" ]; then
  echo "enderlane: failed to create or find lane group '${NAME}'" >&2
  exit 1
fi
echo "lane group '${NAME}' ready (${id})"
