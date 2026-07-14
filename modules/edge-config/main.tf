# One Enderlane edge provider config (Cloudflare KV or CloudFront KVS).
#
# Secrets (cloudflare_api_token, aws_secret_access_key) are WRITE-ONLY in the
# API: reads return only presence booleans, so Terraform cannot detect secret
# drift. They reach the create/update script via the environment (never a
# command line, never echoed) and are NOT stored in state — only a hash is
# tracked, so a change re-runs the update. deleteEdgeProviderConfig is a HARD
# delete.
#
# TWO resources, deliberately:
#   * edge_config       — CREATE + DELETE, keyed on IDENTITY ONLY (name). It is
#     never replaced by a field or secret change, so a rotation never deletes and
#     recreates the config (which would break while it is referenced as a group's
#     binding or the tenant default — the API refuses to delete a referenced
#     config, and the id would change).
#   * edge_config_sync  — UPDATE-ONLY, keyed on the mutable fields + a secret
#     hash. On any change it re-runs the idempotent create-or-update script,
#     resending every field including secrets, IN PLACE (same id). It has no
#     destroy provisioner — deletion is edge_config's job.

terraform {
  required_providers {
    null     = { source = "hashicorp/null", version = "~> 3.2" }
    external = { source = "hashicorp/external", version = "~> 2.3" }
  }
}

locals {
  env = {
    ENDERLANE_API_URL     = var.api_url
    ENDERLANE_API_KEY     = var.api_key
    NAME                  = var.name
    PROVIDER              = var.provider_kind
    CF_ACCOUNT_ID         = var.cloudflare_account_id == null ? "" : var.cloudflare_account_id
    CF_API_TOKEN          = var.cloudflare_api_token == null ? "" : var.cloudflare_api_token
    CF_CONFIG_STORE_NS_ID = var.cloudflare_config_store_ns_id == null ? "" : var.cloudflare_config_store_ns_id
    CFR_REGION            = var.cloudfront_region == null ? "" : var.cloudfront_region
    AWS_ACCESS_KEY_ID     = var.aws_access_key_id == null ? "" : var.aws_access_key_id
    AWS_SECRET_ACCESS_KEY = var.aws_secret_access_key == null ? "" : var.aws_secret_access_key
  }
}

# CREATE + DELETE — identity only, so it never replaces on a field/secret change.
resource "null_resource" "edge_config" {
  triggers = {
    api_url = var.api_url
    api_key = var.api_key
    name    = var.name
  }

  provisioner "local-exec" {
    command     = "${path.module}/../../scripts/create_edge_config.sh"
    environment = local.env
  }

  provisioner "local-exec" {
    when    = destroy
    command = "${path.module}/../../scripts/delete_edge_config.sh"
    environment = {
      ENDERLANE_API_URL = self.triggers.api_url
      ENDERLANE_API_KEY = self.triggers.api_key
      NAME              = self.triggers.name
    }
  }
}

# UPDATE-ONLY — re-runs the idempotent create-or-update in place when any mutable
# field or a secret changes. No destroy provisioner: a rotation replaces this
# resource, whose destroy is a no-op, so the config itself is never deleted.
resource "null_resource" "edge_config_sync" {
  depends_on = [null_resource.edge_config]

  triggers = {
    provider_kind                 = var.provider_kind
    cloudflare_account_id         = var.cloudflare_account_id == null ? "" : var.cloudflare_account_id
    cloudflare_config_store_ns_id = var.cloudflare_config_store_ns_id == null ? "" : var.cloudflare_config_store_ns_id
    cloudfront_region             = var.cloudfront_region == null ? "" : var.cloudfront_region
    aws_access_key_id             = var.aws_access_key_id == null ? "" : var.aws_access_key_id
    secret_hash = sha256(join("|", [
      var.cloudflare_api_token == null ? "" : var.cloudflare_api_token,
      var.aws_secret_access_key == null ? "" : var.aws_secret_access_key,
    ]))
  }

  provisioner "local-exec" {
    command     = "${path.module}/../../scripts/create_edge_config.sh"
    environment = local.env
  }
}

data "external" "edge_config" {
  depends_on = [null_resource.edge_config, null_resource.edge_config_sync]
  program    = ["bash", "${path.module}/../../scripts/lookup_edge_config.sh"]
  query = {
    api_url = var.api_url
    api_key = var.api_key
    name    = var.name
  }
}
