provider "aws" {
  region  = "us-east-1"
}

# VPC
resource "aws_vpc" "main7" {
  cidr_block = "10.0.0.0/16"
}

# Subnets
resource "aws_subnet" "public7" {
  count                   = 2
  vpc_id                  = aws_vpc.main7.id
  cidr_block              = cidrsubnet(aws_vpc.main7.cidr_block, 8, count.index)
  availability_zone       = element(["us-east-1a", "us-east-1b"], count.index)
  map_public_ip_on_launch = true
}

# Internet Gateway
resource "aws_internet_gateway" "igw7" {
  vpc_id = aws_vpc.main7.id
}

# Route Table
resource "aws_route_table" "public7" {
  vpc_id = aws_vpc.main7.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw7.id
  }
}

resource "aws_route_table_association" "public7" {
  count          = 2
  subnet_id      = element(aws_subnet.public7.*.id, count.index)
  route_table_id = aws_route_table.public7.id
}

# Security Group
resource "aws_security_group" "ecs_sg7" {
  vpc_id = aws_vpc.main7.id

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
resource "aws_iam_role" "ecs_task_execution_role7" {
  name = "ecsTaskExecutionRole5"

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

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy7" {
  role       = aws_iam_role.ecs_task_execution_role7.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECR Repository
resource "aws_ecr_repository" "jenkins7" {
  name = "jenkins5"
}

# ECS Cluster
resource "aws_ecs_cluster" "jenkins_cluster7" {
  name = "jenkins-cluster5"
}

# ALB
resource "aws_lb" "jenkins_alb7" {
  name               = "jenkins-alb4"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ecs_sg7.id]
  subnets            = aws_subnet.public7.*.id
}

# ALB Target Group
resource "aws_lb_target_group" "jenkins_tg7" {
  name     = "jenkins-tg4"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.main7.id

target_type = "ip"
}

# ALB Listener
resource "aws_lb_listener" "jenkins_listener7" {
  load_balancer_arn = aws_lb.jenkins_alb7.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jenkins_tg7.arn
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "jenkins_task7" {
  family                   = "jenkins-task4"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role7.arn
  memory                   = "512"
  cpu                      = "256"

  container_definitions = jsonencode([
    {
      name      = "jenkins4"
      image     = "${aws_ecr_repository.jenkins7.repository_url}:latest"
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
resource "aws_ecs_service" "jenkins_service7" {
  name            = "jenkins-service4"
  cluster         = aws_ecs_cluster.jenkins_cluster7.id
  task_definition = aws_ecs_task_definition.jenkins_task7.arn
  launch_type     = "FARGATE"
  desired_count   = 1
  network_configuration {
    subnets         = aws_subnet.public7.*.id
    security_groups = [aws_security_group.ecs_sg7.id]
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.jenkins_tg7.arn
    container_name   = "jenkins4"
    container_port   = 8080
  }
  depends_on = [aws_lb_listener.jenkins_listener7]
}
