# One tenant field-set preset — the template describing what details a unit
# carries. Created (or updated in place) by name; soft-deleted on destroy.
# Seeded system presets are never touched (they are immutable and shared).

terraform {
  required_providers {
    null     = { source = "hashicorp/null", version = "~> 3.2" }
    external = { source = "hashicorp/external", version = "~> 2.3" }
  }
}

locals {
  # Marshal fields into the GraphQL FieldSetPresetFieldInput shape (camelCase).
  # null-valued optionals are stripped by the create script.
  fields_json = jsonencode([
    for f in var.fields : {
      name          = f.name
      required      = f.required
      description   = f.description
      allowedValues = f.allowed_values
    }
  ])
}

resource "null_resource" "preset" {
  triggers = {
    api_url     = var.api_url
    api_key     = var.api_key
    name        = var.name
    description = (var.description == null ? "" : var.description)
    fields      = local.fields_json
  }

  provisioner "local-exec" {
    command = "${path.module}/../../scripts/create_field_set_preset.sh"
    environment = {
      ENDERLANE_API_URL = self.triggers.api_url
      ENDERLANE_API_KEY = self.triggers.api_key
      NAME              = self.triggers.name
      DESCRIPTION       = self.triggers.description
      FIELDS_JSON       = self.triggers.fields
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "${path.module}/../../scripts/delete_field_set_preset.sh"
    environment = {
      ENDERLANE_API_URL = self.triggers.api_url
      ENDERLANE_API_KEY = self.triggers.api_key
      NAME              = self.triggers.name
    }
  }
}

data "external" "preset" {
  depends_on = [null_resource.preset]
  program    = ["bash", "${path.module}/../../scripts/lookup_field_set_preset.sh"]
  query = {
    api_url = var.api_url
    api_key = var.api_key
    name    = var.name
  }
}
