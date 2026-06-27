output "state_bucket_name" {
  description = "S3 bucket for Terraform remote state"
  value       = aws_s3_bucket.terraform_state.id
}

output "dynamodb_table_name" {
  description = "DynamoDB table for state locking"
  value       = aws_dynamodb_table.terraform_locks.name
}

output "backend_config_snippet" {
  description = "Copy these values into terraform/backend.hcl"
  value       = <<-EOT
    bucket         = "${aws_s3_bucket.terraform_state.id}"
    key            = "k8s-frankfurt/terraform.tfstate"
    region         = "${var.aws_region}"
    dynamodb_table = "${aws_dynamodb_table.terraform_locks.name}"
    encrypt        = true
  EOT
}
