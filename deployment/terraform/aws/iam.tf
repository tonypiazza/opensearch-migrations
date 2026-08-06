resource "aws_ecr_repository" "migration" {
  name         = local.ecr_name
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.common_tags
}

data "aws_iam_policy_document" "pod_identity_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "migration_pods" {
  name               = "ma-${var.stage}-${var.region}-migrations"
  description        = "Migration Assistant role assumed by workloads through EKS Pod Identity"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "migration_pods_ecr" {
  role       = aws_iam_role.migration_pods.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"
}

data "aws_iam_policy_document" "migration_pods" {
  statement {
    sid    = "EcrImages"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeRepositories",
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ElasticFileSystem"
    effect    = "Allow"
    actions   = ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite"]
    resources = ["*"]
  }

  statement {
    sid       = "OpenSearch"
    effect    = "Allow"
    actions   = ["es:ESHttp*", "aoss:APIAccessAll"]
    resources = ["*"]
  }

  statement {
    sid    = "Secrets"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecrets",
    ]
    resources = ["*"]
  }

  # S3 access is intentionally account-wide (resources = ["*"]) rather than
  # scoped to migrations-*. This matches the existing CloudFormation deployment
  # and is required for two reasons:
  #   1. s3:ListAllMyBuckets is an account-level action that cannot be
  #      resource-scoped; it only functions with resources = ["*"].
  #   2. The migration console reads/writes user-configured buckets whose names
  #      are not under our control — notably the failed-document-stream bucket,
  #      which is supplied per-migration and may use any name.
  # The bucket the module itself relies on is created and deleted by the Helm
  # chart's defaultBucketConfiguration (app-managed, named
  # migrations-default-<account>-<stage>-<region>), not by Terraform, so
  # s3:CreateBucket/DeleteBucket must remain here. Do not narrow this to
  # migrations-* without confirming these paths still work.
  statement {
    sid    = "Snapshots"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
      "s3:ListAllMyBuckets",
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:ListBucketVersions",
      "s3:ListBucketMultipartUploads",
      "s3:AbortMultipartUpload",
      "s3:CreateBucket",
      "s3:DeleteBucket",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
      "logs:DescribeLogGroups",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "CloudWatchMetrics"
    effect    = "Allow"
    actions   = ["cloudwatch:ListMetrics", "cloudwatch:GetMetricData"]
    resources = ["*"]
  }

  statement {
    sid       = "XRayTraces"
    effect    = "Allow"
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    resources = ["*"]
  }

  statement {
    sid       = "PassSnapshotRoles"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/*"]
  }

  statement {
    sid    = "MigrationDashboards"
    effect = "Allow"
    actions = [
      "cloudwatch:PutDashboard",
      "cloudwatch:GetDashboard",
      "cloudwatch:DeleteDashboards",
    ]
    resources = ["arn:${data.aws_partition.current.partition}:cloudwatch::${data.aws_caller_identity.current.account_id}:dashboard/MA-*"]
  }

  statement {
    sid    = "PrivateCertificateAuthority"
    effect = "Allow"
    actions = [
      "acm-pca:IssueCertificate",
      "acm-pca:GetCertificate",
      "acm-pca:DescribeCertificateAuthority",
      "acm-pca:ListCertificateAuthorities",
      "acm-pca:CreateCertificateAuthority",
      "acm-pca:DeleteCertificateAuthority",
      "acm-pca:UpdateCertificateAuthority",
      "acm-pca:TagCertificateAuthority",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "migration_pods" {
  name   = "MigrationsPodPolicy"
  role   = aws_iam_role.migration_pods.id
  policy = data.aws_iam_policy_document.migration_pods.json
}

data "aws_iam_policy_document" "snapshot_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["es.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "snapshot" {
  name               = "ma-${var.stage}-${var.region}-snapshot"
  description        = "Allows Amazon OpenSearch Service to read and write Migration Assistant snapshots"
  assume_role_policy = data.aws_iam_policy_document.snapshot_assume_role.json

  tags = local.common_tags
}

data "aws_iam_policy_document" "snapshot" {
  statement {
    sid       = "ListMigrationBuckets"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::migrations-*"]
  }

  statement {
    sid       = "ManageMigrationSnapshotObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::migrations-*/*"]
  }
}

resource "aws_iam_role_policy" "snapshot" {
  name   = "MigrationSnapshotPolicy"
  role   = aws_iam_role.snapshot.id
  policy = data.aws_iam_policy_document.snapshot.json
}

resource "aws_eks_pod_identity_association" "migration" {
  for_each = var.pod_identity_service_accounts

  cluster_name    = aws_eks_cluster.migration.name
  namespace       = var.namespace
  service_account = each.value
  role_arn        = aws_iam_role.migration_pods.arn

  depends_on = [
    aws_iam_role_policy.migration_pods,
    aws_iam_role_policy_attachment.migration_pods_ecr,
  ]
}
