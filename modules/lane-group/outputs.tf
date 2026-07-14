output "lane_group_id" {
  description = "Id of the lane group."
  value       = enderlane_lane_group.this.id
}

output "lane_ids" {
  description = "Map of lane name to id."
  value       = { for name, r in enderlane_lane.this : name => r.id }
}

output "stage_ids" {
  description = "Map of group-override stage name to id."
  value       = { for name, r in enderlane_stage.this : name => r.id }
}
