output "cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.migration.name
}

output "cluster_endpoint" {
  description = "EKS Kubernetes API endpoint."
  value       = aws_eks_cluster.migration.endpoint
}

output "cluster_security_group_id" {
  description = "EKS-managed cluster security group ID."
  value       = aws_eks_cluster.migration.vpc_config[0].cluster_security_group_id
}

output "vpc_id" {
  description = "VPC containing the EKS cluster."
  value       = local.vpc_id
}

output "subnet_ids" {
  description = "Subnets used by the EKS cluster."
  value       = local.cluster_subnets
}

output "ecr_repository_url" {
  description = "Private ECR repository available for mirrored or locally built Migration Assistant images."
  value       = aws_ecr_repository.migration.repository_url
}

output "migration_pod_role_arn" {
  description = "IAM role assumed by Migration Assistant workloads through EKS Pod Identity."
  value       = aws_iam_role.migration_pods.arn
}

output "snapshot_role_arn" {
  description = "IAM role that Amazon OpenSearch Service uses for S3 snapshots."
  value       = aws_iam_role.snapshot.arn
}

output "kubeconfig_command" {
  description = "Command that configures kubectl for the new cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${aws_eks_cluster.migration.name}"
}

output "migration_environment" {
  description = "Shell exports equivalent to the values consumed from the CloudFormation MigrationsExportString."
  value = join(" ", [
    "export MIGRATIONS_EKS_CLUSTER_NAME=${aws_eks_cluster.migration.name};",
    "export MIGRATIONS_ECR_REGISTRY=${aws_ecr_repository.migration.repository_url};",
    "export AWS_ACCOUNT=${data.aws_caller_identity.current.account_id};",
    "export AWS_CFN_REGION=${var.region};",
    "export VPC_ID=${local.vpc_id};",
    "export EKS_CLUSTER_SECURITY_GROUP=${aws_eks_cluster.migration.vpc_config[0].cluster_security_group_id};",
    "export SNAPSHOT_ROLE=${aws_iam_role.snapshot.arn};",
    "export STAGE=${var.stage};",
  ])
}

output "helm_release_status" {
  description = "Migration Assistant Helm release status, or null when deploy_helm is false."
  value       = var.deploy_helm ? helm_release.migration_assistant[0].status : null
}
