# AWS Secrets Manager and External Secrets Operator

# KMS key for Secrets Manager encryption
resource "aws_kms_key" "secrets_manager" {
  description             = "${var.cluster_name} Secrets Manager encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name = "${var.cluster_name}-secrets-manager"
  }
}

resource "aws_kms_alias" "secrets_manager" {
  name          = "alias/${var.cluster_name}-secrets-manager"
  target_key_id = aws_kms_key.secrets_manager.key_id
}

# IAM role for External Secrets Operator
resource "aws_iam_role" "external_secrets" {
  count = var.enable_external_secrets ? 1 : 0
  name  = "${var.cluster_name}-external-secrets"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
    }]
  })
}

# IAM policy for External Secrets Operator
resource "aws_iam_policy" "external_secrets" {
  count = var.enable_external_secrets ? 1 : 0
  name  = "${var.cluster_name}-external-secrets-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecrets"
        ]
        Resource = "arn:aws-us-gov:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.cluster_name}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.secrets_manager.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "external_secrets" {
  count      = var.enable_external_secrets ? 1 : 0
  role       = aws_iam_role.external_secrets[0].name
  policy_arn = aws_iam_policy.external_secrets[0].arn
}

# Pod Identity association for External Secrets Operator
resource "aws_eks_pod_identity_association" "external_secrets" {
  count           = var.enable_external_secrets ? 1 : 0
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = aws_iam_role.external_secrets[0].arn

  depends_on = [aws_eks_cluster.main]
}

# Install External Secrets Operator via Helm
resource "helm_release" "external_secrets" {
  count            = var.enable_external_secrets ? 1 : 0
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  version          = var.external_secrets_version

  set {
    name  = "installCRDs"
    value = "true"
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "external-secrets"
  }

  depends_on = [
    aws_eks_cluster.main,
    aws_eks_pod_identity_association.external_secrets
  ]
}

# Create SecretStore for AWS Secrets Manager
resource "kubernetes_manifest" "secret_store" {
  count = var.enable_external_secrets ? 1 : 0

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "aws-secrets-manager"
    }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = var.region
          auth = {
            jwt = {
              serviceAccountRef = {
                name      = "external-secrets"
                namespace = "external-secrets"
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.external_secrets]
}

# Example secret in Secrets Manager (for demonstration)
resource "aws_secretsmanager_secret" "example" {
  count                   = var.enable_external_secrets && var.create_example_secret ? 1 : 0
  name                    = "${var.cluster_name}/example/database-credentials"
  description             = "Example database credentials"
  kms_key_id              = aws_kms_key.secrets_manager.id
  recovery_window_in_days = 30

  tags = {
    Name = "${var.cluster_name}-example-secret"
  }
}

resource "aws_secretsmanager_secret_version" "example" {
  count     = var.enable_external_secrets && var.create_example_secret ? 1 : 0
  secret_id = aws_secretsmanager_secret.example[0].id
  secret_string = jsonencode({
    username = "admin"
    password = "changeme-use-random-password"
    host     = "db.example.com"
    port     = "5432"
  })
}
