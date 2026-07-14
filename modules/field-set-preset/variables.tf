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
  description = "Preset name. Unique per tenant; the idempotency key. Do NOT reuse a seeded system preset name ('Build', 'Config version')."
  type        = string
}

variable "description" {
  description = "Optional preset description."
  type        = string
  default     = null
}

variable "fields" {
  description = <<-EOT
    Ordered list of fields the preset defines. Each:
      - name           (required)
      - required       (required, bool) whether a unit must carry this field
      - description     (optional)
      - allowed_values  (optional) non-empty allowed-values list when set
  EOT
  type = list(object({
    name           = string
    required       = bool
    description    = optional(string)
    allowed_values = optional(list(string))
  }))

  validation {
    condition     = length(var.fields) > 0
    error_message = "a preset must define at least one field."
  }
}
