
data "aws_availability_zones" "available" {
}

module "vpc" {
  source  = "terraform-registry.apps.internal/terraform-aws-modules/vpc/aws"
  version = "3.11.4"
  name    = "solr-${var.instance_name}-vpc"
  cidr    = "10.31.0.0/16"

  azs = data.aws_availability_zones.available.names
  # These subnets represent AZs us-west-2a, us-west-2b, and us-west-2c
  # This gives us 8187 IP addresses that can be given to nodes and (via the VPC-CNI add-on) pods.
  private_subnets = ["10.31.0.0/19", "10.31.32.0/19"]    # , "10.31.64.0/19"]
  public_subnets  = ["10.31.128.0/19", "10.31.160.0/19"] # , "10.31.192.0/19"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  # Tag subnets for use by AWS' load-balancers and the ALB ingress controllers
  # See https://aws.amazon.com/premiumsupport/knowledge-center/eks-vpc-subnet-discovery/
  tags = var.labels
  # tags = merge(var.labels, {
  #   "domain"                                      = local.domain
  # })
}

resource "aws_security_group_rule" "allow-efs" {
  type              = "ingress"
  from_port         = 2049
  to_port           = 2049
  protocol          = "tcp"
  cidr_blocks       = module.vpc.private_subnets_cidr_blocks
  security_group_id = module.vpc.default_security_group_id
}
resource "aws_security_group_rule" "allow-efs-b" {
  type              = "egress"
  from_port         = 2049
  to_port           = 2049
  protocol          = "tcp"
  cidr_blocks       = module.vpc.private_subnets_cidr_blocks
  security_group_id = module.vpc.default_security_group_id
}
resource "aws_security_group_rule" "allow-lb" {
  type                     = "ingress"
  from_port                = 8983
  to_port                  = 8983
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.solr-lb-sg.id
  security_group_id        = module.vpc.default_security_group_id
}
resource "aws_security_group_rule" "allow-lb-b" {
  type                     = "egress"
  from_port                = 8983
  to_port                  = 8983
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.solr-lb-sg.id
  security_group_id        = module.vpc.default_security_group_id
}
resource "aws_security_group_rule" "allow-egress-vpc" {
  type              = "egress"
  from_port         = 0
  to_port           = 65535
  protocol          = "-1"
  cidr_blocks       = [module.vpc.vpc_cidr_block]
  security_group_id = module.vpc.default_security_group_id
}

resource "aws_security_group_rule" "allow-ingress-vpc" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "-1"
  cidr_blocks       = [module.vpc.vpc_cidr_block]
  security_group_id = module.vpc.default_security_group_id
}
