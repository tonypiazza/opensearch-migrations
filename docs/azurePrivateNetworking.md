# Private Networking for Azure Migrations

By default the Azure migration deployment reaches the source cluster, target cluster, and
Blob Storage over routable (typically public) endpoints. This guide shows how to make
each data path private so that no migration data traverses the public internet.

All connectivity is **optional** and configured per leg. With no configuration, behavior
is unchanged from the standard Azure deployment in
[`deployment/terraform/azure`](../deployment/terraform/azure/README.md).

> **Scope:** these mechanisms reach clusters from inside an Azure virtual network, through
> Private Link or virtual network peering. A source or target hosted in another cloud or
> on-premises needs ExpressRoute or a VPN gateway, which this module does not provision; leave
> that leg at `mode = "none"` and connect it out of band.
>
> **Backfill migrations** (snapshot + reindex-from-snapshot) are covered end to end.
> **Live capture-and-replay** adds a capture proxy in front of the source; its ingress is made
> private automatically on AKS. See [Live capture proxy ingress](#live-capture-proxy-ingress).

## The data legs

| Leg | How to make it private |
|-----|------------------------|
| Target write | `target_connectivity` = `private_endpoint` or `vnet_peering` |
| Source read | `source_connectivity` = `private_endpoint` or `vnet_peering` |
| Snapshot ↔ Blob Storage | `storage_connectivity = { mode = "private_endpoint" }` |
| Workload logs → Azure Monitor | `azure_monitor_private_link = true` (with `enable_azure_monitor_logs`) |
| Live capture proxy ingress | Automatic on AKS (internal load balancer); leave the proxy's `internetFacing` unset |
| Control plane (operator access) | `api_server_authorized_ip_ranges`, or `private_cluster_enabled = true` |

Private endpoints are placed in a dedicated subnet, `private_endpoint_subnet_cidr`
(default `10.212.16.0/27`), which Terraform creates only when one is configured. Each private
endpoint is billed hourly plus per GB processed, and peering per GB in each direction; see
[Private Link pricing](https://azure.microsoft.com/pricing/details/private-link/) and
[Virtual Network pricing](https://azure.microsoft.com/pricing/details/virtual-network/).

## Target/Source over Private Link (`private_endpoint`)

Use this when the cluster is published as an Azure Private Link Service (for example a
managed OpenSearch or Elasticsearch service that offers a private endpoint).

1. Obtain the provider's Private Link Service **alias** (or its resource ID, if it is in a
   subscription where you have permission on it) and the **hostname** its TLS certificate is
   issued for.
2. Configure the leg, supplying `dns_name` so the endpoint is reachable by hostname with
   valid TLS:

   ```hcl
   target_connectivity = {
     mode                       = "private_endpoint"
     private_link_service_alias = "search-pls.11111111-1111-1111-1111-111111111111.eastus.azure.privatelinkservice"
     request_message            = "Migration Assistant target"   # optional; shown to the provider
     dns_name                   = "search.example.com"
   }
   ```

   When `dns_name` is set, Terraform creates a **private DNS zone** linked to the migration
   virtual network that resolves that hostname to the private endpoint, so clients validate TLS
   against the real certificate. The zone defaults to the hostname's parent domain and answers
   for every name in it from inside the virtual network; set `dns_zone_domain` to the hostname
   itself (`search.example.com`) to override only that one name. Omit `dns_name` only if you
   intend to connect by IP with relaxed TLS verification.
3. Apply, then read the endpoint and its connection status:

   ```bash
   terraform output target_private_endpoint          # search.example.com, or the private IP without dns_name
   terraform output target_private_endpoint_status   # Pending until approved, then Approved
   ```

4. **Approval.** A connection by alias is a manual request: it stays **Pending** until the
   provider approves it, and carries no traffic until then. Providers that allow-list your
   subscription approve automatically. A connection by resource ID is approved when it is
   created. After the provider approves, refresh the status:

   ```bash
   terraform apply -refresh-only
   terraform output target_private_endpoint_status   # want: Approved
   ```

5. **Use the endpoint in your migration.** Endpoints are not injected automatically. Put the
   **hostname** into your workflow user config's `targetClusters` (or `sourceClusters`) entry
   as the cluster `endpoint`, e.g. `https://search.example.com:9200`, using the **port the
   provider serves on**. The migration workflow reads cluster endpoints from this config at
   submission time.

Private Link Service closes idle TCP connections after about 5 minutes. Clients that keep
connections open longer need TCP keepalives below that.

## Target/Source over virtual network peering (`vnet_peering`)

Use this when the cluster lives in another Azure virtual network you can peer with.

1. Ensure the remote network's address space does **not** overlap this deployment's
   `vnet_cidr` or its pod range. Pods use Azure CNI overlay addresses from `pod_cidr`, which
   defaults to AKS's `10.244.0.0/16`; set `pod_cidr` before creating the cluster if the remote
   network uses that range, since changing it later replaces the cluster.
2. Configure the leg:

   ```hcl
   source_connectivity = {
     mode                      = "vnet_peering"
     remote_virtual_network_id = "/subscriptions/SUBSCRIPTION/resourceGroups/RG/providers/Microsoft.Network/virtualNetworks/their-vnet"
   }
   ```

3. This creates **our** side of the peering only. The remote owner must create the peering
   from their network back to ours; until then the peering stays **Initiated** and carries no
   traffic:

   ```bash
   terraform output virtual_network_id   # give this to the remote owner

   # Run by the remote owner:
   az network vnet peering create --name to-migration --resource-group RG --vnet-name their-vnet \
     --remote-vnet <virtual_network_id> --allow-vnet-access

   az network vnet peering show --name <name> --resource-group <our resource group> \
     --vnet-name <our vnet> --query peeringState   # want: Connected
   ```

4. Pod traffic leaves through the node's IP, so the cluster's network security rules must allow
   `aks_subnet_cidr` (default `10.212.0.0/20`) on the cluster port.
5. Azure-provided DNS does not resolve names across a peering. Use the cluster's private IP, or
   link the private DNS zone that holds its hostname to the migration virtual network. Put that
   address into your workflow user config as usual; traffic now routes over the peering.

## Snapshot storage (Blob Storage)

Set `storage_connectivity = { mode = "private_endpoint" }` to add a Blob private endpoint for
the storage account and the `privatelink.blob.core.windows.net` private DNS zone. Pods keep
using the account's normal hostname (`<account>.blob.core.windows.net`), which resolves to the
private endpoint inside the virtual network. The zone falls back to public DNS for names it does
not hold, so other storage accounts stay reachable. This works for an account Terraform creates
and for an existing account (`create_storage_account = false`).

A private endpoint does not by itself close the account's public endpoint. To do that, also set
`disable_public_access = true`, which applies only to an account Terraform creates:

```hcl
storage_connectivity = {
  mode                  = "private_endpoint"
  disable_public_access = true
}
```

With public access off, only clients in the migration virtual network can use the account:

- **The source cluster writes its snapshot to this account.** A source outside the virtual
  network needs its own private path to the account: a private endpoint in its network, or a
  peering plus the `privatelink.blob.core.windows.net` zone linked to its network. Otherwise
  snapshot creation fails.
- Tools on an operator workstation, such as `az storage blob`, cannot reach the account.
- Terraform keeps working from outside the network, because it manages the account and
  container through Azure Resource Manager rather than the blob endpoint.

> **Source-cluster prerequisite: the `repository-azure` plugin (Elasticsearch < 8.0).**
> The backfill snapshots the **source** cluster to Blob Storage, which requires the source to
> support Azure snapshot repositories. Elasticsearch **8.0+** and OpenSearch bundle Azure
> support; **Elasticsearch 7.x does not**: install the `repository-azure` plugin on every
> source node before migrating.

## Workload logs (Azure Monitor)

With `enable_azure_monitor_logs = true`, set `azure_monitor_private_link = true` to send logs to
Azure Monitor over Private Link. Terraform adds a data collection endpoint with public access off,
points the data collection rule and fluent-bit at it, and creates an Azure Monitor Private Link
Scope holding the workspace and the endpoint, a private endpoint to the scope, and its private DNS
zones (`privatelink.monitor.azure.com`, `privatelink.oms.opinsights.azure.com`,
`privatelink.ods.opinsights.azure.com`, `privatelink.agentsvc.azure-automation.net`, and the
shared `privatelink.blob.core.windows.net`).

- The scope accepts **ingestion** only over Private Link and leaves **queries** open, so the
  workspace can still be queried from the Azure portal outside the virtual network.
- Private-only ingestion also stops the migration virtual network from sending to Azure Monitor
  resources outside the scope.
- These zones change how every Azure Monitor name resolves from the migration virtual network. A
  virtual network can connect to only one Private Link Scope, and Azure recommends a single scope
  for networks that share DNS, so don't link these zones to networks that use another scope.
- fluent-bit still obtains its token from Microsoft Entra ID over the public endpoint, so the
  cluster keeps outbound internet access for authentication.

## Live capture proxy ingress

Live capture-and-replay migrations place a **capture proxy** in front of the source cluster:
source clients connect to the proxy, which forwards traffic to the source while mirroring it to
Kafka for the replayer. The proxy is exposed by a Kubernetes `LoadBalancer` Service.

The proxy Service is annotated for an **internal** load balancer according to the deployment's
cloud provider (the `cloudProvider` Helm value). On AKS this emits
`service.beta.kubernetes.io/azure-load-balancer-internal: "true"`, so the proxy receives an
address in the migration virtual network and its ingress never traverses the public internet.
Deploying with `valuesAks.yaml` (`cloudProvider: azure`) is enough.

- Source clients must reach that address over the virtual network (peering, VPN, or the same
  network), the same as any other private leg here.
- Set the proxy's `internetFacing` option to `true` only if you deliberately want a public proxy
  endpoint; leaving it unset (the default) keeps the proxy private.
- The **replayer → target** leg reuses the target connectivity configured above, and Kafka is
  in-cluster, so no additional setup is needed for them.

## Control-plane privacy (operator access)

These settings affect only how **you** (operators and CI) reach the cluster with `kubectl` and
Helm; the in-cluster migration workloads are unaffected.

- `api_server_authorized_ip_ranges` limits the public API server to the CIDR ranges you list.
  Include the address of every host that runs Terraform, `kubectl`, or Helm.
- `private_cluster_enabled = true` gives the API server only a private endpoint in the migration
  virtual network, with an AKS-managed private DNS zone. Reach it from a peered network, a VPN, or
  Azure Bastion; this module does not provision one. For one-off commands without network access,
  `az aks command invoke` runs `kubectl` through the Azure API. Changing this setting replaces the
  cluster, and it cannot be combined with `api_server_authorized_ip_ranges`.

> **The `terraform apply` host is also affected.** This module's `kubernetes` and `helm`
> providers connect to the API server for `deploy_helm = true` and for the Secret that
> `enable_azure_monitor_logs = true` creates. With a private cluster, the machine running
> `terraform apply` must itself reach the private endpoint, not just your interactive `kubectl`.
> Otherwise those steps hang or fail. To install the chart separately instead, leave both off and
> follow the [Kubernetes deployment README](../deployment/k8s/README.md#aks).
