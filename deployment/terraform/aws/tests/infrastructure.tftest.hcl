# Plan-time tests for the additive AWS Terraform deployment.
# Mock providers keep the tests local: no AWS credentials or cloud resources are required.

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c"]
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:user/terraform-test"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_vpc" {
    defaults = {
      cidr_block = "10.20.0.0/16"
    }
  }

  # aws_iam_policy_document is provider-computed. Supply syntactically valid
  # JSON so aws_iam_role validation still runs under the mocked provider.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  # ipv6_cidr_block is provider-computed; without a valid default the mock emits
  # a random string and the cidrsubnet() calls in network.tf fail to plan.
  mock_resource "aws_vpc" {
    defaults = {
      ipv6_cidr_block = "2600:1f18::/56"
    }
  }

  # The IAM role ARN feeds aws_eks_cluster.compute_config.node_role_arn, which is
  # ARN-validated at plan time; the random mock default fails that check.
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock-migration-role"
    }
  }
}

mock_provider "helm" {}

run "new_vpc_matches_cloudformation_topology" {
  command = plan

  assert {
    condition     = length(aws_vpc.migration) == 1
    error_message = "The default deployment must create one VPC."
  }

  assert {
    condition     = length(aws_subnet.private) == 2 && length(aws_subnet.public) == 2
    error_message = "The default deployment must create two private and two public subnets."
  }

  assert {
    condition     = length(aws_nat_gateway.migration) == 2
    error_message = "The default deployment must create one NAT gateway per availability zone."
  }

  assert {
    condition     = length(aws_vpc_endpoint.s3) == 1 && length(aws_vpc_endpoint.interface) == 4
    error_message = "A new VPC must include the S3, ECR API, ECR Docker, CloudWatch Logs, and EFS endpoints."
  }
}

run "eks_auto_mode_and_pod_identity_are_enabled" {
  command = plan

  assert {
    condition     = aws_eks_cluster.migration.compute_config[0].enabled == true
    error_message = "EKS Auto Mode compute must be enabled."
  }

  assert {
    condition = toset(aws_eks_cluster.migration.compute_config[0].node_pools) == toset([
      "system",
      "general-purpose",
    ])
    error_message = "Both built-in EKS Auto Mode node pools must be enabled."
  }

  assert {
    condition     = length(aws_eks_pod_identity_association.migration) == length(var.pod_identity_service_accounts)
    error_message = "Every configured Migration Assistant service account must receive a Pod Identity association."
  }
}

run "existing_vpc_is_additive_and_endpoints_are_opt_in" {
  command = plan

  variables {
    create_vpc          = false
    existing_vpc_id     = "vpc-0123456789abcdef0"
    existing_subnet_ids = ["subnet-0123456789abcdef0", "subnet-abcdef01234567890"]
    vpc_endpoints       = ["s3", "sts", "eks-auth"]
  }

  assert {
    condition     = length(aws_vpc.migration) == 0 && length(aws_subnet.private) == 0 && length(aws_nat_gateway.migration) == 0
    error_message = "Existing-VPC mode must not create or replace VPC, subnet, or NAT resources."
  }

  assert {
    condition     = length(aws_vpc_endpoint.s3) == 1 && toset(keys(aws_vpc_endpoint.interface)) == toset(["sts", "eks-auth"])
    error_message = "Existing-VPC mode must create only explicitly selected endpoints."
  }
}

run "helm_requires_an_image_version" {
  command = plan

  variables {
    deploy_helm = true
  }

  expect_failures = [
    helm_release.migration_assistant[0],
  ]
}
