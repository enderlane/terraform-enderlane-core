variable "name" {
  description = "Preset name. Unique per tenant. Do NOT reuse a seeded system preset name ('Build', 'Config version')."
  type        = string
}

variable "description" {
  description = "Optional preset description."
  type        = string
  default     = null
}

variable "fields" {
  description = <<-EOT
    Ordered list of fields the preset defines (at least one). Each:
      - name           (required)
      - required       (required, bool)
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
