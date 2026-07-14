#!/usr/bin/env bash
# Soft-delete a gate chain config (destroy-time), identified by scope + target.
#
# Terraform destroys gate chains before the groups/lanes/stages they reference
# (dependency ordering), so those names still resolve here. Already gone is a
# clean no-op. deleteGateChainConfig soft-deletes (sets deletedAt; restorable).
#
# Environment: ENDERLANE_API_URL, ENDERLANE_API_KEY, SCOPE_KIND, SCOPE_GROUP
#   (may be empty), SCOPE_LANE (may be empty), IS_ENTRY (true|false), TO_STAGE
#   (may be empty).
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
el_require_env
: "${SCOPE_KIND:?SCOPE_KIND is required}"
: "${IS_ENTRY:?IS_ENTRY is required}"
SCOPE_GROUP="${SCOPE_GROUP:-}"
SCOPE_LANE="${SCOPE_LANE:-}"
TO_STAGE="${TO_STAGE:-}"

scope_id=""
case "$SCOPE_KIND" in
  group) scope_id=$(el_find_lane_group_id "$SCOPE_GROUP") ;;
  lane)  scope_id=$(el_find_lane_id "$SCOPE_GROUP" "$SCOPE_LANE") ;;
  tenant) scope_id="" ;;
esac

to_stage_id=""
if [ "$IS_ENTRY" != "true" ] && [ -n "$TO_STAGE" ]; then
  to_stage_id=$(el_resolve_stage_id "$SCOPE_GROUP" "$TO_STAGE")
  if [ -z "$to_stage_id" ] && [ -n "$SCOPE_GROUP" ]; then
    to_stage_id=$(el_find_tenant_stage_id "$TO_STAGE")
  fi
fi

# For a non-tenant scope whose group/lane is already gone, the chain cannot be
# matched (and was likely cascaded); treat as a no-op.
if [ "$SCOPE_KIND" != "tenant" ] && [ -z "$scope_id" ]; then
  echo "gate chain scope (${SCOPE_KIND}) not present; nothing to delete"
  exit 0
fi

id=$(el_find_gate_chain_id "$SCOPE_KIND" "$scope_id" "$IS_ENTRY" "$to_stage_id")
if [ -z "$id" ]; then
  echo "gate chain config (scope=${SCOPE_KIND}, entry=${IS_ENTRY}, toStage=${TO_STAGE:-none}) not present; nothing to delete"
  exit 0
fi

vars=$(jq -cn --arg id "$id" '{id: $id}')
if ! el_post_checked 'mutation($id: ID!) { deleteGateChainConfig(id: $id) { id } }' "$vars" >/dev/null; then
  echo "enderlane: failed to delete gate chain config (${id}); see error above" >&2
  exit 1
fi
echo "gate chain config soft-deleted (${id})"
