terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }

  required_version = ">= 0.14.9"
}

provider "aws" {
  profile = var.aws_profile
  region = var.aws_region
  #max_retries = 1
}

data "aws_region" "current" {}

######################################################################
# Create a VPC for application workloads we need to monitor
resource "aws_vpc" "apps" {
  cidr_block = "192.168.128.0/18"
  enable_dns_hostnames = true
  tags = {
    Name = "${var.project_name}.apps"
    Project = var.project_name
    Owner = var.project_owner
  }
}

resource "aws_subnet" "apps_public" {
  vpc_id                  = aws_vpc.apps.id
  cidr_block              = "192.168.128.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}.apps_public"
    Project = var.project_name
    Owner = var.project_owner
  }
}

resource "aws_internet_gateway" "apps_igw" {
  vpc_id = aws_vpc.apps.id

  tags = {
    Name = "${var.project_name}.apps_igw"
    Project = var.project_name
    Owner = var.project_owner
  }
}

resource "aws_route" "apps_default" {
  route_table_id            = aws_vpc.apps.main_route_table_id
  destination_cidr_block    = "0.0.0.0/0"
  gateway_id                = aws_internet_gateway.apps_igw.id
}

resource "aws_security_group" "apps_base" {
  name        = "${var.project_name}.apps_base"
  description = "Base access ruless"
  vpc_id      = aws_vpc.apps.id

  ingress {
    description      = "SSH Access"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["${var.mgmt_cidr}"]
  }

  egress {
    description      = "Outbound traffic"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "${var.project_name}.apps_mgmt"
    Project = var.project_name
    Owner = var.project_owner
  }
}




######################################################################
# Create an EC2 instance "app" using Ubuntu 20.04LTS

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

data "aws_key_pair" "ssh_key" {
  filter {
    name   = "tag:Owner"
    values = ["${var.project_owner}"]
  }
}

resource "aws_instance" "app" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.apps_public.id
  key_name      = data.aws_key_pair.ssh_key.key_name
  vpc_security_group_ids = [aws_security_group.apps_base.id]

  tags = {
    Name = "${var.project_name}.app"
    Project = var.project_name
    Owner = var.project_owner
  }
}