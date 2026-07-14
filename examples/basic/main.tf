# Basic example: one lane group with two lanes, on the tenant-default stage
# progression. No edge configs, gates, or presets.
#
#   export ENDERLANE_API_KEY="<your-machine-key>"
#   # export ENDERLANE_API_URL="https://app.enderlane.com/graphql"   # default
#   terraform init && terraform apply

terraform {
  required_version = ">= 1.5"
  required_providers {
    enderlane = {
      source  = "enderlane/enderlane"
      version = ">= 0.1.0"
    }
  }
}

# API key/URL come from ENDERLANE_API_KEY / ENDERLANE_API_URL (recommended), or
# set them here explicitly.
provider "enderlane" {}

module "tenant" {
  source = "../../"

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
