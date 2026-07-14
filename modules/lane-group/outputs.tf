output "lane_group_id" {
  description = "Id of the lane group."
  value       = data.external.group.result.id
}

output "lane_ids" {
  description = "Map of lane name to id."
  value       = { for name, d in data.external.lane : name => d.result.id }
}

output "stage_ids" {
  description = "Map of group-override stage name to id."
  value       = { for name, d in data.external.stage : name => d.result.id }
}
