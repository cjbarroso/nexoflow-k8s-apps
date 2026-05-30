# The ping URL is the heartbeat target Alertmanager calls. It is a credential
# (anyone with it can spoof the "alive" ping), so it is marked sensitive and must
# never be committed. Pull it after apply with:
#   tofu output -raw ping_url
# then seal it into the cluster per src/observability/README.md §2b.
output "ping_url" {
  description = "healthchecks.io ping URL — seal into the prometheus-hc-ping Secret."
  value       = healthchecksio_check.watchdog.ping_url
  sensitive   = true
}

output "check_name" {
  description = "Name of the created check."
  value       = healthchecksio_check.watchdog.name
}
