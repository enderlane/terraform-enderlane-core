# One Enderlane edge provider config (Cloudflare KV or CloudFront KVS), via the
# enderlane provider. Secret values are write-only in the API (never read back,
# only has_* presence booleans), so the provider stores them as declared and
# never diffs them. This config is HARD-deleted on destroy.

terraform {
  required_providers {
    enderlane = { source = "enderlane/enderlane" }
  }
}

resource "enderlane_edge_provider_config" "this" {
  name                          = var.name
  provider_kind                 = var.provider_kind
  cloudflare_account_id         = var.cloudflare_account_id
  cloudflare_api_token          = var.cloudflare_api_token
  cloudflare_config_store_ns_id = var.cloudflare_config_store_ns_id
  cloudfront_region             = var.cloudfront_region
  aws_access_key_id             = var.aws_access_key_id
  aws_secret_access_key         = var.aws_secret_access_key
}
