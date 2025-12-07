# KMS Keys for STIG/FIPS 140-2 Compliance

# KMS key for EKS secrets encryption
resource "aws_kms_key" "eks_secrets" {
  description             = "${var.cluster_name} EKS secrets encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name = "${var.cluster_name}-eks-secrets"
  }
}

resource "aws_kms_alias" "eks_secrets" {
  name          = "alias/${var.cluster_name}-eks-secrets"
  target_key_id = aws_kms_key.eks_secrets.key_id
}

# KMS key for EBS volume encryption
resource "aws_kms_key" "ebs" {
  description             = "${var.cluster_name} EBS volume encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name = "${var.cluster_name}-ebs"
  }
}

resource "aws_kms_alias" "ebs" {
  name          = "alias/${var.cluster_name}-ebs"
  target_key_id = aws_kms_key.ebs.key_id
}

# Set EBS encryption by default for the region
resource "aws_ebs_encryption_by_default" "enabled" {
  enabled = true
}

resource "aws_ebs_default_kms_key" "default" {
  key_arn = aws_kms_key.ebs.arn
}
