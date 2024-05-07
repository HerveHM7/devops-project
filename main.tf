terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "us-west-1"
}

resource "aws_vpc" "hmtfVPC" {
  cidr_block = var.vpc_cidr
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.hmtfVPC.id
}

resource "aws_route_table" "public-tf-RT" {
  vpc_id = aws_vpc.hmtfVPC.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_subnet" "public-tf-subnet" {
  vpc_id     = aws_vpc.hmtfVPC.id
  cidr_block = var.subnet_cidr
}

resource "aws_subnet" "public-tf-subnet2" {
  vpc_id     = aws_vpc.hmtfVPC.id
  cidr_block = var.subnet2_cidr
}

resource "aws_route_table_association" "rt-ass-tf1" {
  subnet_id      = aws_subnet.public-tf-subnet.id
  route_table_id = aws_route_table.public-tf-RT.id
}

resource "aws_route_table_association" "rt-ass-tf2" {
  subnet_id      = aws_subnet.public-tf-subnet2.id
  route_table_id = aws_route_table.public-tf-RT.id
}

resource "aws_security_group" "tf-sg-ec2" {
  name        = "tf-sg-ec2"
  description = "Allow ports 22 and 80 for all"
  vpc_id      = aws_vpc.hmtfVPC.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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

resource "aws_security_group" "tf-sg-alb" {
  name        = "tf-sg-alb"
  description = "Allow port 80 for all"
  vpc_id      = aws_vpc.hmtfVPC.id

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

resource "aws_security_group" "tf-sg-rds" {
  name        = "tf-sg-rds"
  description = "Allow port 3306 for all"
  vpc_id      = aws_vpc.hmtfVPC.id

  ingress {
    from_port   = 3306
    to_port     = 3306
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

resource "aws_launch_configuration" "hm0224-tf-ec2" {
  name            = "hm0224-tf-ec2"
  image_id        = var.ami_id
  instance_type   = var.instance_type
  security_groups = [aws_security_group.tf-sg-ec2.id]
}

resource "aws_autoscaling_group" "tf-asg-ec2" {
  launch_configuration = aws_launch_configuration.hm0224-tf-ec2.id
  min_size             = 2
  max_size             = 5
  desired_capacity     = 2
  vpc_zone_identifier  = [aws_subnet.public-tf-subnet.id, aws_subnet.public-tf-subnet2.id]

  tag {
    key                 = "Name"
    value               = "tf-asg-ec2"
    propagate_at_launch = true
  }
}

resource "aws_lb_target_group" "tf-lb-tg" {
  name     = "tf-lb-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.hmtfVPC.id
}

resource "aws_lb" "web-app-lb" {
  name               = "web-app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.tf-sg-alb.id]
  subnets            = [aws_subnet.public-tf-subnet.id, aws_subnet.public-tf-subnet2.id]
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.web-app-lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tf-lb-tg.arn
  }
}

resource "aws_s3_bucket" "tf-hm-s3-bucket" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_acl" "tf-hm-s3-bucket" {
  bucket = aws_s3_bucket.tf-hm-s3-bucket.id
  acl    = "private"
}

resource "aws_iam_role" "example" {
  name = "example_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
      },
    ],
  })
}

resource "aws_iam_role_policy" "example" {
  name = "example_role"
  role = aws_iam_role.example.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "s3:*",
        ],
        Effect   = "Allow",
        Resource = "*",
      },
    ],
  })
}

resource "aws_db_subnet_group" "tf_rds_db_subnet_group" {
  name       = "tf_rds_db_subnet_group"
  subnet_ids = [aws_subnet.public-tf-subnet.id, aws_subnet.public-tf-subnet2.id]
}

resource "aws_db_instance" "mydb" {
  allocated_storage      = 20
  storage_type           = "gp2"
  engine                 = "mysql"
  engine_version         = "5.7"
  instance_class         = "db.t2.micro"
  db_name                = "mydb"
  username               = "user"
  password               = "pass"
  parameter_group_name   = "default.mysql5.7"
  db_subnet_group_name   = aws_db_subnet_group.tf_rds_db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.tf-sg-rds.id]
}
