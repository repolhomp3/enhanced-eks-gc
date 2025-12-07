# VPC Endpoints for Private Connectivity (No NAT Gateway Required)
# Enable with: enable_vpc_endpoints = true in terraform.tfvars

locals {
  vpc_id             = var.create_vpc ? module.vpc[0].vpc_id : var.existing_vpc_id
  private_subnet_ids = var.create_vpc ? module.vpc[0].private_subnets : var.existing_private_subnet_ids
  
  # Interface endpoints (require ENI in each AZ)
  interface_endpoints = var.enable_vpc_endpoints ? {
    ec2 = {
      service_name = "com.amazonaws.${var.region}.ec2"
      private_dns  = true
    }
    ecr_api = {
      service_name = "com.amazonaws.${var.region}.ecr.api"
      private_dns  = true
    }
    ecr_dkr = {
      service_name = "com.amazonaws.${var.region}.ecr.dkr"
      private_dns  = true
    }
    ecs = {
      service_name = "com.amazonaws.${var.region}.ecs"
      private_dns  = true
    }
    ecs_agent = {
      service_name = "com.amazonaws.${var.region}.ecs-agent"
      private_dns  = true
    }
    ecs_telemetry = {
      service_name = "com.amazonaws.${var.region}.ecs-telemetry"
      private_dns  = true
    }
    elasticloadbalancing = {
      service_name = "com.amazonaws.${var.region}.elasticloadbalancing"
      private_dns  = true
    }
    rds = {
      service_name = "com.amazonaws.${var.region}.rds"
      private_dns  = true
    }
    secretsmanager = {
      service_name = "com.amazonaws.${var.region}.secretsmanager"
      private_dns  = true
    }
    ssm = {
      service_name = "com.amazonaws.${var.region}.ssm"
      private_dns  = true
    }
    ssmmessages = {
      service_name = "com.amazonaws.${var.region}.ssmmessages"
      private_dns  = true
    }
    ec2messages = {
      service_name = "com.amazonaws.${var.region}.ec2messages"
      private_dns  = true
    }
    logs = {
      service_name = "com.amazonaws.${var.region}.logs"
      private_dns  = true
    }
    monitoring = {
      service_name = "com.amazonaws.${var.region}.monitoring"
      private_dns  = true
    }
    sts = {
      service_name = "com.amazonaws.${var.region}.sts"
      private_dns  = true
    }
    kms = {
      service_name = "com.amazonaws.${var.region}.kms"
      private_dns  = true
    }
    lambda = {
      service_name = "com.amazonaws.${var.region}.lambda"
      private_dns  = true
    }
    sqs = {
      service_name = "com.amazonaws.${var.region}.sqs"
      private_dns  = true
    }
    sns = {
      service_name = "com.amazonaws.${var.region}.sns"
      private_dns  = true
    }
    elasticfilesystem = {
      service_name = "com.amazonaws.${var.region}.elasticfilesystem"
      private_dns  = true
    }
    kinesis_streams = {
      service_name = "com.amazonaws.${var.region}.kinesis-streams"
      private_dns  = true
    }
    kinesis_firehose = {
      service_name = "com.amazonaws.${var.region}.kinesis-firehose"
      private_dns  = true
    }
    xray = {
      service_name = "com.amazonaws.${var.region}.xray"
      private_dns  = true
    }
    athena = {
      service_name = "com.amazonaws.${var.region}.athena"
      private_dns  = true
    }
    glue = {
      service_name = "com.amazonaws.${var.region}.glue"
      private_dns  = true
    }
    sagemaker_api = {
      service_name = "com.amazonaws.${var.region}.sagemaker.api"
      private_dns  = true
    }
    sagemaker_runtime = {
      service_name = "com.amazonaws.${var.region}.sagemaker.runtime"
      private_dns  = true
    }
    bedrock_runtime = {
      service_name = "com.amazonaws.${var.region}.bedrock-runtime"
      private_dns  = true
    }
    bedrock_agent = {
      service_name = "com.amazonaws.${var.region}.bedrock-agent"
      private_dns  = true
    }
    bedrock_agent_runtime = {
      service_name = "com.amazonaws.${var.region}.bedrock-agent-runtime"
      private_dns  = true
    }
    autoscaling = {
      service_name = "com.amazonaws.${var.region}.autoscaling"
      private_dns  = true
    }
    application_autoscaling = {
      service_name = "com.amazonaws.${var.region}.application-autoscaling"
      private_dns  = true
    }
    events = {
      service_name = "com.amazonaws.${var.region}.events"
      private_dns  = true
    }
    servicediscovery = {
      service_name = "com.amazonaws.${var.region}.servicediscovery"
      private_dns  = true
    }
    appmesh_envoy_management = {
      service_name = "com.amazonaws.${var.region}.appmesh-envoy-management"
      private_dns  = true
    }
  } : {}

  # Gateway endpoints (no ENI, free)
  gateway_endpoints = var.enable_vpc_endpoints ? {
    s3 = {
      service_name = "com.amazonaws.${var.region}.s3"
    }
    dynamodb = {
      service_name = "com.amazonaws.${var.region}.dynamodb"
    }
  } : {}
}

# Security group for VPC endpoints
resource "aws_security_group" "vpc_endpoints" {
  count       = var.enable_vpc_endpoints ? 1 : 0
  name        = "${var.cluster_name}-vpc-endpoints"
  description = "Security group for VPC endpoints"
  vpc_id      = local.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.create_vpc ? var.vpc_cidr : data.aws_vpc.existing[0].cidr_block]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-vpc-endpoints"
  }
}

# Interface VPC Endpoints
resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoints

  vpc_id              = local.vpc_id
  service_name        = each.value.service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = each.value.private_dns

  tags = {
    Name = "${var.cluster_name}-${each.key}"
  }
}

# Gateway VPC Endpoints (S3 and DynamoDB)
resource "aws_vpc_endpoint" "gateway" {
  for_each = local.gateway_endpoints

  vpc_id            = local.vpc_id
  service_name      = each.value.service_name
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.create_vpc ? module.vpc[0].private_route_table_ids : var.existing_private_route_table_ids

  tags = {
    Name = "${var.cluster_name}-${each.key}"
  }
}

# Data source for existing VPC CIDR (when using existing VPC)
data "aws_vpc" "existing" {
  count = var.create_vpc ? 0 : 1
  id    = var.existing_vpc_id
}
