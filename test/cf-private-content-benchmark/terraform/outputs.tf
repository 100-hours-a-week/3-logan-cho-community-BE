output "vm_public_ip" {
  description = "Public IPv4 address of the Azure Busan benchmark VM."
  value       = azurerm_public_ip.this.ip_address
}

output "ssh_command" {
  description = "SSH command for the benchmark VM."
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.this.ip_address}"
}

output "run_remote_command" {
  description = "Example command to copy the benchmark workspace and run the remote benchmark."
  value = join(" ", [
    "ssh ${var.admin_username}@${azurerm_public_ip.this.ip_address} \"mkdir -p ~/cf-private-content-benchmark\"",
    "&&",
    "scp -r ../. ${var.admin_username}@${azurerm_public_ip.this.ip_address}:~/cf-private-content-benchmark/",
    "&&",
    "ssh ${var.admin_username}@${azurerm_public_ip.this.ip_address}",
    "\"cd ~/cf-private-content-benchmark && npm install && node scripts/run-remote-benchmark.js --config configs/benchmark.config.json\""
  ])
}
