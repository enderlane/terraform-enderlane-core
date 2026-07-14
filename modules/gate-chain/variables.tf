variable "api_url" {
  description = "Enderlane GraphQL v2 endpoint."
  type        = string
}

variable "api_key" {
  description = "Enderlane machine API key (sent as X-API-Key). Stored in state — treat state as a secret."
  type        = string
  sensitive   = true
}

variable "scope_kind" {
  description = "Scope level: tenant (tenant-wide default), group (a lane-group override), or lane (a lane override)."
  type        = string

  validation {
    condition     = contains(["tenant", "group", "lane"], var.scope_kind)
    error_message = "scope_kind must be tenant, group, or lane."
  }
}

variable "scope_group" {
  description = "Lane group name — required for scope_kind group or lane (the lane's group)."
  type        = string
  default     = null
}

variable "scope_lane" {
  description = "Lane name — required for scope_kind lane."
  type        = string
  default     = null
}

variable "is_entry" {
  description = "true = the entry transition (registration into the first stage; to_stage must be null). false = a hop; to_stage names the destination."
  type        = bool
}

variable "to_stage" {
  description = "Destination stage name for a hop (required when is_entry is false). Resolved within scope_group's override stages, else the tenant-default stage of that name."
  type        = string
  default     = null
}

variable "initiation_mode" {
  description = "MANUAL (an explicit promote/CI call pulls the trigger) or AUTO (the system initiates when the chain opens)."
  type        = string

  validation {
    condition     = contains(["MANUAL", "AUTO"], var.initiation_mode)
    error_message = "initiation_mode must be MANUAL or AUTO."
  }
}

variable "steps" {
  description = <<-EOT
    Ordered chain steps (may be empty — an empty chain + AUTO on the entry
    transition is the one-call CI shape). Each step:
      - mode        SINGLE | ALL | ANY  (SINGLE = one condition; ALL = every
                    condition must clear; ANY = at least one)
      - conditions  list of conditions, each:
          - kind              APPROVAL | FREEZE | SOAK | DEPENDENCY
          - subject           (APPROVAL) who/what must approve
          - duration_minutes  (SOAK) how long the source declaration must stand
          - dependency_lane   (DEPENDENCY) another lane's name, within scope_group
          - dependency_stage  (DEPENDENCY) that lane's stage name
  EOT
  type = list(object({
    mode = string
    conditions = list(object({
      kind             = string
      subject          = optional(string)
      duration_minutes = optional(number)
      dependency_lane  = optional(string)
      dependency_stage = optional(string)
    }))
  }))
  default = []
}
