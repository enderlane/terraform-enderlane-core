output "edge_config_id" {
  description = "Id of the edge provider config."
  value       = enderlane_edge_provider_config.this.id
}

output "provider_kind" {
  description = "The edge provider kind (CLOUDFLARE or CLOUDFRONT)."
  value       = enderlane_edge_provider_config.this.provider_kind
}
