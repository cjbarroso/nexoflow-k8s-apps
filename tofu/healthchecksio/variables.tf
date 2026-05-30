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

# Which healthchecks.io integrations notify you when the check goes down (email,
# Telegram, etc.). "*" assigns ALL integrations configured in the project, so you
# actually get alerted. Set to a specific list of integration UUIDs to narrow it,
# or [] to assign none. Integrations themselves are configured in the HC.io UI.
variable "channels" {
  description = "Integration UUIDs to notify, or [\"*\"] for all configured integrations."
  type        = list(string)
  default     = ["*"]
}
