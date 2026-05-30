# To get notified when the dead-man's switch trips, assign notification channels.
# This provider needs channel UUIDs (it rejects the API's "*" wildcard), but you
# can look one up by kind instead of hardcoding it. Every healthchecks.io account
# has an "email" integration to the account address, so this resolves out of the
# box; change kind to "telegram", "slack", etc. for others. Uncomment, then set
# the resource's channels to: concat(var.channels, [data.healthchecksio_channel.email.id])
#
# data "healthchecksio_channel" "email" {
#   kind = "email"
# }

resource "healthchecksio_check" "watchdog" {
  name     = var.check_name
  desc     = var.check_desc
  timeout  = var.timeout_seconds
  grace    = var.grace_seconds
  tags     = var.tags
  channels = var.channels
}
