# One Enderlane gate chain config, attached to a (scope, transition target).
# Gate chains carry no name — identity is scope + target, which is also the
# idempotency key. Created (or updated in place) then soft-deleted on destroy.
# STORAGE/RESOLUTION/READ only in the current backend — nothing in the promotion
# path consults it yet.

terraform {
  required_providers {
    null     = { source = "hashicorp/null", version = "~> 3.2" }
    external = { source = "hashicorp/external", version = "~> 2.3" }
  }
}

locals {
  # Marshal steps into the shape create_gate_chain.sh expects: camelCase keys,
  # DEPENDENCY conditions still carrying NAME references (dependencyLane/Stage)
  # which the script resolves to ids at run time.
  steps_json = jsonencode([
    for s in var.steps : {
      mode = s.mode
      conditions = [
        for c in s.conditions : {
          kind            = c.kind
          subject         = c.subject
          durationMinutes = c.duration_minutes
          dependencyLane  = c.dependency_lane
          dependencyStage = c.dependency_stage
        }
      ]
    }
  ])
}

resource "null_resource" "gate_chain" {
  triggers = {
    api_url         = var.api_url
    api_key         = var.api_key
    scope_kind      = var.scope_kind
    scope_group     = (var.scope_group == null ? "" : var.scope_group)
    scope_lane      = (var.scope_lane == null ? "" : var.scope_lane)
    is_entry        = tostring(var.is_entry)
    to_stage        = (var.to_stage == null ? "" : var.to_stage)
    initiation_mode = var.initiation_mode
    steps           = local.steps_json
  }

  provisioner "local-exec" {
    command = "${path.module}/../../scripts/create_gate_chain.sh"
    environment = {
      ENDERLANE_API_URL = self.triggers.api_url
      ENDERLANE_API_KEY = self.triggers.api_key
      SCOPE_KIND        = self.triggers.scope_kind
      SCOPE_GROUP       = self.triggers.scope_group
      SCOPE_LANE        = self.triggers.scope_lane
      IS_ENTRY          = self.triggers.is_entry
      TO_STAGE          = self.triggers.to_stage
      INITIATION_MODE   = self.triggers.initiation_mode
      STEPS_JSON        = self.triggers.steps
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "${path.module}/../../scripts/delete_gate_chain.sh"
    environment = {
      ENDERLANE_API_URL = self.triggers.api_url
      ENDERLANE_API_KEY = self.triggers.api_key
      SCOPE_KIND        = self.triggers.scope_kind
      SCOPE_GROUP       = self.triggers.scope_group
      SCOPE_LANE        = self.triggers.scope_lane
      IS_ENTRY          = self.triggers.is_entry
      TO_STAGE          = self.triggers.to_stage
    }
  }
}

data "external" "gate_chain" {
  depends_on = [null_resource.gate_chain]
  program    = ["bash", "${path.module}/../../scripts/lookup_gate_chain.sh"]
  query = {
    api_url     = var.api_url
    api_key     = var.api_key
    scope_kind  = var.scope_kind
    scope_group = (var.scope_group == null ? "" : var.scope_group)
    scope_lane  = (var.scope_lane == null ? "" : var.scope_lane)
    is_entry    = tostring(var.is_entry)
    to_stage    = (var.to_stage == null ? "" : var.to_stage)
  }
}
