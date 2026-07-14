#!/usr/bin/env bash
# Soft-delete a lane by name within its group (destroy-time).
#
# Resolves the id by (group name, lane name) from self.triggers. A lane already
# gone is a clean no-op. deleteLane soft-deletes: bindings and transition
# history are retained; the lane just drops out of default reads.
#
# Environment: ENDERLANE_API_URL, ENDERLANE_API_KEY, GROUP_NAME, NAME.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
el_require_env
: "${GROUP_NAME:?GROUP_NAME is required}"
: "${NAME:?NAME is required}"

id=$(el_find_lane_id "$GROUP_NAME" "$NAME")
if [ -z "$id" ]; then
  echo "lane '${NAME}' in '${GROUP_NAME}' not present; nothing to delete"
  exit 0
fi

vars=$(jq -cn --arg id "$id" '{id: $id}')
if ! el_post_checked 'mutation($id: ID!) { deleteLane(id: $id) }' "$vars" >/dev/null; then
  echo "enderlane: refused to delete lane '${NAME}' (${id}) — see error above" >&2
  exit 1
fi
echo "lane '${NAME}' soft-deleted (${id})"
