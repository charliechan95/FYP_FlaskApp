terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  alias                       = "localstack"
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    apigateway     = "http://localhost:4566"
    lambda         = "http://localhost:4566"
    sts            = "http://localhost:4566"
    iam            = "http://localhost:4566"
    cloudwatch     = "http://localhost:4566"
    cloudwatchlogs = "http://localhost:4566"
    sns            = "http://localhost:4566"
    ec2            = "http://localhost:4566"
  }
}


# VPC
resource "aws_vpc" "main" {
  provider   = aws.localstack
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "localstack-vpc"
  }
}

# Subnet
resource "aws_subnet" "public" {
  provider          = aws.localstack
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a" # LocalStack only uses us-east-1a

  tags = {
    Name = "localstack-public-subnet"
  }
}

# Security Group
resource "aws_security_group" "ec2_sg" {
  provider = aws.localstack
  name        = "ec2-security-group"
  description = "Allow inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # In real life, restrict this!
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # In real life, restrict this!
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "localstack-ec2-sg"
  }
}

# EC2 Instance
resource "aws_instance" "example" {
  provider        = aws.localstack
  ami             = "ami-00000000000000000" # Dummy AMI ID (LocalStack doesn't validate)
  instance_type   = "t2.micro"            # Dummy instance type
  subnet_id       = aws_subnet.public.id
  security_groups = [aws_security_group.ec2_sg.name]

  tags = {
    Name = "localstack-ec2"
  }
}

# SNS Topic
resource "aws_sns_topic" "example" {
  provider = aws.localstack
  name     = "localstack-topic"

  tags = {
    Name = "localstack-sns-topic"
  }
}

resource "aws_lambda_function" "flask_lambda" {
  provider      = aws.localstack
  function_name = "flask-app"
  handler       = "lambda_function.handler"
  runtime       = "python3.9"
  timeout       = 30
  memory_size   = 128

  # You'll need to package your Flask app into a ZIP file
  filename      = "lambda_package.zip"
  source_code_hash = filebase64sha256("lambda_package.zip")

  role          = aws_iam_role.lambda_role.arn
}

resource "aws_iam_role" "lambda_role" {
  provider = aws.localstack
  name     = "lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Effect = "Allow",
        Sid = ""
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_policy" {
  provider    = aws.localstack
  name        = "lambda-policy"
  description = "IAM policy for Lambda execution"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:*:*:*",
        Effect   = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  provider   = aws.localstack
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_api_gateway_rest_api" "api" {
  provider    = aws.localstack
  name        = "flask-api"
  description = "API Gateway for Flask app"
}

resource "aws_api_gateway_resource" "proxy" {
  provider    = aws.localstack
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy_method" {
  provider      = aws.localstack
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE"
  api_key_required = false

  request_parameters = {
    "method.request.path.proxy" = true
  }
}

resource "aws_api_gateway_integration" "lambda_integration" {
  provider                  = aws.localstack
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.proxy.id
  http_method             = aws_api_gateway_method.proxy_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.flask_lambda.invoke_arn

  request_parameters = {
    "integration.request.path.proxy" = "method.request.path.proxy"
  }
}

resource "aws_api_gateway_deployment" "deployment" {
  provider                  = aws.localstack
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "dev"

  triggers = {
    redeployment = sha256(jsonencode([
      aws_api_gateway_integration.lambda_integration,
      aws_api_gateway_method.proxy_method,
      aws_api_gateway_resource.proxy
    ]))
  }

  depends_on = [
    aws_api_gateway_integration.lambda_integration
  ]
}


output "api_url" {
  value = "http://localhost:4566/restapis/${aws_api_gateway_rest_api.api.id}/dev/_user_request_/${aws_api_gateway_resource.proxy.path_part}"
}

output "instance_public_ip" {
  value = aws_instance.example.public_ip
}

output "sns_topic_arn" {
  value = aws_sns_topic.example.arn
}

output "vpc_id" {
  value = aws_vpc.main.id
}