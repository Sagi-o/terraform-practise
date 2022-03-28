terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

variable "subnet_prefix" {
    description = "CIDR block for the subnet"
    type = string # number / bool / list(<TYPE>) set(<TYPE>) / map(<TYPE>) / object({<ATTR NAME> = <TYPE>, ... }) / tuple([<TYPE>, ...])
    default = "10.0.1.0/24" # default will make it optional
}

# Configure the AWS Provider
provider "aws" {
  region     = "eu-central-1"
  access_key = ""
  secret_key = ""
}

# 1. Create a VPC
resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "production_vpc"
  }
}

# 2. Create and Internet Gateway
resource "aws_internet_gateway" "gateway" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "production_gateway"
  }
}


# 3. Create Custom Route Table
resource "aws_route_table" "route_table" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0" # Send all IPv4 traffic to where this route points
    gateway_id = aws_internet_gateway.gateway.id
  }

  route {
    ipv6_cidr_block        = "::/0" # All IPv6 traffic
    gateway_id = aws_internet_gateway.gateway.id
  }

  tags = {
    Name = "production_route_table"
  }
}

# 4. Create a Subnet
resource "aws_subnet" "subnet" {
  vpc_id            = aws_vpc.vpc.id  # Local id of resource on Terraform
  cidr_block        = var.subnet_prefix  # Needed to be on the range of our VPC cidr_block (24 1's is after th 16 on the VPC block)
  availability_zone = "eu-central-1a" # Hardcodeed zone, else AWS will randomly choose one

  tags = {
    Name = "production_subnet"
  }
}

# 5. Associate subnet with Route Table
resource "aws_route_table_association" "subnet_to_route_table" {
  subnet_id      = aws_subnet.subnet.id
  route_table_id = aws_route_table.route_table.id
}

# 6. Create Security Group to allow port 22 (SSH), 80 (HTTP), 443 (HTTPS)
resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow Web inbound traffic"
  vpc_id      = aws_vpc.vpc.id

  # From world to server
  ingress {
    description      = "HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"] # Every IPv4 address can access from outside
    ipv6_cidr_blocks = ["::/0"]      # Every IPv6 address can access from outside
  }

  ingress {
    description      = "HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"] # Every IPv4 address can access from outside
    ipv6_cidr_blocks = ["::/0"]      # Every IPv6 address can access from outside
  }

  ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"] # Every IPv4 address can access from outside
    ipv6_cidr_blocks = ["::/0"]      # Every IPv6 address can access from outside
  }

  # From server to the outside world
  egress {
    from_port        = 0    # All ports
    to_port          = 0    # All ports
    protocol         = "-1" # Any protocol
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_web_traffic"
  }
}

# 7. Create a network interface with an IP in the subnet that was created in step 4 (Private IP)
resource "aws_network_interface" "web_server_nic" {
  subnet_id       = aws_subnet.subnet.id
  private_ips     = ["10.0.1.50"] # "Any" IP from our subnet. Our subnet is: "10.0.1.x" - choose x
  security_groups = [aws_security_group.allow_web.id]

  #   attachment {
  #     instance     = aws_instance.test.id
  #     device_index = 1
  #   }
}

# 8. Assign an elastic (public) IP to the network interface created in step 7 (aws_eip relies on internet_gateway)
resource "aws_eip" "elastic_ip" {
  vpc                       = true
  network_interface         = aws_network_interface.web_server_nic.id
  associate_with_private_ip = "10.0.1.50"                  # Some private IP to point to
#   depeneds_on               = [aws_internet_gateway.gateway] # Explicit dependecy on the gateway resource, or any other depedency
}

# Output "aws_eip.elastic_ip.public_ip"
output "server_public_ip" {
    value = aws_eip.elastic_ip.public_ip
}

# 9. Create Ubuntu server and install/enable apache2
resource "aws_instance" "web_server_instance" {
  ami               = "ami-0d527b8c289b4af7f"
  instance_type     = "t2.micro"
  availability_zone = "eu-central-1a" # Same zone as subnet
#   key_pair          = "terraform-key-pair"

  # Attach a network interface to an EC2 instance during boot time
  network_interface {
    device_index         = 0 # The first network interface that associated with this device
    network_interface_id = aws_network_interface.web_server_nic.id
  }

  user_data = <<-EOF
            #!/bin/bash
            sudo apt update -y
            sudo apt install apache2 -y
            sudo systemctl start apache2
            sudo bash -c 'echo Your very first web server with Terraform > /var/www/html/index.html'
            EOF


  tags = {
    Name = "web_server"
  }
}

# Output "aws_instance.web_server_instance.private_ip"
output "server_private_ip" {
    value = aws_instance.web_server_instance.private_ip
}

# commands:
# terraform init
# terraform plan

# terraform apply --auto-approve
# terraform apply -target aws_instance.my_first_server
# terraform apply -var-file terraform.tfvars

# terraform destroy
# terraform destroy -target aws_instance.my_first_server

# terraform state list
# terraform state show aws_vpc.my_vpc
# terraform output
# terraform refresh

# terraform apply -var "subnet_prefix=10.0.100/24"