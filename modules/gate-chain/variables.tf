variable "lane_group_id" {
  description = "Resolved lane group id for a group-scoped chain (null otherwise)."
  type        = string
  default     = null
}

variable "lane_id" {
  description = "Resolved lane id for a lane-scoped chain (null otherwise). Mutually exclusive with lane_group_id."
  type        = string
  default     = null
}

variable "is_entry" {
  description = "true = entry transition (to_stage_id must be null); false = a hop (to_stage_id required)."
  type        = bool
}

variable "to_stage_id" {
  description = "Resolved destination stage id for a hop (null for an entry transition)."
  type        = string
  default     = null
}

variable "initiation_mode" {
  description = "MANUAL or AUTO."
  type        = string

  validation {
    condition     = contains(["MANUAL", "AUTO"], var.initiation_mode)
    error_message = "initiation_mode must be MANUAL or AUTO."
  }
}

variable "steps" {
  description = <<-EOT
    Ordered chain steps (may be empty). Each step:
      - mode        SINGLE | ALL | ANY
      - conditions  list of { kind, subject?, duration_minutes?,
                    dependency_lane_id?, dependency_stage_id? } — all ids
                    already resolved by the caller.
  EOT
  type = list(object({
    mode = string
    conditions = list(object({
      kind                = string
      subject             = optional(string)
      duration_minutes    = optional(number)
      dependency_lane_id  = optional(string)
      dependency_stage_id = optional(string)
    }))
  }))
  default = []
}
