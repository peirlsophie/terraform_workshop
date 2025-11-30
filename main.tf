provider "aws" {
  region = "us-east-1"
}

# VPC
# Creates a VPC 

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "TerraformVPC"
  }
}

# Internet Gateway
# Creates an internet gateway

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "TerraformGateway"
  }
}

# Route Table
# creates a custom route table

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "TerraformRouteTable"
  }
}

# Subnets
# the load balancer requires at least two 2 public subnets in different availability zones

resource "aws_subnet" "subnet_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "TerraformSubnetA"
  }
}

resource "aws_subnet" "subnet_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "TerraformSubnetB"
  }
}


# Route table associations

resource "aws_route_table_association" "rta_a" {
  subnet_id      = aws_subnet.subnet_a.id
  route_table_id = aws_route_table.rt.id
}

resource "aws_route_table_association" "rta_b" {
  subnet_id      = aws_subnet.subnet_b.id
  route_table_id = aws_route_table.rt.id
}

# Security Groups
# allows ingress traffic port through tcp port 80
# allows everything egress traffic 

resource "aws_security_group" "web_sg" {
  name        = "web-sg"
  description = "Allow HTTP inbound, all outbound"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "lb_sg" {
  name   = "lb-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Load Balancer
# routes to created instances 

resource "aws_lb" "app_lb" {
  name               = "terraform-workshop-lb"
  load_balancer_type = "application"

  subnets = [
    aws_subnet.subnet_a.id,
    aws_subnet.subnet_b.id
  ]

  security_groups = [aws_security_group.lb_sg.id]
}

# Target Group
# decides which instance receives the traffic from the load balancer 

resource "aws_lb_target_group" "tg" {
  name     = "terraform-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

# Listener
# listens for connections on port 80 and forwards traffic to target group

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# EC2 Instances
# two instances are created

resource "aws_instance" "web" {
  count = 2

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  subnet_id              = element([aws_subnet.subnet_a.id, aws_subnet.subnet_b.id], count.index)
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y apache2
              systemctl enable apache2
              systemctl start apache2
              echo "<h1>Hello from instance ${count.index}</h1>" > /var/www/html/index.html
              EOF

  tags = {
    Name = "Terraform-Web-${count.index}"
  }
}

# Attach instances to Target Group

resource "aws_lb_target_group_attachment" "attach" {
  count = 2

  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.web[count.index].id
  port             = 80
}

# AMI Data Source

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
}

# Outputs
# Load balancers dns address

output "load_balancer_dns" {
  value = aws_lb.app_lb.dns_name
}
