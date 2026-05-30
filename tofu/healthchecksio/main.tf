resource "healthchecksio_check" "watchdog" {
  name     = var.check_name
  desc     = var.check_desc
  timeout  = var.timeout_seconds
  grace    = var.grace_seconds
  tags     = var.tags
  channels = var.channels
}
