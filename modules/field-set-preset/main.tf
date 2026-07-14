# One Enderlane field-set preset — the template describing what metadata a unit
# carries — via the enderlane provider. Ordered fields are preserved. Seeded
# system presets are immutable and never managed here. Soft-deleted on destroy.

terraform {
  required_providers {
    enderlane = { source = "enderlane/enderlane" }
  }
}

resource "enderlane_field_set_preset" "this" {
  name        = var.name
  description = var.description

  dynamic "fields" {
    for_each = var.fields
    content {
      name           = fields.value.name
      required       = fields.value.required
      description    = fields.value.description
      allowed_values = fields.value.allowed_values
    }
  }
}
