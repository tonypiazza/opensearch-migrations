# Azure Terraform: Migration Assistant Infrastructure

This root module provisions the Azure infrastructure used by the Kubernetes-based
OpenSearch Migration Assistant on Azure Kubernetes Service (AKS).

The default deployment creates:

- A resource group and a virtual network with one subnet for the AKS nodes
- An AKS cluster using Azure CNI overlay, with the OIDC issuer and Microsoft Entra
  Workload ID enabled and one autoscaling node pool
- A storage account and blob container for snapshots and workflow artifacts
- A user-assigned managed identity with Storage Blob Data Contributor on the storage
  account, federated to the chart's service accounts
- Optionally, Azure Monitor Logs resources for workload logs
- Optionally, private connectivity to the source and target clusters, Blob Storage, and
  Azure Monitor, and a restricted or private API server
- Optionally, the Migration Assistant Helm chart using the AKS overlay

## Prerequisites

- Terraform or OpenTofu 1.6 or newer
- Azure credentials (for example `az login`) authorized to create resource groups,
  AKS clusters, storage accounts, managed identities, and role assignments in the
  subscription. Role assignments need `Microsoft.Authorization/roleAssignments/write`,
  for example through Owner or User Access Administrator.
- With `enable_azure_monitor_logs = true`, permission to create Microsoft Entra
  application registrations
- Azure CLI and `kubectl` for cluster access after provisioning
- Network access to public Helm and container registries if `deploy_helm = true`

`kubernetes_version` defaults to `1.35`, the oldest version the chart supports;
override it if that version is not offered in your region.

## Create the cluster

From this directory:

```bash
terraform init
terraform apply \
  -var="subscription_id=<subscription-id>" \
  -var="location=eastus" \
  -var="stage=dev"

# Configure kubectl using the command emitted by Terraform.
$(terraform output -raw kubeconfig_command)
kubectl get nodes
```

`subscription_id` defaults to `ARM_SUBSCRIPTION_ID` or the Azure CLI's current
subscription. The virtual network uses `10.212.0.0/16` by default; override
`vnet_cidr` and `aks_subnet_cidr` if that range overlaps a source, target, or peered
network. Pods use Azure CNI overlay addresses, not the subnet.

The node pool defaults to `Standard_D4s_v5`. The published images are
multi-architecture, so arm64 sizes such as `Standard_D4ps_v5` also work.

## Install the Helm chart with Terraform

Helm installation is off by default so infrastructure can be provisioned
independently. To install the local chart with published public ECR images:

```bash
terraform apply \
  -var="location=eastus" \
  -var="stage=dev" \
  -var="deploy_helm=true" \
  -var="migration_assistant_version=<release>"
```

Use a published Migration Assistant release later than 3.4.2. In 3.4.2 and earlier, the
migration workflow does not give document backfill pods Workload ID, so the backfill
cannot read the snapshot from Blob Storage. Terraform applies
`valuesAks.yaml`, passes the workload identity client ID and the storage account and
container to the chart, and waits `helm_timeout_seconds` (1500, or 25 minutes) for
the release. Terraform owns the container it creates, so the chart's container job
leaves it in place on uninstall.

