variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "ami_id" {
  description = "Ubuntu 22.04 LTS AMI ID (us-east-1)"
  type        = string
  default     = "ami-0261755bbcb8c4a84"
}

variable "public_key_path" {
  description = "Path to the SSH public key file for EC2 access"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}
