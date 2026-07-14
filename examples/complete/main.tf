# Complete example: exercises every part of the module — two edge provider
# configs (Cloudflare + CloudFront), a tenant default edge config, the
# tenant-default stage progression, a lane group with a per-group stage
# override, gate chains (an AUTO empty entry chain and a MANUAL hop chain with
# an ALL step), a custom field-set preset, and unit-kind mappings.
#
#   export ENDERLANE_API_KEY="<your-machine-key>"
#   terraform init && terraform apply
#
# Edge SECRETS (cloudflare_api_token, aws_secret_access_key) are optional here;
# set TF_VAR_cf_api_token / TF_VAR_aws_secret_key to store real credentials (the
# API then reports has_cloudflare_api_token / has_aws_secret_access_key true).

terraform {
  required_version = ">= 1.5"
  required_providers {
    enderlane = {
      source  = "enderlane/enderlane"
      version = ">= 0.1.0"
    }
  }
}

provider "enderlane" {}

variable "tenant_id" {
  description = "Tenant id (needed to set the tenant default edge config)."
  type        = string
}

variable "cf_api_token" {
  type      = string
  default   = null
  sensitive = true
}

variable "aws_secret_key" {
  type      = string
  default   = null
  sensitive = true
}

module "tenant" {
  source = "../../"

  tenant_id = var.tenant_id

  edge_provider_configs = {
    cf-main = {
      provider                      = "CLOUDFLARE"
      cloudflare_account_id         = "cf-account-123"
      cloudflare_config_store_ns_id = "cf-ns-456"
      cloudflare_api_token          = var.cf_api_token
    }
    aws-edge = {
      provider              = "CLOUDFRONT"
      cloudfront_region     = "us-east-1"
      aws_access_key_id     = "AKIAEXAMPLE"
      aws_secret_access_key = var.aws_secret_key
    }
  }

  # cf-main is the tenant default. NOTE: it is deliberately NOT bound to the
  # lane group below (no edge_provider_config on the group) so this example
  # destroys cleanly — a group-bound edge config cannot be destroyed while the
  # group's (soft-deleted) row still references it (END-87). See the README.
  default_edge_provider_config = "cf-main"

  default_stages = {
    alpha   = { order_index = 0, kv_prefix = "alpha" }
    bravo   = { order_index = 1, kv_prefix = "bravo" }
    charlie = { order_index = 2, kv_prefix = "charlie" }
  }

  lane_groups = {
    acme-platform = {
      kv_namespace_id = "kv-namespace-789"
      lanes = {
        web = { description = "Customer-facing SPA", deployment_type = "SPA" }
        api = { description = "Backend API", deployment_type = "CLOUD_RUN" }
      }
      # Override the tenant-default progression for this group.
      stages = {
        alpha = { order_index = 0, kv_prefix = "alpha" }
        bravo = { order_index = 1, kv_prefix = "bravo" }
        prod  = { order_index = 2, kv_prefix = "prod", requires_approval = true }
      }
    }
  }

  gate_chains = [
    # Entry transition auto-initiates with no gates.
    {
      scope_kind      = "group"
      scope_group     = "acme-platform"
      is_entry        = true
      initiation_mode = "AUTO"
      steps           = []
    },
    # Promotions into "prod" require a manual approval AND a 60-minute soak.
    {
      scope_kind      = "group"
      scope_group     = "acme-platform"
      is_entry        = false
      to_stage        = "prod"
      initiation_mode = "MANUAL"
      steps = [
        {
          mode = "ALL"
          conditions = [
            { kind = "APPROVAL", subject = "release-manager" },
            { kind = "SOAK", duration_minutes = 60 },
          ]
        },
      ]
    },
  ]

  field_set_presets = {
    "Strict build" = {
      description = "Build units must declare their branch and target environment."
      fields = [
        { name = "branch", required = true, description = "Source branch" },
        { name = "commit_message", required = false },
        { name = "environment", required = true, allowed_values = ["dev", "staging", "prod"] },
      ]
    }
  }

  unit_kind_field_sets = [
    # Tenant-wide: all BUILD units validate against the custom preset.
    { kind = "BUILD", preset = "Strict build" },
    # Lane override: the web lane's BUILD units use the seeded system preset.
    { kind = "BUILD", preset = "Build", scope_group = "acme-platform", scope_lane = "web" },
  ]
}

output "edge_provider_config_ids" { value = module.tenant.edge_provider_config_ids }
output "lane_group_ids" { value = module.tenant.lane_group_ids }
output "lane_ids" { value = module.tenant.lane_ids }
output "group_stage_ids" { value = module.tenant.group_stage_ids }
output "default_stage_ids" { value = module.tenant.default_stage_ids }
output "field_set_preset_ids" { value = module.tenant.field_set_preset_ids }
output "gate_chain_ids" { value = module.tenant.gate_chain_ids }
