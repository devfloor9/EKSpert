resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  
  tags = {
    Name = var.vpc_name
    "kubernetes.io/cluster/${var.vpc_name}" = "shared"
  }
}

# Create private subnets
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)
  
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  
  tags = {
    Name = "${var.vpc_name}-private-${var.availability_zones[count.index]}"
    "kubernetes.io/cluster/${var.vpc_name}" = "shared"
    "kubernetes.io/role/internal-elb" = "1"
    "karpenter.sh/discovery" = var.vpc_name  # For Karpenter auto-discovery
  }
}

# Create public subnets
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)
  
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  
  tags = {
    Name = "${var.vpc_name}-public-${var.availability_zones[count.index]}"
    "kubernetes.io/cluster/${var.vpc_name}" = "shared"
    "kubernetes.io/role/elb" = "1"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  
  tags = {
    Name = "${var.vpc_name}-igw"
  }
}

# Elastic IPs for NAT Gateways
resource "aws_eip" "nat" {
  count = length(var.public_subnet_cidrs)
  domain = "vpc"
  
  tags = {
    Name = "${var.vpc_name}-nat-eip-${count.index}"
  }
}

# NAT Gateways
resource "aws_nat_gateway" "nat" {
  count = length(var.public_subnet_cidrs)
  
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  
  tags = {
    Name = "${var.vpc_name}-nat-${var.availability_zones[count.index]}"
  }
  
  depends_on = [aws_internet_gateway.igw]
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  
  tags = {
    Name = "${var.vpc_name}-public-rt"
  }
}

# Private Route Tables
resource "aws_route_table" "private" {
  count = length(var.private_subnet_cidrs)
  
  vpc_id = aws_vpc.main.id
  
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat[count.index].id
  }
  
  tags = {
    Name = "${var.vpc_name}-private-rt-${var.availability_zones[count.index]}"
  }
}

# Associate public route table with public subnets
resource "aws_route_table_association" "public" {
  count = length(var.public_subnet_cidrs)
  
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Associate private route tables with private subnets
resource "aws_route_table_association" "private" {
  count = length(var.private_subnet_cidrs)
  
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# VPC Flow Logs 
resource "aws_flow_log" "vpc_flow_log" {
  count = var.enable_flow_logs ? 1 : 0
  
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow_logs[0].arn
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.main.id
  
  tags = {
    Name = "${var.vpc_name}-flow-logs"
  }
}

resource "aws_cloudwatch_log_group" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0
  
  name              = var.flow_logs_group_name
  retention_in_days = 30
}

# VPC Endpoints for private cluster
resource "aws_vpc_endpoint" "s3" {
  count = var.enable_vpc_endpoints ? 1 : 0
  
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id
  
  tags = {
    Name = "${var.vpc_name}-s3-endpoint"
  }
}

resource "aws_security_group" "vpc_endpoints" {
  count = var.enable_vpc_endpoints ? 1 : 0
  
  name        = "${var.vpc_name}-vpc-endpoints-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.main.id
  
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Allow HTTPS from VPC CIDR"
  }
}

# Interface VPC endpoints for private EKS
resource "aws_vpc_endpoint" "endpoints" {
  for_each = var.enable_vpc_endpoints ?  {
    "ecr-api"     = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
    "ecr-dkr"     = "com.amazonaws.${data.aws_region.current.name}.ecr.dkr"
    "ec2"         = "com.amazonaws.${data.aws_region.current.name}.ec2"
    "logs"        = "com.amazonaws.${data.aws_region.current.name}.logs"
    "sts"         = "com.amazonaws.${data.aws_region.current.name}.sts"
    "autoscaling" = "com.amazonaws.${data.aws_region.current.name}.autoscaling"
    "elasticloadbalancing" = "com.amazonaws.${data.aws_region.current.name}.elasticloadbalancing"
  } : {}
  
  vpc_id             = aws_vpc.main.id
  service_name       = each.value
  vpc_endpoint_type  = "Interface"
  security_group_ids = [aws_security_group.vpc_endpoints[0].id]
  subnet_ids         = aws_subnet.private[*].id
  private_dns_enabled = true
  
  tags = {
    Name = "${var.vpc_name}-${each.key}-endpoint"
  }
}

data "aws_region" "current" {}