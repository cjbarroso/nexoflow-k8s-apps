terraform {
  # OpenTofu. (Also works with Terraform >= 1.0.)
  required_version = ">= 1.6.0"

  required_providers {
    healthchecksio = {
      source  = "kristofferahl/healthchecksio"
      version = "~> 2.3"
    }
  }
}
