# Azure Terraform - Migration Assistant

## Prerequisites

- Azure CLI (`az`) installed and authenticated
- Terraform >= 1.0
- Appropriate Azure permissions (Contributor on subscription)

## Deploy

```bash
cd deployment/terraform/azure
terraform init
terraform plan -var="subscription_id=your-sub-id" -var="resource_group_name=migration-rg" -var="source_endpoint=http://source-es:9200" -var="target_endpoint=https://target-os:9200"
terraform apply -var="subscription_id=your-sub-id" -var="resource_group_name=migration-rg" -var="source_endpoint=http://source-es:9200" -var="target_endpoint=https://target-os:9200"
```

## Configure kubectl

```bash
az aks get-credentials --resource-group migration-rg --name migration-cluster-migration-rg
```

## Deploy Helm Chart

```bash
helm install migration-assistant ../../k8s/charts/aggregates/migrationAssistantWithArgo \
  --namespace migration \
  --create-namespace \
  --set aws.region=us-east-1
```

## Teardown

```bash
terraform destroy -var="subscription_id=your-sub-id" -var="resource_group_name=migration-rg" -var="source_endpoint=http://source-es:9200" -var="target_endpoint=https://target-os:9200"
```
