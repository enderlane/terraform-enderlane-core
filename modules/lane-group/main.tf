# One Enderlane lane group: the group, its lanes, and its per-group stage
# overrides — via the enderlane provider. Cross-references (the bound edge
# config) arrive as a resolved id from the caller.

terraform {
  required_providers {
    enderlane = { source = "enderlane/enderlane" }
  }
}

resource "enderlane_lane_group" "this" {
  name                    = var.name
  kv_namespace_id         = var.kv_namespace_id
  provider_kind           = var.provider_kind
  edge_provider_config_id = var.edge_provider_config_id
}

resource "enderlane_lane" "this" {
  for_each = var.lanes

  lane_group_id   = enderlane_lane_group.this.id
  name            = each.key
  description     = each.value.description
  deployment_type = each.value.deployment_type
}

# Per-group stage OVERRIDES (lane_group_id set). Omit the group's stages to
# inherit the tenant-default progression instead.
resource "enderlane_stage" "this" {
  for_each = var.stages

  lane_group_id     = enderlane_lane_group.this.id
  name              = each.key
  order_index       = each.value.order_index
  kv_prefix         = each.value.kv_prefix
  description       = each.value.description
  requires_approval = each.value.requires_approval
}
