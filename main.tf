provider "aws" {
  region = "us-west-2"
  profile = "default"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "testvpc"

  cidr = "10.0.0.0/16"

  azs             = ["us-west-2a", "us-west-2b"]
  public_subnets  = ["10.0.0.0/24", "10.0.1.0/24"]
  private_subnets = ["10.0.2.0/24", "10.0.3.0/24"]

  enable_nat_gateway = true
  
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  # TODO - restrict subnet ACLs, default allows all ingress/egress
}

module "alb_80_security_group" {
  source  = "terraform-aws-modules/security-group/aws//modules/http-80"

  name = "alb_sg"

  vpc_id = module.vpc.vpc_id
  ingress_cidr_blocks = ["0.0.0.0/0"]
}

module "ec2_private_80_security_group" {
  source  = "terraform-aws-modules/security-group/aws//modules/http-80"

  # TODO - Restrict Port 80 traffic to only ALB SG. *UNUSED Currently*
  name = "web_albtoec2_sg"
  vpc_id = module.vpc.vpc_id
}

module "ssh_security_group" {
  source  = "terraform-aws-modules/security-group/aws//modules/ssh"

  # TODO - Restrict SSH further.
  name = "ssh_wildcard"
  vpc_id = module.vpc.vpc_id
  ingress_cidr_blocks = ["0.0.0.0/0"]
}

module "ec2-instance_web" {
  source = "terraform-aws-modules/ec2-instance/aws"
  
  name = "web"
  ami = "ami-02d40d11bb3aaf3e5"   # Red Hat 7
  key_name = "lab1" # Define pre-existing SSH keypair instead of creating new one with modules/terraform-aws-modules/key-pair
  instance_type = "t2.micro"
  subnet_id = module.vpc.public_subnets[0]
  
  
  vpc_security_group_ids = [module.alb_80_security_group.this_security_group_id, module.ssh_security_group.this_security_group_id]
  
  # Ensure root device is 20GB, per requirements
  root_block_device = [{
    volume_size           = "20"
  }]
  # Use user-data to install, enable, and start httpd
  user_data_base64 = "IyEvYmluL2Jhc2gKeXVtIC15IGluc3RhbGwgaHR0cGQKc3lzdGVtY3RsIGVuYWJsZSBodHRwZApzeXN0ZW1jdGwgc3RhcnQgaHR0cGQK"
}

module "ec2-instance_private" {
  source = "terraform-aws-modules/ec2-instance/aws"
  name = "private"

  ami = "ami-02d40d11bb3aaf3e5"  # Red Hat 7
  key_name = "lab1" # Define pre-existing SSH keypair instead of creating new one with modules/terraform-aws-modules/key-pair
  instance_type = "t2.micro"
  vpc_security_group_ids = [module.ssh_security_group.this_security_group_id]
  subnet_id = module.vpc.private_subnets[0]
  # Ensure root device is 20GB, per requirements
  root_block_device = [{
    volume_size           = "20"
  }]
}

## Create ALB, Port 80 listener, and empty target group
module "alb" {
  source  = "terraform-aws-modules/alb/aws"

  name = "test-alb"

  load_balancer_type = "application"

  vpc_id             = module.vpc.vpc_id
  subnets            = module.vpc.public_subnets
  
  # allow port 80 from 0.0.0.0/0 source for testing 
  security_groups    = [module.alb_80_security_group.this_security_group_id]

  target_groups = [
    {
      name_prefix      = "test-"
      backend_protocol = "HTTP"
      backend_port     = 80
      target_type      = "instance"
    }
  ]

  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
      target_group_index = 0
    }
  ]
}

# terraform-aws-modules/alb/aws can't handle attaching instance to target group yet. Defined attachment manually here.
resource "aws_lb_target_group_attachment" "test" {
  target_group_arn = module.alb.target_group_arns[0]
  target_id        = module.ec2-instance_web.id[0]
}