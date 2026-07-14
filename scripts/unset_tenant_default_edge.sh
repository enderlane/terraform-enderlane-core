#!/usr/bin/env bash
# Clear the tenant's default edge provider config (destroy-time): passes a null
# edgeProviderConfigId. If the tenant is already unresolvable this is a no-op.
#
# Environment: ENDERLANE_API_URL, ENDERLANE_API_KEY.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
el_require_env

tenant_id=$(el_tenant_id) || true
if [ -z "$tenant_id" ]; then
  echo "tenant not resolvable; nothing to clear"
  exit 0
fi

vars=$(jq -cn --arg t "$tenant_id" '{t: $t}')
if ! el_post_checked \
  'mutation($t: ID!) { setTenantDefaultEdgeProviderConfig(tenantId: $t, edgeProviderConfigId: null) { id defaultEdgeProviderConfigId } }' \
  "$vars" >/dev/null; then
  echo "enderlane: failed to clear tenant default edge provider config; see error above" >&2
  exit 1
fi
echo "tenant default edge provider config cleared"
