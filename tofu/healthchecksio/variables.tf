variable "check_name" {
  description = "Display name of the healthchecks.io check."
  type        = string
  default     = "nexoflow-prometheus-watchdog"
}

variable "check_desc" {
  description = "Description shown in the healthchecks.io UI."
  type        = string
  default     = "Dead-man's switch for the nexoflow k3s cluster. Alertmanager pings this every 5 min while Prometheus is alive (Watchdog rule). If the pings stop, Prometheus/Alertmanager is down. See nexoflow-k8s-apps/apps/observability."
}

# Expected ping period. The Alertmanager Watchdog pings every 5 min, so a 10-min
# period with a 5-min grace means a single delayed ping won't false-alarm but a
# real outage surfaces within ~15 min (matches src/observability/README.md §2b).
variable "timeout_seconds" {
  description = "Expected period between pings, in seconds."
  type        = number
  default     = 600 # 10 minutes
}

variable "grace_seconds" {
  description = "Grace period after a missed ping before the check goes down, in seconds."
  type        = number
  default     = 300 # 5 minutes
}

variable "tags" {
  description = "Tags for the check (space-separated in the UI; a list here)."
  type        = list(string)
  default     = ["nexoflow", "prometheus", "dead-mans-switch"]
}

# Which healthchecks.io integrations notify you when the check goes down. This
# provider requires real integration **UUIDs** here (it rejects the API's "*"
# wildcard). Leave empty to assign none, or pass UUIDs directly. The simplest way
# to get a UUID without hardcoding it is the healthchecksio_channel data source —
# see the commented example in main.tf. Empty default keeps `apply` working out of
# the box; set channels (or enable the data source) so you actually get alerted.
variable "channels" {
  description = "Integration UUIDs to notify when the check goes down. Empty = no notifications."
  type        = list(string)
  default     = []
}
