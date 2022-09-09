resource "aws_vpc" "dataplane_vpc" {
  cidr_block           = var.cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "${local.prefix}-dataplane-vpc"
  }
}

// Private Subnets
resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.dataplane_vpc.id
  count                   = length(local.private_subnets_cidr)
  cidr_block              = element(local.private_subnets_cidr, count.index)
  availability_zone       = element(local.availability_zones, count.index)
  map_public_ip_on_launch = false
  tags = {
    Name = "${local.prefix}-private-${element(local.availability_zones, count.index)}"
  }
}

resource "aws_network_acl" "dataplane" {
  vpc_id = aws_vpc.dataplane_vpc.id
  subnet_ids = concat(aws_subnet.private[*].id, aws_subnet.public[*].id)

  ingress {
    protocol   = "all"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
  
  egress {
    protocol   = "all"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.cidr_block
    from_port  = 0
    to_port    = 0
  }

  dynamic "egress" {
    for_each = local.sg_egress_ports
    content {
      from_port   = egress.value
      to_port     = egress.value
      protocol    = "tcp"
      cidr_block  = "0.0.0.0/0"
      action      = "ALLOW"
      rule_no     = egress.key + 200
    }
  }
  tags = {
    Name = "${local.prefix}-nacl"
  }
}

// Public Subnet
resource "aws_subnet" "public" {

    vpc_id                  = aws_vpc.dataplane_vpc.id
    count                   = length(local.public_subnets_cidr)
    cidr_block              = element(local.public_subnets_cidr, count.index)
    availability_zone       = element(local.availability_zones, count.index)
    map_public_ip_on_launch = true
    tags = {
        Name = "${local.prefix}-public-${element(local.availability_zones, count.index)}"
     }
}

// IGW
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.dataplane_vpc.id
  tags = {
    Name = "${local.prefix}-igw"
  }
}

// EIP
resource "aws_eip" "ngw_eip" {
  count      = length(local.public_subnets_cidr)
  vpc        = true
}

// NGW
resource "aws_nat_gateway" "ngw" {
  count         = length(local.public_subnets_cidr)
  allocation_id = element(aws_eip.ngw_eip.*.id, count.index)
  subnet_id     = element(aws_subnet.public.*.id, count.index)
  depends_on    = [aws_internet_gateway.igw]
  tags = {
    Name = "${local.prefix}-ngw-${element(local.availability_zones, count.index)}"
  }
}

// SG
resource "aws_security_group" "sg" {
  name        = "${local.prefix}-sg"
  description = "Databricks Data Plane SG"
  vpc_id = aws_vpc.dataplane_vpc.id
  depends_on  = [aws_vpc.dataplane_vpc]

  dynamic "ingress" {
    for_each = local.sg_ingress_protocol
    content {
      from_port = 0
      to_port   = 65535
      protocol  = ingress.value
      self      = true
    }
  }

  dynamic "egress" {
    for_each = local.sg_egress_protocol
    content {
      from_port = 0
      to_port   = 65535
      protocol  = egress.value
      self      = true
    }
  }

  dynamic "egress" {
    for_each = local.sg_egress_ports
    content {
      from_port   = egress.value
      to_port     = egress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  tags = {
    Name = "${local.prefix}-sg"
  }
}

// Private RT
resource "aws_route_table" "private_rt" {
  count              = length(local.private_subnets_cidr)
  vpc_id             = aws_vpc.dataplane_vpc.id
  tags = {
    Name = "${local.prefix}-private-rt-${element(local.availability_zones, count.index)}"
  }
}

// Public RT
resource "aws_route_table" "public_rt" {
    count              = length(local.public_subnets_cidr)
    vpc_id            = aws_vpc.dataplane_vpc.id
    tags  = {
      Name = "${local.prefix}-public-rt-${element(local.availability_zones, count.index)}"
  }
}

// Private RT Associations
resource "aws_route_table_association" "private" {
  count          = length(local.private_subnets_cidr)
  subnet_id      = element(aws_subnet.private.*.id, count.index)
  route_table_id = element(aws_route_table.private_rt.*.id, count.index)
}

// Public RT Associations
resource "aws_route_table_association" "public" {
  count          = length(local.public_subnets_cidr)
  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = element(aws_route_table.public_rt.*.id, count.index)
  depends_on = [aws_subnet.public]
}

// Private Route
resource "aws_route" "private_ngw" {
  count                  = length(local.private_subnets_cidr)
  route_table_id         = element(aws_route_table.private_rt.*.id, count.index)
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = element(aws_nat_gateway.ngw.*.id, count.index)
}

// Public Route
resource "aws_route" "public_igw" {
  count                  = length(local.public_subnets_cidr)
  route_table_id         = element(aws_route_table.public_rt.*.id, count.index)
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             =  aws_internet_gateway.igw.id
}