output "gate_chain_id" {
  description = "Id of the gate chain config."
  value       = data.external.gate_chain.result.id
}
