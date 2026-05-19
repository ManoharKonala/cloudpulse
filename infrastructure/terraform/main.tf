terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ── VPC ──────────────────────────────────────────────────────────────
resource "aws_vpc" "cloudpulse_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "cloudpulse-vpc" }
}

# ── Subnet ───────────────────────────────────────────────────────────
resource "aws_subnet" "cloudpulse_subnet" {
  vpc_id                  = aws_vpc.cloudpulse_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"
  tags = { Name = "cloudpulse-subnet" }
}

# ── Internet Gateway ─────────────────────────────────────────────────
resource "aws_internet_gateway" "cloudpulse_igw" {
  vpc_id = aws_vpc.cloudpulse_vpc.id
  tags = { Name = "cloudpulse-igw" }
}

# ── Route Table ──────────────────────────────────────────────────────
resource "aws_route_table" "cloudpulse_rt" {
  vpc_id = aws_vpc.cloudpulse_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.cloudpulse_igw.id
  }
  tags = { Name = "cloudpulse-rt" }
}

resource "aws_route_table_association" "cloudpulse_rta" {
  subnet_id      = aws_subnet.cloudpulse_subnet.id
  route_table_id = aws_route_table.cloudpulse_rt.id
}

# ── Security Group ───────────────────────────────────────────────────
resource "aws_security_group" "cloudpulse_sg" {
  name        = "cloudpulse-sg"
  description = "CloudPulse application security group"
  vpc_id      = aws_vpc.cloudpulse_vpc.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTP Frontend"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Jenkins"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Grafana"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Prometheus"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Product Service"
    from_port   = 5001
    to_port     = 5001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Order Service"
    from_port   = 5002
    to_port     = 5002
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "cloudpulse-sg" }
}

# ── SSH Key Pair ─────────────────────────────────────────────────────
resource "aws_key_pair" "cloudpulse_key" {
  key_name   = "cloudpulse-key"
  public_key = file(var.public_key_path)
}

# ── App EC2 Instance ─────────────────────────────────────────────────
resource "aws_instance" "cloudpulse_app" {
  ami                    = var.ami_id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.cloudpulse_subnet.id
  vpc_security_group_ids = [aws_security_group.cloudpulse_sg.id]
  key_name               = aws_key_pair.cloudpulse_key.key_name

  user_data = <<-EOF
    #!/bin/bash
    set -e
    
    # Create a 2GB Swap file to prevent OOM on t2.micro
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo "/swapfile none swap sw 0 0" >> /etc/fstab

    apt-get update -y
    apt-get install -y docker.io docker-compose git
    systemctl start docker
    systemctl enable docker
    usermod -aG docker ubuntu
    mkdir -p /opt/cloudpulse
    chown ubuntu:ubuntu /opt/cloudpulse
  EOF

  tags = { Name = "cloudpulse-app-server" }
}

# ── Jenkins EC2 Instance ─────────────────────────────────────────────
resource "aws_instance" "cloudpulse_jenkins" {
  ami                    = var.ami_id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.cloudpulse_subnet.id
  vpc_security_group_ids = [aws_security_group.cloudpulse_sg.id]
  key_name               = aws_key_pair.cloudpulse_key.key_name

  user_data = <<-EOF
    #!/bin/bash
    set -e
    
    # Create a 2GB Swap file to prevent OOM on t2.micro
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo "/swapfile none swap sw 0 0" >> /etc/fstab

    apt-get update -y
    apt-get install -y openjdk-21-jdk docker.io git curl python3-pip
    systemctl start docker
    systemctl enable docker

    # Install Jenkins securely
    curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | tee /etc/apt/sources.list.d/jenkins.list > /dev/null
    
    apt-get update -y
    apt-get install -y jenkins
    systemctl start jenkins
    systemctl enable jenkins
    usermod -aG docker jenkins
  EOF

  tags = { Name = "cloudpulse-jenkins-server" }
}

# ── Outputs ──────────────────────────────────────────────────────────
output "app_server_public_ip" {
  value       = aws_instance.cloudpulse_app.public_ip
  description = "Public IP of the CloudPulse application server"
}

output "jenkins_server_public_ip" {
  value       = aws_instance.cloudpulse_jenkins.public_ip
  description = "Public IP of the Jenkins server"
}

output "jenkins_url" {
  value       = "http://${aws_instance.cloudpulse_jenkins.public_ip}:8080"
  description = "Jenkins web UI URL"
}

output "app_url" {
  value       = "http://${aws_instance.cloudpulse_app.public_ip}"
  description = "CloudPulse frontend URL"
}

output "grafana_url" {
  value       = "http://${aws_instance.cloudpulse_app.public_ip}:3000"
  description = "Grafana dashboard URL"
}

output "prometheus_url" {
  value       = "http://${aws_instance.cloudpulse_app.public_ip}:9090"
  description = "Prometheus UI URL"
}
