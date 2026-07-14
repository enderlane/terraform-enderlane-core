# Basic example: one lane group with two lanes, on the tenant-default stage
# progression. No edge configs, gates, or presets.
#
#   export TF_VAR_api_key="<your-enderlane-machine-key>"
#   terraform init && terraform apply
#
# Targets a local preview backend by default; point api_url at your real
# Enderlane instance for production use.

terraform {
  required_version = ">= 1.5"
}

variable "api_url" {
  type    = string
  default = "http://127.0.0.1:5300/graphql"
}

variable "api_key" {
  type      = string
  sensitive = true
}

module "tenant" {
  source = "../../"

  api_url = var.api_url
  api_key = var.api_key

  default_stages = {
    alpha   = { order_index = 0 }
    bravo   = { order_index = 1 }
    charlie = { order_index = 2 }
  }

  lane_groups = {
    acme-platform = {
      lanes = {
        web = { description = "Customer-facing SPA", deployment_type = "SPA" }
        api = { description = "Backend API", deployment_type = "CLOUD_RUN" }
      }
    }
  }
}

output "lane_group_ids" { value = module.tenant.lane_group_ids }
output "lane_ids" { value = module.tenant.lane_ids }
output "default_stage_ids" { value = module.tenant.default_stage_ids }
