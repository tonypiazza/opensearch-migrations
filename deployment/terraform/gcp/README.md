# GCP Terraform - Migration Assistant

## Prerequisites

- Google Cloud SDK (`gcloud`) installed and authenticated
- Terraform >= 1.0
- Appropriate GCP permissions (Compute Admin, Kubernetes Engine Admin, Service Account Admin, Storage Admin)

## Deploy

```bash
cd deployment/terraform/gcp
terraform init
terraform plan -var="project=my-project" -var="source_endpoint=http://source-es:9200" -var="target_endpoint=https://target-os:9200"
terraform apply -var="project=my-project" -var="source_endpoint=http://source-es:9200" -var="target_endpoint=https://target-os:9200"
```

## Configure kubectl

```bash
gcloud container clusters get-credentials migration-cluster-my-project --region us-central1 --project my-project
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
terraform destroy -var="project=my-project" -var="source_endpoint=http://source-es:9200" -var="target_endpoint=https://target-os:9200"
```
