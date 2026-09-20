locals {
  common_tags = merge(
    {
      Environment = var.environment
      ManagedBy   = "terraform"
      Project     = var.project
      Repository  = "scientificcalculator"
    },
    var.tags,
  )
}
