#!/usr/bin/env bash
# Create or update an edge provider config by name.
#
# Find-or-create by name (v2 has no by-name query). If it already exists we
# UPDATE it, resending every field including secrets — because the API never
# returns secret values (only presence booleans), Terraform cannot detect secret
# drift, so any tracked-field change that re-runs this script resends the secrets
# wholesale. A pure secret rotation with no other change does not re-trigger on
# its own; taint the resource (or change a tracked field) to rotate.
#
# Secrets (CF_API_TOKEN, AWS_SECRET_ACCESS_KEY) arrive ONLY via the environment
# and are never echoed nor placed on a command line.
#
# Environment: ENDERLANE_API_URL, ENDERLANE_API_KEY, NAME, PROVIDER
#   (CLOUDFLARE|CLOUDFRONT); optional CF_ACCOUNT_ID, CF_API_TOKEN,
#   CF_CONFIG_STORE_NS_ID, CFR_REGION, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
el_require_env
: "${NAME:?NAME is required}"
: "${PROVIDER:?PROVIDER is required}"

# Build the input object from whichever fields are set. Secrets read from env,
# never logged. jq --arg keeps every value out of the shell command line.
build_fields() {
  local obj="$1"
  [ -n "${CF_ACCOUNT_ID:-}" ] && obj=$(printf '%s' "$obj" | jq --arg v "$CF_ACCOUNT_ID" '. + {cloudflareAccountId: $v}')
  [ -n "${CF_API_TOKEN:-}" ] && obj=$(printf '%s' "$obj" | jq --arg v "$CF_API_TOKEN" '. + {cloudflareApiToken: $v}')
  [ -n "${CF_CONFIG_STORE_NS_ID:-}" ] && obj=$(printf '%s' "$obj" | jq --arg v "$CF_CONFIG_STORE_NS_ID" '. + {cloudflareConfigStoreNsId: $v}')
  [ -n "${CFR_REGION:-}" ] && obj=$(printf '%s' "$obj" | jq --arg v "$CFR_REGION" '. + {cloudfrontRegion: $v}')
  [ -n "${AWS_ACCESS_KEY_ID:-}" ] && obj=$(printf '%s' "$obj" | jq --arg v "$AWS_ACCESS_KEY_ID" '. + {awsAccessKeyId: $v}')
  [ -n "${AWS_SECRET_ACCESS_KEY:-}" ] && obj=$(printf '%s' "$obj" | jq --arg v "$AWS_SECRET_ACCESS_KEY" '. + {awsSecretAccessKey: $v}')
  printf '%s' "$obj"
}

existing=$(el_find_edge_config_id "$NAME")

if [ -n "$existing" ]; then
  input=$(build_fields "$(jq -n --arg n "$NAME" --arg p "$PROVIDER" '{name: $n, provider: $p}')")
  vars=$(jq -cn --arg id "$existing" --argjson input "$input" '{id: $id, input: $input}')
  if ! el_post_checked \
    'mutation($id: ID!, $input: UpdateEdgeProviderConfigInput!) { updateEdgeProviderConfig(id: $id, input: $input) { id } }' \
    "$vars" >/dev/null; then
    echo "enderlane: failed to update edge provider config '${NAME}'" >&2
    exit 1
  fi
  echo "edge provider config '${NAME}' updated (${existing})"
  exit 0
fi

input=$(build_fields "$(jq -n --arg n "$NAME" --arg p "$PROVIDER" '{name: $n, provider: $p}')")
vars=$(jq -cn --argjson input "$input" '{input: $input}')

id=""
if resp=$(el_post_checked \
  'mutation($input: CreateEdgeProviderConfigInput!) { createEdgeProviderConfig(input: $input) { id name } }' \
  "$vars"); then
  id=$(printf '%s' "$resp" | jq -r '.data.createEdgeProviderConfig.id // empty')
fi

if [ -z "$id" ]; then
  id=$(el_find_edge_config_id "$NAME")
fi

if [ -z "$id" ]; then
  echo "enderlane: failed to create or find edge provider config '${NAME}'" >&2
  exit 1
fi
echo "edge provider config '${NAME}' ready (${id})"
