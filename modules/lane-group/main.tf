# One Enderlane lane group: the group itself, its lanes, and its per-group stage
# overrides. Idempotent by name; soft-deletes on destroy (lanes/stages before
# the group, so the group's children-active guard is satisfied).

terraform {
  required_providers {
    null     = { source = "hashicorp/null", version = "~> 3.2" }
    external = { source = "hashicorp/external", version = "~> 2.3" }
  }
}

resource "null_resource" "group" {
  triggers = {
    api_url         = var.api_url
    api_key         = var.api_key
    name            = var.name
    kv_namespace_id = (var.kv_namespace_id == null ? "" : var.kv_namespace_id)
    edge_config     = (var.edge_provider_config == null ? "" : var.edge_provider_config)
  }

  provisioner "local-exec" {
    command = "${path.module}/../../scripts/create_lane_group.sh"
    environment = {
      ENDERLANE_API_URL = self.triggers.api_url
      ENDERLANE_API_KEY = self.triggers.api_key
      NAME              = self.triggers.name
      KV_NAMESPACE_ID   = self.triggers.kv_namespace_id
      EDGE_CONFIG       = self.triggers.edge_config
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "${path.module}/../../scripts/delete_lane_group.sh"
    environment = {
      ENDERLANE_API_URL = self.triggers.api_url
      ENDERLANE_API_KEY = self.triggers.api_key
      NAME              = self.triggers.name
    }
  }
}

resource "null_resource" "lane" {
  for_each   = var.lanes
  depends_on = [null_resource.group]

  triggers = {
    api_url         = var.api_url
    api_key         = var.api_key
    group_name      = var.name
    name            = each.key
    description     = (each.value.description == null ? "" : each.value.description)
    deployment_type = (each.value.deployment_type == null ? "" : each.value.deployment_type)
  }

  provisioner "local-exec" {
    command = "${path.module}/../../scripts/create_lane.sh"
    environment = {
      ENDERLANE_API_URL = self.triggers.api_url
      ENDERLANE_API_KEY = self.triggers.api_key
      GROUP_NAME        = self.triggers.group_name
      NAME              = self.triggers.name
      DESCRIPTION       = self.triggers.description
      DEPLOYMENT_TYPE   = self.triggers.deployment_type
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "${path.module}/../../scripts/delete_lane.sh"
    environment = {
      ENDERLANE_API_URL = self.triggers.api_url
      ENDERLANE_API_KEY = self.triggers.api_key
      GROUP_NAME        = self.triggers.group_name
      NAME              = self.triggers.name
    }
  }
}

resource "null_resource" "stage" {
  for_each   = var.stages
  depends_on = [null_resource.group]

  triggers = {
    api_url     = var.api_url
    api_key     = var.api_key
    group_name  = var.name
    name        = each.key
    order_index = tostring(each.value.order_index)
    kv_prefix   = (each.value.kv_prefix == null ? "" : each.value.kv_prefix)
    description = (each.value.description == null ? "" : each.value.description)
  }

  provisioner "local-exec" {
    command = "${path.module}/../../scripts/create_stage.sh"
    environment = {
      ENDERLANE_API_URL = self.triggers.api_url
      ENDERLANE_API_KEY = self.triggers.api_key
      GROUP_NAME        = self.triggers.group_name
      NAME              = self.triggers.name
      ORDER_INDEX       = self.triggers.order_index
      KV_PREFIX         = self.triggers.kv_prefix
      DESCRIPTION       = self.triggers.description
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "${path.module}/../../scripts/delete_stage.sh"
    environment = {
      ENDERLANE_API_URL = self.triggers.api_url
      ENDERLANE_API_KEY = self.triggers.api_key
      GROUP_NAME        = self.triggers.group_name
      NAME              = self.triggers.name
    }
  }
}

data "external" "group" {
  depends_on = [null_resource.group]
  program    = ["bash", "${path.module}/../../scripts/lookup_lane_group.sh"]
  query = {
    api_url = var.api_url
    api_key = var.api_key
    name    = var.name
  }
}

data "external" "lane" {
  for_each   = var.lanes
  depends_on = [null_resource.lane]
  program    = ["bash", "${path.module}/../../scripts/lookup_lane.sh"]
  query = {
    api_url    = var.api_url
    api_key    = var.api_key
    group_name = var.name
    name       = each.key
  }
}

data "external" "stage" {
  for_each   = var.stages
  depends_on = [null_resource.stage]
  program    = ["bash", "${path.module}/../../scripts/lookup_stage.sh"]
  query = {
    api_url    = var.api_url
    api_key    = var.api_key
    group_name = var.name
    name       = each.key
  }
}