To install the chart yourself instead, pass the `workload_identity_client_id` and
`storage_account_name` outputs as `azure.workloadIdentityClientId` and
`azureStorageConfiguration.accountName`, as described in the
[Kubernetes deployment README](../../k8s/README.md#aks).

Snapshot repositories in the workflow configuration use the `snapshot_repo_uri`
output, for example `azure://<account>/migration-snapshots/<path>`.

## Use an existing storage account

```bash
terraform apply \
  -var="create_storage_account=false" \
  -var="existing_storage_account_name=<account>" \
  -var="existing_storage_account_resource_group_name=<resource-group>"
```

Terraform grants the workload identity Storage Blob Data Contributor on the account
but does not create a container in it; the chart creates `storage_container_name`
if it is missing.

## Ship workload logs to Azure Monitor

Set `enable_azure_monitor_logs = true` to create a Log Analytics workspace, the
custom table `MigrationAssistant_CL`, a data collection rule, and a Microsoft Entra
application with Monitoring Metrics Publisher on the rule. Terraform also creates the
`ma` namespace with the application's client secret in the
`azure-monitor-logs-credentials` Secret, and with `deploy_helm = true` installs the
chart with `valuesAksMonitor.yaml`, which replaces the shared logs volume.

Fluent Bit's `azure_logs_ingestion` output authenticates only with a client secret,
so this is the one Azure credential the deployment does not federate. The secret is
stored in the Terraform state; protect the state accordingly.

The data collection rule is created with `kind = "Direct"` and has its own logs
ingestion endpoint, so no data collection endpoint is created unless
`azure_monitor_private_link = true` sends logs over Private Link (see
[Private networking](#private-networking)).

`terraform destroy` only soft-deletes the workspace, which stays recoverable for 14 days.
Its name carries a random suffix so that a later apply creates a new workspace instead of
recovering the old one; a recovered workspace accepts uploads from the new data collection
rule but stores none of them.

## Private networking

`source_connectivity` and `target_connectivity` establish a private network path to the
source and target clusters so backfill and live migration run without a public data path.
Each leg is independent and defaults to `mode = "none"`, which creates nothing and leaves a
public-path deployment unchanged.

- `private_endpoint` adds a private endpoint to the provider's Private Link Service, by
  `private_link_service_alias` (the provider approves the connection) or
  `private_link_service_id`, with an optional `dns_name` resolved through a private DNS zone.
- `vnet_peering` creates our side of a peering to `remote_virtual_network_id`; the remote
  owner creates the other side.

```hcl
# Target reached over Private Link, with a private DNS name.
target_connectivity = {
  mode                       = "private_endpoint"
  private_link_service_alias = "search-pls.11111111-1111-1111-1111-111111111111.eastus.azure.privatelinkservice"
  dns_name                   = "search.example.com"   # optional; use the provider's canonical hostname
}

# Source reached by peering to a customer virtual network.
source_connectivity = {
  mode                      = "vnet_peering"
  remote_virtual_network_id = "/subscriptions/SUBSCRIPTION/resourceGroups/RG/providers/Microsoft.Network/virtualNetworks/their-vnet"
}
```

After apply, `source_private_endpoint` / `target_private_endpoint` give the address to place
in the workflow cluster configuration, and `..._private_endpoint_status` shows whether the
provider has approved the connection. The cluster endpoint and credentials themselves are
supplied as runtime migration config, not by Terraform.

The other private paths are set separately:

- `storage_connectivity = { mode = "private_endpoint" }` adds a Blob private endpoint for the
  storage account, and `disable_public_access = true` also closes its public endpoint.
- `azure_monitor_private_link = true` sends workload logs over an Azure Monitor Private Link
  Scope when `enable_azure_monitor_logs` is true.
- `api_server_authorized_ip_ranges` restricts the public API server, and
  `private_cluster_enabled = true` gives it only a private endpoint. With a private cluster,
  Terraform itself must run from a host that can reach the virtual network for
  `deploy_helm` and `enable_azure_monitor_logs`.

Private endpoints go in a subnet created from `private_endpoint_subnet_cidr` only when one is
configured. For approval, peering, DNS, the source cluster's access to a locked-down storage
account, and the other operator steps, see
[Private Networking for Azure Migrations](../../../docs/azurePrivateNetworking.md).

## Variables

| Name | Default | Description |
|---|---|---|
| `subscription_id` | `null` | Subscription for the deployment; null uses `ARM_SUBSCRIPTION_ID` or the Azure CLI |
| `location` | `eastus` | Azure region |
| `stage` | `dev` | Short identifier used in resource names |
| `resource_group_name` | `null` | Resource group to create; null uses `ma-<stage>-<location>` |
| `kubernetes_version` | `1.35` | AKS Kubernetes version |
| `vnet_cidr` | `10.212.0.0/16` | Virtual network address space |
| `aks_subnet_cidr` | `10.212.0.0/20` | AKS node subnet, inside `vnet_cidr` |
| `pod_cidr` | `null` | Overlay pod range; null uses AKS's `10.244.0.0/16` |
| `private_endpoint_subnet_cidr` | `10.212.16.0/27` | Private endpoint subnet, created only when needed |
| `source_connectivity` | `{ mode = "none" }` | Source leg: `none`, `private_endpoint`, or `vnet_peering` |
| `target_connectivity` | `{ mode = "none" }` | Target leg: `none`, `private_endpoint`, or `vnet_peering` |
| `storage_connectivity` | `{ mode = "none" }` | Blob private endpoint, optionally with public access off |
| `api_server_authorized_ip_ranges` | `[]` | CIDRs allowed to reach the public API server; empty allows any |
| `private_cluster_enabled` | `false` | Private-only API server; replaces the cluster when changed |
| `node_vm_size` | `Standard_D4s_v5` | Node pool VM size |
| `node_min_count` / `node_max_count` | `3` / `6` | Node pool autoscaling range |
| `create_storage_account` | `true` | Create the storage account; false uses an existing one |
| `existing_storage_account_name` | `null` | Existing account when `create_storage_account` is false |
| `existing_storage_account_resource_group_name` | `null` | Resource group of the existing account |
| `storage_container_name` | `migration-snapshots` | Blob container for snapshots and artifacts |
| `namespace` | `ma` | Kubernetes namespace and Helm release name |
| `workload_identity_service_accounts` | the chart's five | Service accounts federated to the workload identity |
| `enable_azure_monitor_logs` | `false` | Create Azure Monitor Logs resources and ship logs there |
| `azure_monitor_private_link` | `false` | Send logs over an Azure Monitor Private Link Scope |
| `log_analytics_retention_in_days` | `30` | Workspace retention |
| `deploy_helm` | `false` | Install the Migration Assistant Helm chart |
| `migration_assistant_version` | `null` | Public ECR image tag; required when `deploy_helm = true` |
| `helm_timeout_seconds` | `1500` | How long Terraform waits for the release |
| `tags` | `{}` | Additional tags on every Azure resource |

## Outputs

| Output | Purpose |
|---|---|
| `resource_group_name` | Resource group holding the deployment |
| `cluster_name` | AKS cluster name |
| `kubeconfig_command` | Ready-to-run Azure CLI command for kubectl access |
| `virtual_network_id` | Migration virtual network, for the remote side of a peering |
| `source_private_endpoint` / `target_private_endpoint` | Address for a `private_endpoint` leg, or null |
| `source_private_endpoint_status` / `target_private_endpoint_status` | Connection approval status, or null |
| `oidc_issuer_url` | AKS OIDC issuer used by the federated credentials |
| `workload_identity_client_id` | The chart's `azure.workloadIdentityClientId` |
| `storage_account_name` | The chart's `azureStorageConfiguration.accountName` |
| `storage_container_name` | Blob container for snapshots and artifacts |
| `snapshot_repo_uri` | `azure://<account>/<container>` prefix for snapshot repositories |
| `storage_private_endpoint_ip` | Blob private endpoint IP, or null |
| `logs_ingestion_endpoint` | Endpoint fluent-bit sends logs to, or null without Azure Monitor |
| `log_analytics_workspace_id` | Workspace receiving logs, or null without Azure Monitor |
| `helm_release_status` | Helm release status, or null when `deploy_helm` is false |

## Validate

The tests use Terraform mock providers and do not require Azure credentials:

```bash
terraform init -backend=false
terraform fmt -check -recursive
terraform validate
terraform test
```

## Destroy

Review the plan carefully; this removes the AKS cluster, the storage account Terraform
created with any snapshots in it, and any Helm release managed by this state:

```bash
terraform destroy
```

If the destroy fails with `ResourceGroupDeletionBlocked` and the node resource group's activity log
shows a VM Agent rolling upgrade in progress on the node scale set, Azure started that upgrade itself.
Cancel it and run the destroy again:

```bash
az vmss rolling-upgrade cancel \
  --resource-group <node-resource-group> \
  --name <node-scale-set>
```

The node resource group is `MC_<resource-group>_<cluster>_<location>`.
