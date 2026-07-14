#!/usr/bin/env bash
# Set the tenant's default edge provider config (by name).
#
# The tenant id is the ambient API-key caller's tenant. The edge config is
# resolved by name to its id. Idempotent: setting the same default again is a
# no-op on the server.
#
# Environment: ENDERLANE_API_URL, ENDERLANE_API_KEY, EDGE_CONFIG (name).
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
el_require_env
: "${EDGE_CONFIG:?EDGE_CONFIG is required}"

tenant_id=$(el_tenant_id)
[ -z "$tenant_id" ] && { echo "enderlane: could not resolve tenant id" >&2; exit 1; }

ec_id=$(el_find_edge_config_id "$EDGE_CONFIG")
[ -z "$ec_id" ] && { echo "enderlane: edge provider config '${EDGE_CONFIG}' not found" >&2; exit 1; }

vars=$(jq -cn --arg t "$tenant_id" --arg e "$ec_id" '{t: $t, e: $e}')
if ! el_post_checked \
  'mutation($t: ID!, $e: ID) { setTenantDefaultEdgeProviderConfig(tenantId: $t, edgeProviderConfigId: $e) { id defaultEdgeProviderConfigId } }' \
  "$vars" >/dev/null; then
  echo "enderlane: failed to set tenant default edge provider config to '${EDGE_CONFIG}'" >&2
  exit 1
fi
echo "tenant default edge provider config set to '${EDGE_CONFIG}' (${ec_id})"
