output "edge_provider_config_ids" {
  description = "Map of edge provider config name to id."
  value       = { for name, m in module.edge_config : name => m.edge_config_id }
}

output "lane_group_ids" {
  description = "Map of lane group name to id."
  value       = { for name, m in module.lane_group : name => m.lane_group_id }
}

output "lane_ids" {
  description = "Nested map of lane group name -> (lane name -> id)."
  value       = { for name, m in module.lane_group : name => m.lane_ids }
}

output "group_stage_ids" {
  description = "Nested map of lane group name -> (override stage name -> id)."
  value       = { for name, m in module.lane_group : name => m.stage_ids }
}

output "default_stage_ids" {
  description = "Map of tenant-default stage name to id."
  value       = { for name, r in enderlane_stage.default : name => r.id }
}

output "field_set_preset_ids" {
  description = "Map of field-set preset name to id."
  value       = { for name, m in module.field_set_preset : name => m.field_set_preset_id }
}

output "gate_chain_ids" {
  description = "Map of gate-chain identity key (scope|group|lane|is_entry|to_stage) to id."
  value       = { for key, m in module.gate_chain : key => m.gate_chain_id }
}
