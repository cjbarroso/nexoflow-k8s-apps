# The provider talks to the hosted healthchecks.io SaaS (hc-ping.com), which is
# what the cluster already uses. The API key is a *project* API key from
# healthchecks.io: Project Settings -> API Access -> "API key" (read-write).
#
# Do NOT put the key in a .tf file or tfvars committed to Git. Export it instead:
#   export HEALTHCHECKSIO_API_KEY=...      (the provider reads this env var)
# api_key is intentionally omitted here so the env var is the only source.
provider "healthchecksio" {
  # api_url defaults to https://healthchecks.io/api/v1/ (the SaaS).
  # Set HEALTHCHECKSIO_API_URL only if you ever point at a self-hosted instance.
}
