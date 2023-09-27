# Create a VPC
resource "aws_vpc" "VPC1" {
  cidr_block = var.vpc_cidr
tags = {
  Name = "VPC_TF"
}
}

#subnets
  
resource "aws_subnet" "public_subnet1" {
  vpc_id     = aws_vpc.VPC1.id
  cidr_block = "10.0.0.0/24"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = true 

  tags = {
    Name = "TF_Public_Subnet1"
  }
}

resource "aws_subnet" "private_subnet1" {
  vpc_id     = aws_vpc.VPC1.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "TF_Private_Subnet1"
  }
}  

resource "aws_subnet" "private_subnet2" {
  vpc_id     = aws_vpc.VPC1.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "TF_Private_Subnet2"
  }
}  


resource "aws_internet_gateway" "IGW" {
  vpc_id = aws_vpc.VPC1.id
  tags = {
    Name = "TF_IGW"
  }  
}

resource "aws_route_table" "route" {
  vpc_id = aws_vpc.VPC1.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.IGW.id
  }

  tags = {
    Name = "TF_route"
  }
}

resource "aws_route_table_association" "r_t" {
  subnet_id      = aws_subnet.public_subnet1.id
  route_table_id = aws_route_table.route.id
}


resource "aws_instance" "instance1" {
  ami=var.ami
  instance_type=var.instance_type
  subnet_id=aws_subnet.private_subnet2.id
  availability_zone = "us-east-1a"
  vpc_security_group_ids = [aws_security_group.sg1.id]
  user_data              = base64encode(file("userdata2.sh"))
  tags = {
    Name = "TF_Instance1"
  }
}

resource "aws_instance" "instance2" {
  ami=var.ami
  instance_type=var.instance_type
  subnet_id=aws_subnet.private_subnet2.id
  availability_zone = "us-east-1b"
  vpc_security_group_ids = [aws_security_group.sg1.id]
  user_data              = base64encode(file("userdata.sh"))
  tags = {
    Name = "TF_Instance2"
  }
}

resource "aws_instance" "instance3" {
  ami=var.ami
  instance_type=var.instance_type
  subnet_id=aws_subnet.public_subnet1.id
  availability_zone = "us-east-1a"
  vpc_security_group_ids = [aws_security_group.sg1.id]
 
  tags = {
    Name = "TF_Pub_Instance1"
  }
}


resource "aws_s3_bucket" "s3_bucket" {
  bucket = "tf_s3_BK"
}


resource "aws_dynamodb_table" "terraform_lock" {
  name           = "terraform-lock"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

resource "aws_security_group" "sg1" {
  name        = "sg1"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.VPC1.id
  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description      = "TLS from VPC"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["192.168.0.0/16"]
  }
  
  ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["192.168.0.0/16"]
  }
  

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
}

  tags = {
    Name = "TF_SG1"
  }
}

resource "aws_network_interface" "eni" {
  subnet_id       = aws_subnet.private_subnet2.id
  private_ips     = ["10.0.64.50"]
  security_groups = [aws_security_group.sg1.id]

  attachment {
    instance     = aws_instance.instance2.id
    device_index = 1
  }
}

resource "aws_eip" "eip" {
  domain                    = "vpc"
  network_interface         = aws_network_interface.eni.id
  depends_on = [ aws_internet_gateway.IGW ]
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.eip.id
  subnet_id     = aws_subnet.public_subnet1.id
  tags = {
    Name = "gw NAT"
  }
# To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
  depends_on = [aws_internet_gateway.IGW]
}

resource "aws_eip_association" "eip_assoc" {
  instance_id   = aws_instance.instance2.id
  allocation_id = aws_eip.eip.id
}

resource "aws_lb" "myalb" {
  name               = "lb-tf"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.sg1.id]
  subnets            = ["public_subnet1"]

  enable_deletion_protection = true

  access_logs {
    bucket  = aws_s3_bucket.s3_bucket.id
    prefix  = "test-lb"
    enabled = true
  }

} 
resource "aws_lb_target_group" "tg" {
  name     = "myTG"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.VPC1.id

  health_check {
    path = "/"
    port = "traffic-port"
  }
}

resource "aws_lb_target_group_attachment" "attach1" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.instance1.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "attach2" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.instance2.id
  port             = 80
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.myalb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.tg.arn
    type             = "forward"
  }
}


output "loadbalancerdns" {
  value = aws_lb.myalb.dns_name
}
