#!/usr/bin/env bash
# Soft-delete a lane group by name (destroy-time).
#
# Resolves the id by name (destroy provisioners may only read self.triggers, so
# name is all we have). A group already gone is a clean no-op — destroy stays
# idempotent. deleteLaneGroup soft-deletes: the row and all its history survive,
# it just drops out of default reads. It refuses while any lane is still active,
# but Terraform destroys the lanes first (they depend on the group), so by now
# they are soft-deleted; a genuine refusal is surfaced as an error.
#
# Environment: ENDERLANE_API_URL, ENDERLANE_API_KEY, NAME.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
el_require_env
: "${NAME:?NAME is required}"

id=$(el_find_lane_group_id "$NAME")
if [ -z "$id" ]; then
  echo "lane group '${NAME}' not present; nothing to delete"
  exit 0
fi

vars=$(jq -cn --arg id "$id" '{id: $id}')
if ! el_post_checked 'mutation($id: ID!) { deleteLaneGroup(id: $id) }' "$vars" >/dev/null; then
  echo "enderlane: refused to delete lane group '${NAME}' (${id}) — see error above" >&2
  exit 1
fi
echo "lane group '${NAME}' soft-deleted (${id})"
