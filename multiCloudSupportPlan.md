# Multi-Cloud Support Implementation Plan

Tracking document for the implementation of [RFC #2845: Multi-Cloud Support
for Migration Assistant][rfc] in `opensearch-project/opensearch-migrations`.

This PR is a working branch. Code changes will land as follow-up commits and
this document will track scope, decisions, and progress.

## Scope

The RFC proposes extending the Migration Assistant to support GCP, Azure, and
bare-metal Kubernetes alongside the existing AWS deployment. Changes are
strictly additive — the AWS CDK path and existing Helm overlays remain
untouched.

## Phases

### Phase 1 — Cloud-Agnostic Object Storage

- [ ] `GcsRepo implements SourceRepo` in `SnapshotReader`
- [ ] `AzureBlobRepo implements SourceRepo` in `SnapshotReader`
- [ ] `GcsSnapshotCreator extends SnapshotCreator` in `RFS`
- [ ] `AzureBlobSnapshotCreator extends SnapshotCreator` in `RFS`
- [ ] `GcsTupleSink implements TupleSink` in `TrafficCapture/tupleSink`
- [ ] `AzureBlobTupleSink implements TupleSink` in `TrafficCapture/tupleSink`
- [ ] `TrafficReplayer` dispatcher: select tuple sink by configured backend
- [ ] Python console: `GcsSnapshot` / `AzureBlobSnapshot` + factory dispatch
- [ ] Schema and Pydantic enum updates in `console_link/models/snapshot.py`

### Phase 2 — Cloud-Agnostic Kafka Authentication

The SCRAM-SHA-512 auth path is already wired through the proxy and replayer
(see [`kafkaAuthWiringPlan.md`](./kafkaAuthWiringPlan.md)). Remaining work:

- [ ] mTLS auth option in `KafkaConfig.applySaslAuthProperties`
- [ ] Helm chart values for non-MSK Kafka brokers
- [ ] Documentation for SASL/SCRAM and mTLS deployment

### Phase 3 — Infrastructure Provisioning and Lifecycle

- [ ] `deployment/terraform/gcp/` — GKE, VPC, Cloud Storage, Kafka
- [ ] `deployment/terraform/azure/` — AKS, VNet, Blob Storage, Kafka
- [ ] `deployment/terraform/modules/` — shared Helm install / K8s config
- [ ] Helm chart refactor: `templates/resources/objectStore/` (cloud-conditional)
- [ ] Helm chart refactor: `templates/resources/gcp/` and `templates/resources/azure/`
- [ ] `valuesGke.yaml` and `valuesAks.yaml` overlays
- [ ] GCP Persistent Disk and Azure Managed Disk StorageClass templates
- [ ] GKE Node Auto-Provisioning / AKS Cluster Autoscaler equivalents
- [ ] Argo Workflows artifact storage on GCS and Azure Blob
- [ ] OTEL exporter overlays for Google Cloud Monitoring and Azure Monitor

### Phase 4 — End-to-End Validation

- [ ] CI matrix covering GKE and AKS deployments
- [ ] Full lifecycle test (provision → migrate → deprovision)
- [ ] Aiven for OpenSearch as target cluster validation
- [ ] Provider-specific configuration and troubleshooting docs

## Open Questions

These mirror the open questions in the upstream RFC and will be resolved as
implementation progresses:

1. **Module organization.** Inline GCS/Azure code in `SnapshotReader`
   alongside `S3Repo`, or split into `SnapshotReaderGcs` / `SnapshotReaderAzure`
   Gradle modules to keep cloud SDKs out of the default build?
2. **Helm chart structure.** Single chart with provider-specific values
   overlays, or separate sub-charts per cloud?
3. **CI ownership.** Aiven has offered to host GCP/Azure test infrastructure;
   test definitions live in this repo. How should the existing Jenkins setup
   at <https://migrations.ci.opensearch.org/> integrate non-AWS providers?
4. **Release cadence.** Feature flag initially, or GA from first release?
5. **IaC tooling.** Terraform is the working assumption. OpenTofu, Pulumi,
   and Crossplane remain on the table.

## What This PR Does NOT Change

- The AWS CDK deployment path
- Existing AWS-specific Helm templates under `templates/resources/aws/`
- Any existing migration capability — this work is purely about portability

## References

- Upstream RFC: <https://github.com/opensearch-project/opensearch-migrations/issues/2845>
- Existing Kafka auth wiring: [`kafkaAuthWiringPlan.md`](./kafkaAuthWiringPlan.md)
- Existing K8s charts: [`deployment/k8s/`](./deployment/k8s/)

[rfc]: https://github.com/opensearch-project/opensearch-migrations/issues/2845
