# Amazon Bedrock Agent for AI-Driven EKS Operations

resource "aws_s3_bucket" "bedrock_agent" {
  count  = var.enable_bedrock_agent ? 1 : 0
  bucket = "${var.cluster_name}-bedrock-agent"
}

resource "aws_s3_bucket_versioning" "bedrock_agent" {
  count  = var.enable_bedrock_agent ? 1 : 0
  bucket = aws_s3_bucket.bedrock_agent[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bedrock_agent" {
  count  = var.enable_bedrock_agent ? 1 : 0
  bucket = aws_s3_bucket.bedrock_agent[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.bedrock_agent[0].arn
    }
  }
}

resource "aws_kms_key" "bedrock_agent" {
  count                   = var.enable_bedrock_agent ? 1 : 0
  description             = "KMS key for Bedrock agent ${var.cluster_name}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_kms_alias" "bedrock_agent" {
  count         = var.enable_bedrock_agent ? 1 : 0
  name          = "alias/${var.cluster_name}-bedrock-agent"
  target_key_id = aws_kms_key.bedrock_agent[0].key_id
}

resource "aws_s3_object" "kubernetes_api_schema" {
  count   = var.enable_bedrock_agent ? 1 : 0
  bucket  = aws_s3_bucket.bedrock_agent[0].id
  key     = "schemas/kubernetes-api.json"
  content = jsonencode({
    openapi = "3.0.0"
    info    = { title = "Kubernetes API", version = "1.0.0" }
    paths = {
      "/kubectl/get"      = { post = { summary = "Get Kubernetes resources", operationId = "kubectlGet" } }
      "/kubectl/logs"     = { post = { summary = "Get pod logs", operationId = "kubectlLogs" } }
      "/kubectl/describe" = { post = { summary = "Describe Kubernetes resource", operationId = "kubectlDescribe" } }
    }
  })
}

resource "aws_s3_object" "aws_api_schema" {
  count   = var.enable_bedrock_agent ? 1 : 0
  bucket  = aws_s3_bucket.bedrock_agent[0].id
  key     = "schemas/aws-api.json"
  content = jsonencode({
    openapi = "3.0.0"
    info    = { title = "AWS Operations API", version = "1.0.0" }
    paths = {
      "/cloudwatch/get-metric-data" = { post = { summary = "Get CloudWatch metrics", operationId = "getMetricData" } }
      "/guardduty/get-findings"     = { post = { summary = "Get GuardDuty findings", operationId = "getGuardDutyFindings" } }
      "/xray/get-service-graph"     = { post = { summary = "Get X-Ray service graph", operationId = "getXRayServiceGraph" } }
    }
  })
}

resource "aws_iam_role" "bedrock_agent" {
  count = var.enable_bedrock_agent ? 1 : 0
  name  = "${var.cluster_name}-bedrock-agent-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "bedrock.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
    }]
  })
}

