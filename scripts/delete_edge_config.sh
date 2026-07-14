#!/usr/bin/env bash
# Delete an edge provider config by name (destroy-time).
#
# NOTE: deleteEdgeProviderConfig is a HARD delete (the row is removed; there is
# no includeDeleted read and no restore) — unlike lanes/stages/presets/gate
# chains, which soft-delete. A config already gone is a clean no-op. The backend
# refuses if a lane group still references it, so groups are destroyed first
# (dependency ordering); a genuine refusal is surfaced as an error.
#
# Environment: ENDERLANE_API_URL, ENDERLANE_API_KEY, NAME.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
el_require_env
: "${NAME:?NAME is required}"

id=$(el_find_edge_config_id "$NAME")
if [ -z "$id" ]; then
  echo "edge provider config '${NAME}' not present; nothing to delete"
  exit 0
fi

vars=$(jq -cn --arg id "$id" '{id: $id}')
if ! el_post_checked 'mutation($id: ID!) { deleteEdgeProviderConfig(id: $id) }' "$vars" >/dev/null; then
  echo "enderlane: refused to delete edge provider config '${NAME}' (${id}) — a lane group may still reference it; see error above" >&2
  exit 1
fi
echo "edge provider config '${NAME}' deleted (${id})"
