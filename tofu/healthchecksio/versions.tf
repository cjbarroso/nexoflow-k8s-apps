terraform {
  # OpenTofu. (Also works with Terraform >= 1.0.)
  required_version = ">= 1.6.0"

  # Remote state in Cloudflare R2 (migrated 2026-06-11 from the Actions-cache
  # hack, whose 7-day eviction could orphan the state and duplicate the check).
  # Same bucket the backup systems use, under its own tofu/ prefix.
  # Credentials: AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY from env — in CI the
  # repo secrets R2_TOFU_ACCESS_KEY_ID / R2_TOFU_SECRET_ACCESS_KEY.
  # No state locking on R2 with tofu 1.9 (S3 locking needs DynamoDB or
  # tofu >=1.10 use_lockfile); the workflow's concurrency group serializes runs.
  backend "s3" {
    bucket                      = "velero-backups"
    key                         = "tofu/healthchecksio.tfstate"
    region                      = "auto"
    endpoints                   = { s3 = "https://77df3d66af9eb572fe180d800d44127b.r2.cloudflarestorage.com" }
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
    use_path_style              = true
  }

  required_providers {
    healthchecksio = {
      source  = "kristofferahl/healthchecksio"
      version = "~> 2.3"
    }
  }
}
