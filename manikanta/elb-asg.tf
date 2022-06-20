resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc-cidr
  enable_dns_hostnames = true
}

resource "aws_subnet" "subnet-a" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = var.subnet-cidr-a
  availability_zone = "${var.region}a"
}

resource "aws_subnet" "subnet-b" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = var.subnet-cidr-b
  availability_zone = "${var.region}b"
}

resource "aws_subnet" "subnet-c" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = var.subnet-cidr-c
  availability_zone = "${var.region}c"
}

resource "aws_route_table" "subnet-route-table" {
  vpc_id = aws_vpc.vpc.id
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
}

resource "aws_route" "subnet-route" {
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
  route_table_id         = aws_route_table.subnet-route-table.id
}

resource "aws_route_table_association" "subnet-a-route-table-association" {
  subnet_id      = aws_subnet.subnet-a.id
  route_table_id = aws_route_table.subnet-route-table.id
}

resource "aws_eip" "eip-for-nat" {
        vpc                  =   true
}
resource "aws_nat_gateway" "natGW" {
  depends_on = [aws_internet_gateway.igw]
  allocation_id = aws_eip.eip-for-nat.id
  subnet_id     = aws_subnet.subnet-a.id

  tags = {
    Name = " NATGwPSn"
  }
}
resource "aws_route_table" "private-route-table" {
        vpc_id               =  aws_vpc.vpc.id

        route {
                cidr_block       =     "0.0.0.0/0"
                nat_gateway_id = "${aws_nat_gateway.natGW.id}"
        }
}
resource "aws_route_table_association" "subnet-b-route-table-association" {
  subnet_id      = aws_subnet.subnet-b.id
  route_table_id = aws_route_table.private-route-table.id
}
resource "aws_route_table_association" "subnet-c-route-table-association" {
  subnet_id      = aws_subnet.subnet-c.id
  route_table_id = aws_route_table.private-route-table.id
}
data "aws_ami" "amazon-2" {
  most_recent = true
  owners = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-kernel-*-hvm-*-gp2"]
  }
  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}
resource "aws_security_group" "security-group" {
  vpc_id = aws_vpc.vpc.id

  ingress {
    from_port   = "80"
    to_port     = "80"
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
  ingress {
    from_port   = "443"
    to_port     = "443"
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
  ingress {
    from_port   = "22"
    to_port     = "22"
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
}

resource "aws_launch_configuration" "lcg" {
  name_prefix     = "aws-lcg"
  image_id        = data.aws_ami.amazon-2.id
  instance_type   = var.instanceType
  key_name        = "${var.key_name}"
  user_data       = file("user-data.sh")
  security_groups = [aws_security_group.security-group.id]

  lifecycle {
    create_before_destroy = true
  }
}



resource "aws_autoscaling_group" "asg" {
  min_size             = 1
  max_size             = 3
  desired_capacity     = 1
  launch_configuration = aws_launch_configuration.lcg.name
  vpc_zone_identifier       = [aws_subnet.subnet-a.id, aws_subnet.subnet-b.id,aws_subnet.subnet-c.id]
}


resource "aws_lb" "alb" {
  name               = "aws-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.security-group.id]
  subnets            = [aws_subnet.subnet-a.id, aws_subnet.subnet-b.id,aws_subnet.subnet-c.id]
}


resource "aws_lb_listener" "alb-lstnr" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}


 resource "aws_lb_target_group" "tg" {
   name     = "aws-asg-tg"
   port     = 80
   protocol = "HTTP"
   vpc_id   = aws_vpc.vpc.id
 }

resource "aws_autoscaling_attachment" "albatch" {
  autoscaling_group_name = aws_autoscaling_group.asg.id
  alb_target_group_arn   = aws_lb_target_group.tg.arn
}