# The Enderlane provider is configured by the ROOT (consuming) configuration:
#
#   provider "enderlane" {
#     # api_url = "https://app.enderlane.com/graphql"   # or ENDERLANE_API_URL
#     # api_key = var.enderlane_api_key                 # or ENDERLANE_API_KEY
#   }
#
# This module therefore takes NO api_url / api_key variables (a breaking change
# from v0.1). It inherits the default enderlane provider.

variable "tenant_id" {
  description = <<-EOT
    Tenant ID, REQUIRED only when default_edge_provider_config is set (the
    provider's tenant-default resource needs an explicit tenant id, and the v2
    API exposes no current-tenant lookup). Leave null otherwise.
  EOT
  type        = string
  default     = null
}

# ── Edge provider configs ─────────────────────────────────────────────────────
variable "edge_provider_configs" {
  description = <<-EOT
    Edge provider configs (Cloudflare KV / CloudFront KVS), keyed by a friendly
    name used to cross-reference them from lane groups and the tenant default.
    Secrets (cloudflare_api_token, aws_secret_access_key) are WRITE-ONLY in the
    API — never read back (the server exposes only has_* presence booleans), so
    the provider stores the declared value in state and never diffs it. Each:
      - provider                       CLOUDFLARE | CLOUDFRONT
      - cloudflare_account_id          (CLOUDFLARE)
      - cloudflare_api_token           (CLOUDFLARE, sensitive, write-only)
      - cloudflare_config_store_ns_id  (CLOUDFLARE)
      - cloudfront_region              (CLOUDFRONT)
      - aws_access_key_id              (CLOUDFRONT)
      - aws_secret_access_key          (CLOUDFRONT, sensitive, write-only)
  EOT
  type = map(object({
    provider                      = string
    cloudflare_account_id         = optional(string)
    cloudflare_api_token          = optional(string)
    cloudflare_config_store_ns_id = optional(string)
    cloudfront_region             = optional(string)
    aws_access_key_id             = optional(string)
    aws_secret_access_key         = optional(string)
  }))
  default = {}
}

variable "default_edge_provider_config" {
  description = "Name (key in edge_provider_configs) of the config to set as the tenant default, or null to leave it unset. Requires tenant_id when set."
  type        = string
  default     = null
}

# ── Tenant-default stages ─────────────────────────────────────────────────────
variable "default_stages" {
  description = <<-EOT
    The tenant-default stage progression (shared by any lane group that does not
    override it), keyed by stage name. Each:
      - order_index        (required, number) position; lower runs first
      - kv_prefix          (optional)
      - description        (optional)
      - requires_approval  (optional bool) promotions into this stage park for approval
  EOT
  type = map(object({
    order_index       = number
    kv_prefix         = optional(string)
    description       = optional(string)
    requires_approval = optional(bool)
  }))
  default = {}
}

# ── Lane groups ───────────────────────────────────────────────────────────────
variable "lane_groups" {
  description = <<-EOT
    Lane groups keyed by group name. Each:
      - kv_namespace_id       (optional) edge KV namespace id (declare-only)
      - edge_provider_config  (optional) name of an edge_provider_configs entry
                              to bind (created first automatically; declare-only,
                              and cannot be cleared via update — see END-87)
      - lanes                 map of lane name -> { description?, deployment_type? }
                              deployment_type in SPA | CLOUD_RUN | CONFIG | OTHER
      - stages                map of stage name -> { order_index, kv_prefix?,
                              description?, requires_approval? } — per-group
                              OVERRIDES of the tenant-default progression
  EOT
  type = map(object({
    kv_namespace_id      = optional(string)
    edge_provider_config = optional(string)
    lanes = optional(map(object({
      description     = optional(string)
      deployment_type = optional(string)
    })), {})
    stages = optional(map(object({
      order_index       = number
      kv_prefix         = optional(string)
      description       = optional(string)
      requires_approval = optional(bool)
    })), {})
  }))
  default = {}
}

# ── Gate chains ───────────────────────────────────────────────────────────────
variable "gate_chains" {
  description = <<-EOT
    Gate chain configs. A list; each chain is identified by its scope +
    transition target. Cross-references are by NAME (resolved to ids). Each:
      - scope_kind       tenant | group | lane
      - scope_group      lane group name (required for group/lane scope)
      - scope_lane       lane name (required for lane scope)
      - is_entry         true = entry transition (to_stage null); false = a hop
      - to_stage         destination stage name (required when is_entry false)
      - initiation_mode  MANUAL | AUTO
      - steps            ordered steps (may be empty). Each step:
          - mode         SINGLE | ALL | ANY
          - conditions   list of { kind (APPROVAL|FREEZE|SOAK|DEPENDENCY),
                         subject?, duration_minutes?, dependency_lane?,
                         dependency_stage? }
  EOT
  type = list(object({
    scope_kind      = string
    scope_group     = optional(string)
    scope_lane      = optional(string)
    is_entry        = bool
    to_stage        = optional(string)
    initiation_mode = string
    steps = optional(list(object({
      mode = string
      conditions = list(object({
        kind             = string
        subject          = optional(string)
        duration_minutes = optional(number)
        dependency_lane  = optional(string)
        dependency_stage = optional(string)
      }))
    })), [])
  }))
  default = []
}

# ── Field-set presets ─────────────────────────────────────────────────────────
variable "field_set_presets" {
  description = <<-EOT
    Tenant field-set presets keyed by preset name (do NOT reuse a seeded system
    preset name, 'Build' or 'Config version'). Each:
      - description  (optional)
      - fields       ordered list of { name, required (bool), description?,
                     allowed_values? }
  EOT
  type = map(object({
    description = optional(string)
    fields = list(object({
      name           = string
      required       = bool
      description    = optional(string)
      allowed_values = optional(list(string))
    }))
  }))
  default = {}
}

# ── Unit-kind → field-set-preset mappings ─────────────────────────────────────
variable "unit_kind_field_sets" {
  description = <<-EOT
    Which field-set preset governs a unit KIND's registration validation, at a
    chosen scope. A list; each:
      - kind         BUILD | CONFIG
      - preset       preset name (a field_set_presets entry, or a seeded system
                     preset such as 'Build' / 'Config version')
      - scope_group  (optional) lane group name -> a group-level override
      - scope_lane   (optional) lane name -> a lane-level override (with scope_group)
    Omit both scopes for a tenant-wide mapping. Naming both a group (without a
    lane) and a lane is refused by the API.
  EOT
  type = list(object({
    kind        = string
    preset      = string
    scope_group = optional(string)
    scope_lane  = optional(string)
  }))
  default = []
}
