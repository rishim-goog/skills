# IAM Permissions

This document provides insights into the IAM permissions required for Cloud Deploy to operate based on the features enabled for the `DeliveryPipeline`.

## Execution Service Account

**MUST KNOW**: The execution service account used by Cloud Deploy. This is either the default Compute Engine service account or a user-provided service account that was defined in the `Target` (or in `deployment-config.json`).

The execution service account **must always** have the following roles:
* `roles/clouddeploy.jobRunner`
* `roles/iam.serviceAccountUser`

### Runtime Permissions

If deploying to Cloud Run then `roles/run.developer` is **required**.

If deploying to GKE then `roles/container.developer` is **required**.

### Supply Chain Security & Binary Authorization Permissions (`prod` Targets)

If the target enforces Binary Authorization (`--binary-authorization=default` or `run.googleapis.com/binary-authorization: default`) or verifies attestations/SBOMs:
* `roles/binaryauthorization.attestorsVerifier` (to verify attestor signatures against the policy)
* `roles/containeranalysis.notes.occurrences.viewer` (to inspect vulnerability scans, SPDX SBOMs, and attestation occurrences)
* `roles/artifactregistry.reader` (to pull images and inspect image digests)

### Agent Registry Permissions (AI Agents & MCP Servers)

If the workload registers or verifies AI Agents or MCP Servers in Google Cloud Agent Registry (`agentregistry.googleapis.com`):
* `roles/agentregistry.viewer` (to list and verify registered agents and MCP servers)
* `roles/agentregistry.admin` (if explicitly managing Agent Registry entries or services)

### Analysis Permissions (Google Cloud Observability)

The following roles are **required**:
* `roles/monitoring.alertViewer`
* `roles/serviceusage.serviceUsageConsumer`

## Automation Service Account

**MUST KNOW**: The service account defined in the `Automation` resources.

The `Automation` service account **requires** the `roles/clouddeploy.operator` role.

## Release Creator

The user or service account that creates a `Release` and `Rollout` **must** have:
* `roles/clouddeploy.releaser`
* `roles/iam.serviceAccountUser`
* `roles/storage.admin`

**TIP**: If the `Release` and `Rollout` is created by a Cloud Build trigger with a custom service account (`cloud_build_trigger.service_account`), assign these roles (plus `roles/logging.logWriter` with `options: { logging: CLOUD_LOGGING_ONLY }`) to the custom Cloud Build service account. See https://docs.cloud.google.com/build/docs/cloud-build-service-account for more information.
