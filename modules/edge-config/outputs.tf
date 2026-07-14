output "edge_config_id" {
  description = "Id of the edge provider config."
  value       = data.external.edge_config.result.id
}
