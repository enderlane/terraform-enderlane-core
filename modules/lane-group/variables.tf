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
  description = "Lane group name. Unique per tenant; the idempotency key."
  type        = string
}

variable "kv_namespace_id" {
  description = "Optional Cloudflare KV namespace id for the group's edge pointers."
  type        = string
  default     = null
}

variable "edge_provider_config" {
  description = "Optional name of an edge provider config to bind this group to. Must exist (create it first, e.g. via the tenant root module which orders this dependency). The group's provider is set to match the referenced config."
  type        = string
  default     = null
}

variable "lanes" {
  description = <<-EOT
    Lanes (deployable apps/components) in the group, keyed by lane name. Each:
      - description      (optional)
      - deployment_type  (optional) SPA | CLOUD_RUN | CONFIG | OTHER
  EOT
  type = map(object({
    description     = optional(string)
    deployment_type = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for l in values(var.lanes) :
      l.deployment_type == null || contains(["SPA", "CLOUD_RUN", "CONFIG", "OTHER"], coalesce(l.deployment_type, "SPA"))
    ])
    error_message = "deployment_type, when set, must be one of SPA, CLOUD_RUN, CONFIG, OTHER."
  }
}

variable "stages" {
  description = <<-EOT
    Per-group stage OVERRIDES, keyed by stage name. When non-empty, these
    override the tenant-default progression FOR THIS GROUP. Each:
      - order_index  (required, number) position; lower runs first
      - kv_prefix    (optional)
      - description   (optional)
  EOT
  type = map(object({
    order_index = number
    kv_prefix   = optional(string)
    description = optional(string)
  }))
  default = {}
}
