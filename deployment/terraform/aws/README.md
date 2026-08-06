# AWS Terraform — Migration Assistant Infrastructure

This root module provisions the AWS infrastructure used by the Kubernetes-based
OpenSearch Migration Assistant. It is an additive Terraform alternative to the
existing CDK-generated CloudFormation templates; those templates remain in the
repository and continue to be supported.

The default deployment creates:

- A dual-stack VPC spanning two availability zones, with public and private
  subnets and one NAT gateway per zone
- S3, ECR API, ECR Docker, CloudWatch Logs, and EFS VPC endpoints
- An EKS Auto Mode cluster with the `system` and `general-purpose` node pools
- A private ECR repository
- Cluster, node, snapshot, and Migration Assistant workload IAM roles
- EKS Pod Identity associations for the chart's AWS-facing service accounts
- Optionally, the Migration Assistant Helm chart using the EKS overlay

You can instead deploy into an existing VPC and select only the endpoints that
Terraform should add.

## Prerequisites

- Terraform or OpenTofu 1.6 or newer
- AWS credentials authorized to manage VPC, EKS, ECR, IAM, and VPC endpoint
  resources
- AWS CLI and `kubectl` for cluster access after provisioning
- Network access to public Helm and container registries if `deploy_helm = true`

EKS Auto Mode must be available in the selected AWS region and for the selected
Kubernetes version.

## Create a new VPC and EKS cluster

From this directory:

```bash
terraform init
terraform plan \
  -var="region=us-east-1" \
  -var="stage=dev"
terraform apply \
  -var="region=us-east-1" \
  -var="stage=dev"

# Configure kubectl using the command emitted by Terraform.
$(terraform output -raw kubeconfig_command)
kubectl get nodes
```

The new VPC uses `10.212.0.0/16` by default to reduce the chance of conflicts
with a default VPC. Override `vpc_cidr` if that range overlaps a source, target,
peered, or transit-connected network.

## Use an existing VPC

Supply at least two subnets in distinct availability zones. Private subnets with
NAT or equivalent egress are recommended.

```hcl
create_vpc          = false
existing_vpc_id     = "vpc-0123456789abcdef0"
existing_subnet_ids = [
  "subnet-0123456789abcdef0",
  "subnet-abcdef01234567890",
]

# Endpoints are opt-in for an existing VPC.
vpc_endpoints = [
  "s3",
  "ecr.api",
  "ecr.dkr",
  "logs",
  "sts",
  "eks-auth",
]
```

When `existing_route_table_ids` is empty, Terraform discovers the route table
associated with each supplied subnet for the S3 gateway endpoint. Set the route
table IDs explicitly if the subnets use an implicit main-route-table association
or if only selected route tables should receive the S3 route.

Valid `vpc_endpoints` values are `s3`, `ecr.api`, `ecr.dkr`, `logs`,
`monitoring`, `elasticfilesystem`, `sts`, and `eks-auth`. Isolated subnets need
additional private access to every registry and Helm repository used during
installation; these AWS service endpoints alone do not provide that access.

## Install the Helm chart with Terraform

Helm installation is off by default so infrastructure can be provisioned
independently and images can be mirrored before workloads start. To install the
local chart with published public ECR images:

```bash
terraform apply \
  -var="region=us-east-1" \
  -var="stage=dev" \
  -var="deploy_helm=true" \
  -var="migration_assistant_version=3.3.4"
```

Use an actual published Migration Assistant release tag. Terraform applies
`valuesEks.yaml`, passes the AWS account, region, stage, and snapshot role to the
chart, and waits up to 25 minutes by default.

The module creates a private ECR repository for parity with the CloudFormation
deployment and exposes it as `ecr_repository_url`. The optional Terraform Helm
path uses public images; image mirroring or source builds remain a separate step.

## Outputs

Important outputs include:

| Output | Purpose |
|---|---|
| `cluster_name` | EKS cluster name |
| `kubeconfig_command` | Ready-to-run AWS CLI command for kubectl access |
| `ecr_repository_url` | Private image repository |
| `snapshot_role_arn` | Role passed when registering OpenSearch S3 snapshot repositories |
| `migration_pod_role_arn` | Shared role used by EKS Pod Identity |
| `migration_environment` | Shell exports equivalent to the CloudFormation bootstrap export string |

To load the compatibility environment into the current shell:

```bash
eval "$(terraform output -raw migration_environment)"
```

## CloudFormation coexistence and migration

This module does not delete, update, import, or otherwise manage resources in an
existing CloudFormation stack. It uses the same familiar cluster and ECR naming
pattern, so do not deploy Terraform with the same `stage` and region as a live
CloudFormation deployment unless you first plan an explicit state migration.
Use a different stage for side-by-side evaluation.

The Terraform implementation intentionally replaces CloudFormation's stack-level
AppRegistry association with normal AWS resource tags because there is no
CloudFormation stack to associate. Runtime infrastructure remains equivalent:
EKS Auto Mode, networking, ECR, IAM, snapshot access, and Pod Identity.

## Validate

The tests use Terraform mock providers and do not require AWS credentials:

```bash
terraform init -backend=false
terraform fmt -check -recursive
terraform validate
terraform test
```

## Destroy

Review the plan carefully; this removes the EKS environment and any Helm release
managed by this state:

```bash
terraform destroy
```

Terraform does not touch the CloudFormation deployment or its resources.
