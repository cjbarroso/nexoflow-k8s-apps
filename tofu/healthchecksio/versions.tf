terraform {
  # OpenTofu. (Also works with Terraform >= 1.0.)
  required_version = ">= 1.6.0"

  # State is LOCAL by default. Locally that's a file on your disk; in CI it is
  # carried between runs via the Actions cache (see the workflow). For a more
  # robust setup, enable a real remote backend instead — e.g. the cluster's
  # S3-compatible object store — and drop the cache step from the workflow:
  #
  # backend "s3" {
  #   bucket                      = "tofu-state"
  #   key                         = "healthchecksio/terraform.tfstate"
  #   region                      = "us-east-1"      # ignored by most non-AWS S3
  #   endpoints                   = { s3 = "https://<minio-or-r2-endpoint>" }
  #   skip_credentials_validation = true
  #   skip_region_validation      = true
  #   skip_requesting_account_id  = true
  #   use_path_style              = true
  #   # AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY come from env / CI secrets.
  # }

  required_providers {
    healthchecksio = {
      source  = "kristofferahl/healthchecksio"
      version = "~> 2.3"
    }
  }
}
