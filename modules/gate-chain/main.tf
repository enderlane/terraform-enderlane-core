# One Enderlane gate chain config, via the enderlane provider. Scope and target
# and any DEPENDENCY references arrive as already-resolved ids from the caller
# (the root module resolves names -> ids). Soft-deleted on destroy.

terraform {
  required_providers {
    enderlane = { source = "enderlane/enderlane" }
  }
}

resource "enderlane_gate_chain_config" "this" {
  lane_group_id       = var.lane_group_id
  lane_id             = var.lane_id
  is_entry_transition = var.is_entry
  to_stage_id         = var.to_stage_id
  initiation_mode     = var.initiation_mode

  dynamic "steps" {
    for_each = var.steps
    content {
      mode = steps.value.mode
      dynamic "conditions" {
        for_each = steps.value.conditions
        content {
          kind                = conditions.value.kind
          subject             = conditions.value.subject
          duration_minutes    = conditions.value.duration_minutes
          dependency_lane_id  = conditions.value.dependency_lane_id
          dependency_stage_id = conditions.value.dependency_stage_id
        }
      }
    }
  }
}
