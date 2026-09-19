data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  az_count           = 3
  availability_zones = slice(data.aws_availability_zones.available.names, 0, local.az_count)

  public_subnet_cidrs = [for index in range(local.az_count) : cidrsubnet(var.vpc_cidr, 4, index)]
  private_subnet_cidrs = [
    for index in range(local.az_count) : cidrsubnet(var.vpc_cidr, 4, index + local.az_count)
  ]

  cluster_tag_key = "kubernetes.io/cluster/${var.cluster_name}"

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
