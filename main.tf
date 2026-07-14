# Enderlane tenant module (v0) — declares a whole tenant's configuration:
# edge provider configs, the tenant-default stage progression, lane groups (with
# their lanes and per-group stage overrides), gate chain configs, field-set
# presets, and unit-kind → preset mappings.
#
# v0 mechanism: no custom Terraform provider yet. Each entity is driven through
# the Enderlane GraphQL v2 API by bash/curl/jq helpers in scripts/, invoked by
# null_resource provisioners, with `external` data sources reading ids back.
# Cross-references between blocks are by NAME and resolved inside the scripts
# (list + jq filter — the same list-filter that gives idempotency). A native
# terraform-provider-enderlane is on the roadmap and will supersede this
# mechanism; the interface is intended to stay stable. See the README.

locals {
  # Gate chains: identity is scope + transition target, used as the for_each key.
  gate_chains_by_key = {
    for gc in var.gate_chains :
    join("|", [
      gc.scope_kind,
      (gc.scope_group == null ? "" : gc.scope_group),
      (gc.scope_lane == null ? "" : gc.scope_lane),
      tostring(gc.is_entry),
      (gc.to_stage == null ? "" : gc.to_stage),
    ]) => gc
  }

  # Unit-kind mappings: identity is kind + scope.
  unit_kind_by_key = {
    for m in var.unit_kind_field_sets :
    join("|", [m.kind, (m.scope_group == null ? "" : m.scope_group), (m.scope_lane == null ? "" : m.scope_lane)]) => m
  }
}

# ── Edge provider configs ─────────────────────────────────────────────────────
module "edge_config" {
  source   = "./modules/edge-config"
  for_each = var.edge_provider_configs

  api_url                       = var.api_url
  api_key                       = var.api_key
  name                          = each.key
  provider_kind                 = each.value.provider
  cloudflare_account_id         = each.value.cloudflare_account_id
  cloudflare_api_token          = each.value.cloudflare_api_token
  cloudflare_config_store_ns_id = each.value.cloudflare_config_store_ns_id
  cloudfront_region             = each.value.cloudfront_region
  aws_access_key_id             = each.value.aws_access_key_id
  aws_secret_access_key         = each.value.aws_secret_access_key
}

# ── Tenant default edge provider config ───────────────────────────────────────
resource "null_resource" "tenant_default_edge" {
  count      = var.default_edge_provider_config == null ? 0 : 1
  depends_on = [module.edge_config]

  triggers = {
    api_url     = var.api_url
    api_key     = var.api_key
    edge_config = var.default_edge_provider_config
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/set_tenant_default_edge.sh"
    environment = {
      ENDERLANE_API_URL = self.triggers.api_url
      ENDERLANE_API_KEY = self.triggers.api_key
      EDGE_CONFIG       = self.triggers.edge_config
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "${path.module}/scripts/unset_tenant_default_edge.sh"
    environment = {
      ENDERLANE_API_URL = self.triggers.api_url
      ENDERLANE_API_KEY = self.triggers.api_key
    }
  }
}

# ── Tenant-default stages ─────────────────────────────────────────────────────
resource "null_resource" "tenant_default_stage" {
  for_each = var.default_stages

  triggers = {
    api_url     = var.api_url
    api_key     = var.api_key
    name        = each.key
    order_index = tostring(each.value.order_index)
    kv_prefix   = (each.value.kv_prefix == null ? "" : each.value.kv_prefix)
    description = (each.value.description == null ? "" : each.value.description)
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/create_stage.sh"
    environment = {
      ENDERLANE_API_URL = self.triggers.api_url
      ENDERLANE_API_KEY = self.triggers.api_key
      GROUP_NAME        = "" # tenant default
      NAME              = self.triggers.name
      ORDER_INDEX       = self.triggers.order_index
      KV_PREFIX         = self.triggers.kv_prefix
      DESCRIPTION       = self.triggers.description
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "${path.module}/scripts/delete_stage.sh"
    environment = {
      ENDERLANE_API_URL = self.triggers.api_url
      ENDERLANE_API_KEY = self.triggers.api_key
      GROUP_NAME        = ""
      NAME              = self.triggers.name
    }
  }
}

data "external" "tenant_default_stage" {
  for_each   = var.default_stages
  depends_on = [null_resource.tenant_default_stage]
  program    = ["bash", "${path.module}/scripts/lookup_stage.sh"]
  query = {
    api_url    = var.api_url
    api_key    = var.api_key
    group_name = "" # tenant default
    name       = each.key
  }
}

# ── Lane groups (+ lanes + per-group stage overrides) ─────────────────────────
module "lane_group" {
  source   = "./modules/lane-group"
  for_each = var.lane_groups
  # Edge configs must exist before a group can bind one by name.
  depends_on = [module.edge_config]

  api_url              = var.api_url
  api_key              = var.api_key
  name                 = each.key
  kv_namespace_id      = each.value.kv_namespace_id
  edge_provider_config = each.value.edge_provider_config
  lanes                = each.value.lanes
  stages               = each.value.stages
}

# ── Field-set presets ─────────────────────────────────────────────────────────
module "field_set_preset" {
  source   = "./modules/field-set-preset"
  for_each = var.field_set_presets

  api_url     = var.api_url
  api_key     = var.api_key
  name        = each.key
  description = each.value.description
  fields      = each.value.fields
}

# ── Unit-kind → field-set-preset mappings ─────────────────────────────────────
# Depend on presets (referenced by name) and lane groups (scope references).
resource "null_resource" "unit_kind_field_set" {
  for_each   = local.unit_kind_by_key
  depends_on = [module.field_set_preset, module.lane_group]

  triggers = {
    api_url     = var.api_url
    api_key     = var.api_key
    kind        = each.value.kind
    preset      = each.value.preset
    scope_group = (each.value.scope_group == null ? "" : each.value.scope_group)
    scope_lane  = (each.value.scope_lane == null ? "" : each.value.scope_lane)
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/configure_unit_kind_field_set.sh"
    environment = {
      ENDERLANE_API_URL = self.triggers.api_url
      ENDERLANE_API_KEY = self.triggers.api_key
      KIND              = self.triggers.kind
      PRESET            = self.triggers.preset
      SCOPE_GROUP       = self.triggers.scope_group
      SCOPE_LANE        = self.triggers.scope_lane
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "${path.module}/scripts/clear_unit_kind_field_set.sh"
    environment = {
      ENDERLANE_API_URL = self.triggers.api_url
      ENDERLANE_API_KEY = self.triggers.api_key
      KIND              = self.triggers.kind
      SCOPE_GROUP       = self.triggers.scope_group
      SCOPE_LANE        = self.triggers.scope_lane
    }
  }
}

# ── Gate chains ───────────────────────────────────────────────────────────────
# Depend on lane groups + tenant-default stages (scope/target references).
module "gate_chain" {
  source     = "./modules/gate-chain"
  for_each   = local.gate_chains_by_key
  depends_on = [module.lane_group, null_resource.tenant_default_stage]

  api_url         = var.api_url
  api_key         = var.api_key
  scope_kind      = each.value.scope_kind
  scope_group     = each.value.scope_group
  scope_lane      = each.value.scope_lane
  is_entry        = each.value.is_entry
  to_stage        = each.value.to_stage
  initiation_mode = each.value.initiation_mode
  steps           = each.value.steps
}
