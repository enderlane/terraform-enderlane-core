variable "api_url" {
  description = "Enderlane GraphQL v2 endpoint."
  type        = string
}

variable "api_key" {
  description = "Enderlane machine API key (sent as X-API-Key). Stored in state — treat state as a secret."
  type        = string
  sensitive   = true
}

variable "name" {
  description = "Edge provider config name. Unique per tenant; the idempotency key."
  type        = string
}

variable "provider_kind" {
  description = "Edge provider: CLOUDFLARE or CLOUDFRONT."
  type        = string

  validation {
    condition     = contains(["CLOUDFLARE", "CLOUDFRONT"], var.provider_kind)
    error_message = "provider_kind must be CLOUDFLARE or CLOUDFRONT."
  }
}

variable "cloudflare_account_id" {
  description = "Cloudflare account id (CLOUDFLARE provider)."
  type        = string
  default     = null
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token (CLOUDFLARE provider). Write-only in the API; never read back. Passed via the environment only, never stored in state (only a hash is tracked)."
  type        = string
  default     = null
  sensitive   = true
}

variable "cloudflare_config_store_ns_id" {
  description = "Cloudflare config-store KV namespace id (CLOUDFLARE provider)."
  type        = string
  default     = null
}

variable "cloudfront_region" {
  description = "AWS region for CloudFront KVS (CLOUDFRONT provider)."
  type        = string
  default     = null
}

variable "aws_access_key_id" {
  description = "AWS access key id (CLOUDFRONT provider)."
  type        = string
  default     = null
}

variable "aws_secret_access_key" {
  description = "AWS secret access key (CLOUDFRONT provider). Write-only in the API; never read back. Passed via the environment only, never stored in state (only a hash is tracked)."
  type        = string
  default     = null
  sensitive   = true
}
