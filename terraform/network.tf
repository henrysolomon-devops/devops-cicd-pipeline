# The VPC my EC2 instance is going to live in. AWS won't let you launch
# a server without one, so even for a single box this is step one.
# 10.0.0.0/16 is way more address space than I need, but it's the
# conventional starting range everyone uses, so no point deviating.
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "devops-pipeline-vpc"
  }
}

# Just a slice carved out of the VPC above. Calling it "public" because
# I'm about to give it a route to the internet below - that's what
# actually makes it public, not the name by itself.
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"

  tags = {
    Name = "devops-pipeline-public-subnet"
  }
}

# This is the actual door between my VPC and the internet. Without it
# the server could exist just fine internally, but nothing outside AWS
# could ever reach it, and it couldn't reach out either.
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "devops-pipeline-igw"
  }
}

# Route table - basically directions for traffic. This one just says:
# anything leaving the VPC (0.0.0.0/0) goes out through the gateway above.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "devops-pipeline-public-rt"
  }
}

# The route table doesn't do anything until it's actually attached to a
# subnet - this is that attachment, applying the rule above to my subnet.
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}