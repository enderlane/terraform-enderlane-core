variable "name" {
  description = "Lane group name. Unique per tenant."
  type        = string
}

variable "kv_namespace_id" {
  description = "Optional edge KV namespace id (declare-only in the v2 API)."
  type        = string
  default     = null
}

variable "provider_kind" {
  description = "Optional edge provider kind for the group's target: CLOUDFLARE or CLOUDFRONT (declare-only)."
  type        = string
  default     = null
}

variable "edge_provider_config_id" {
  description = "Optional id of the edge provider config this group binds. Declare-only; cannot be cleared via update (END-87) — remove-and-recreate to unset."
  type        = string
  default     = null
}

variable "lanes" {
  description = <<-EOT
    Lanes in the group, keyed by lane name. Each:
      - description      (optional; declare-only)
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
    Per-group stage OVERRIDES, keyed by stage name. Each:
      - order_index        (required, number) position; lower runs first
      - kv_prefix          (optional)
      - description        (optional)
      - requires_approval  (optional bool)
  EOT
  type = map(object({
    order_index       = number
    kv_prefix         = optional(string)
    description       = optional(string)
    requires_approval = optional(bool)
  }))
  default = {}
}
