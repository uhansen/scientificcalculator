variable "aws_region" {
  description = "AWS region for the backend bucket."
  type        = string
  default     = "eu-north-1"
}

variable "state_bucket_name" {
  description = "Globally unique S3 bucket name for Terraform state."
  type        = string
}

variable "tags" {
  description = "Additional tags for backend resources."
  type        = map(string)
  default     = {}
}
