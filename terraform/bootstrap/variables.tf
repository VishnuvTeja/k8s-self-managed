variable "aws_region" {
  description = "AWS region for state resources"
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Project tag prefix"
  type        = string
  default     = "k8s-frankfurt"
}

variable "state_bucket_name" {
  description = "Globally unique S3 bucket name for Terraform state"
  type        = string
}

variable "dynamodb_table_name" {
  description = "DynamoDB table for Terraform state locking"
  type        = string
  default     = "k8s-frankfurt-terraform-locks"
}