resource "aws_iam_role_policy" "bedrock_agent" {
  count = var.enable_bedrock_agent ? 1 : 0
  name  = "bedrock-agent-policy"
  role  = aws_iam_role.bedrock_agent[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel"]
        Resource = "arn:${data.aws_partition.current.partition}:bedrock:${var.aws_region}::foundation-model/anthropic.claude-3-sonnet-20240229-v1:0"
      },
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = aws_lambda_function.mcp_server[0].arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.bedrock_agent[0].arn}/*"
      }
    ]
  })
}

resource "aws_lambda_function" "mcp_server" {
  count            = var.enable_bedrock_agent ? 1 : 0
  filename         = "lambda/mcp-server.zip"
  function_name    = "${var.cluster_name}-mcp-server"
  role             = aws_iam_role.mcp_server_lambda[0].arn
  handler          = "index.handler"
  runtime          = "python3.12"
  timeout          = 60
  memory_size      = 512
  source_code_hash = fileexists("lambda/mcp-server.zip") ? filebase64sha256("lambda/mcp-server.zip") : null

  environment {
    variables = {
      CLUSTER_NAME = module.eks.cluster_name
      AWS_REGION   = var.aws_region
    }
  }

  vpc_config {
    subnet_ids         = module.vpc.private_subnets
    security_group_ids = [aws_security_group.mcp_server_lambda[0].id]
  }
}

resource "aws_security_group" "mcp_server_lambda" {
  count       = var.enable_bedrock_agent ? 1 : 0
  name        = "${var.cluster_name}-mcp-server-lambda"
  description = "Security group for MCP server Lambda"
  vpc_id      = module.vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "mcp_server_lambda" {
  count = var.enable_bedrock_agent ? 1 : 0
  name  = "${var.cluster_name}-mcp-server-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "mcp_server_lambda_vpc" {
  count      = var.enable_bedrock_agent ? 1 : 0
  role       = aws_iam_role.mcp_server_lambda[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "mcp_server_lambda" {
  count = var.enable_bedrock_agent ? 1 : 0
  name  = "mcp-server-lambda-policy"
  role  = aws_iam_role.mcp_server_lambda[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["eks:DescribeCluster", "eks:ListClusters"], Resource = module.eks.cluster_arn },
      { Effect = "Allow", Action = ["cloudwatch:GetMetricData", "cloudwatch:GetMetricStatistics", "logs:GetLogEvents", "logs:FilterLogEvents"], Resource = "*" },
      { Effect = "Allow", Action = ["guardduty:GetFindings", "guardduty:ListFindings"], Resource = "*" },
      { Effect = "Allow", Action = ["xray:GetServiceGraph", "xray:GetTraceSummaries", "xray:GetTraceGraph"], Resource = "*" },
      { Effect = "Allow", Action = ["bedrock:InvokeModel"], Resource = "arn:${data.aws_partition.current.partition}:bedrock:${var.aws_region}::foundation-model/anthropic.claude-3-sonnet-20240229-v1:0" }
    ]
  })
}

resource "aws_cloudwatch_log_group" "mcp_server_lambda" {
  count             = var.enable_bedrock_agent ? 1 : 0
  name              = "/aws/lambda/${aws_lambda_function.mcp_server[0].function_name}"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.bedrock_agent[0].arn
}

resource "aws_lambda_permission" "mcp_server_bedrock" {
  count         = var.enable_bedrock_agent ? 1 : 0
  statement_id  = "AllowExecutionFromBedrock"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.mcp_server[0].function_name
  principal     = "bedrock.amazonaws.com"
  source_arn    = aws_iam_role.bedrock_agent[0].arn
}

resource "aws_cloudwatch_event_rule" "guardduty_critical" {
  count       = var.enable_bedrock_agent ? 1 : 0
  name        = "${var.cluster_name}-guardduty-critical-bedrock"
  description = "Trigger Bedrock agent on GuardDuty critical findings"
  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail      = { severity = [{ numeric = [">=", 7] }] }
  })
}

resource "aws_cloudwatch_event_target" "guardduty_critical_lambda" {
  count = var.enable_bedrock_agent ? 1 : 0
  rule  = aws_cloudwatch_event_rule.guardduty_critical[0].name
  arn   = aws_lambda_function.bedrock_agent_trigger[0].arn
}

resource "aws_lambda_function" "bedrock_agent_trigger" {
  count            = var.enable_bedrock_agent ? 1 : 0
  filename         = "lambda/bedrock-agent-trigger.zip"
  function_name    = "${var.cluster_name}-bedrock-agent-trigger"
  role             = aws_iam_role.bedrock_agent_trigger[0].arn
  handler          = "index.handler"
  runtime          = "python3.12"
  timeout          = 30
  source_code_hash = fileexists("lambda/bedrock-agent-trigger.zip") ? filebase64sha256("lambda/bedrock-agent-trigger.zip") : null

  environment {
    variables = {
      AGENT_ID       = ""
      AGENT_ALIAS_ID = "production"
    }
  }
}

resource "aws_iam_role" "bedrock_agent_trigger" {
  count = var.enable_bedrock_agent ? 1 : 0
  name  = "${var.cluster_name}-bedrock-agent-trigger-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "bedrock_agent_trigger_basic" {
  count      = var.enable_bedrock_agent ? 1 : 0
  role       = aws_iam_role.bedrock_agent_trigger[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "bedrock_agent_trigger" {
  count = var.enable_bedrock_agent ? 1 : 0
  name  = "bedrock-agent-trigger-policy"
  role  = aws_iam_role.bedrock_agent_trigger[0].id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["bedrock:InvokeAgent"], Resource = "*" }]
  })
}

resource "aws_lambda_permission" "bedrock_agent_trigger_eventbridge" {
  count         = var.enable_bedrock_agent ? 1 : 0
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.bedrock_agent_trigger[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.guardduty_critical[0].arn
}
