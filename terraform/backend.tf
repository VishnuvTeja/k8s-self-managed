# Remote state — configure via backend.hcl (copy from backend.hcl.example).
# One-time setup: cd bootstrap && terraform apply
# Then: terraform init -backend-config=backend.hcl

terraform {
  backend "s3" {}
}
