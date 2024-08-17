provider "aws" {
  profile = "susmitha.yarragunta"
  region  = "us-west-2"
}

# VPC
resource "aws_vpc" "main4" {
  cidr_block = "10.0.0.0/16"
}

# Subnets
resource "aws_subnet" "public4" {
  count                   = 2
  vpc_id                  = aws_vpc.main4.id
  cidr_block              = cidrsubnet(aws_vpc.main4.cidr_block, 8, count.index)
  availability_zone       = element(["us-west-2a", "us-west-2b"], count.index)
  map_public_ip_on_launch = true
}

# Internet Gateway
resource "aws_internet_gateway" "igw4" {
  vpc_id = aws_vpc.main4.id
}

# Route Table
resource "aws_route_table" "public4" {
  vpc_id = aws_vpc.main4.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw4.id
  }
}

resource "aws_route_table_association" "public4" {
  count          = 2
  subnet_id      = element(aws_subnet.public4.*.id, count.index)
  route_table_id = aws_route_table.public4.id
}

# Security Group
resource "aws_security_group" "ecs_sg4" {
  vpc_id = aws_vpc.main4.id

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

# ECS Task Execution Role
resource "aws_iam_role" "ecs_task_execution_role4" {
  name = "ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy4" {
  role       = aws_iam_role.ecs_task_execution_role4.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECR Repository
resource "aws_ecr_repository" "jenkins4" {
  name = "jenkins"
}

# ECS Cluster
resource "aws_ecs_cluster" "jenkins_cluster4" {
  name = "jenkins-cluster"
}

# ALB
resource "aws_lb" "jenkins_alb4" {
  name               = "jenkins-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ecs_sg4.id]
  subnets            = aws_subnet.public4.*.id
}

# ALB Target Group
resource "aws_lb_target_group" "jenkins_tg4" {
  name     = "jenkins-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.main4.id
}

# ALB Listener
resource "aws_lb_listener" "jenkins_listener4" {
  load_balancer_arn = aws_lb.jenkins_alb4.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jenkins_tg4.arn
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "jenkins_task4" {
  family                   = "jenkins-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role4.arn
  memory                   = "512"
  cpu                      = "256"

  container_definitions = jsonencode([
    {
      name      = "jenkins"
      image     = "${aws_ecr_repository.jenkins4.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
        }
      ]
    }
  ])
}

# ECS Service
resource "aws_ecs_service" "jenkins_service4" {
  name            = "jenkins-service"
  cluster         = aws_ecs_cluster.jenkins_cluster4.id
  task_definition = aws_ecs_task_definition.jenkins_task4.arn
  launch_type     = "FARGATE"
  desired_count   = 1
  network_configuration {
    subnets         = aws_subnet.public4.*.id
    security_groups = [aws_security_group.ecs_sg4.id]
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.jenkins_tg4.arn
    container_name   = "jenkins"
    container_port   = 8080
  }
  depends_on = [aws_lb_listener.jenkins_listener4]
}
