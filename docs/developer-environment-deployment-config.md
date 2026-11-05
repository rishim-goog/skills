# Configure CI/CD and Deployment Defaults (`deployment-config.json`)

> **Target Documentation Page**: [Set up a local development environment (`https://docs.cloud.google.com/docs/get-started/developer-environment`)](https://docs.cloud.google.com/docs/get-started/developer-environment)
> **Placement**: Immediately following the **"Install the google-cloud-developer plugin"** section (with administrator setup bullets added to **"Before you begin"**).

---

## 1. Addition to "Before you begin" (Administrator Prerequisites)

Add the following items to the **Before you begin** section of [Set up a local development environment](https://docs.cloud.google.com/docs/get-started/developer-environment):

* **Publish an organization deployment configuration (`deployment-config.json`)**: (Optional, recommended for teams) Create and host a shared `deployment-config.json` file in a central Git repository (GitHub, GitLab, or Bitbucket) to define standard runtime targets (Cloud Run or GKE), Artifact Registry repositories, Developer Connect connections, and Binary Authorization policies across `dev` and `prod` environments.
* **Provision a dedicated Cloud Build service account**: Create a least-privilege, user-managed service account (for example, `cloudbuild-runner@YOUR_PROJECT_ID.iam.gserviceaccount.com`) rather than using the default Compute Engine service account for CI/CD triggers.

---

## 2. New Section: Configure CI/CD and Deployment Defaults for Skills (`deployment-config.json`)

After you install the `google-cloud-developer` plugin in **Antigravity**, **Claude Code CLI**, or **Codex CLI**, the Google Cloud CI/CD skills (`google-cicd-deploy`, `google-cicd-pipeline-design`, and `google-cicd-release-orchestration`) use a standardized **`deployment-config.json`** configuration file to automate builds, supply-chain security checks, and deployments to **Cloud Run** and **Google Kubernetes Engine (GKE)**.

Providing a `deployment-config.json` file eliminates repetitive prompts for project IDs, regions, Artifact Registry paths, GKE cluster names, and Cloud Build settings, while enforcing your organization's security guardrails across `dev` and `prod` environments.

### How Agents Resolve Deployment Configuration

When you ask your agent to build or deploy an application, AI agent, or Model Context Protocol (MCP) server, the CI/CD skills resolve configuration in the following order:

1. **Cached Workspace Configuration (`.gcp-deploy/deployment-config.json`)**:
   * If `.gcp-deploy/deployment-config.json` (or `./deployment-config.json`) already exists in your project workspace, the agent uses it immediately without prompting you or running unnecessary network fetches.
2. **Agent Workspace Context Files (`GEMINI.md`, `CLAUDE.md`, or `AGENTS.md`)**:
   * If no `deployment-config.json` file is present, the agent checks your agent-specific workspace instructions file (`GEMINI.md` for Antigravity/Gemini CLI, `CLAUDE.md` for Claude Code CLI, or `AGENTS.md` for Codex CLI) or your prompt for explicit parameters.
3. **Central Git Configuration Repository or Auto-Generation**:
   * For new projects without local configuration, you can instruct the agent to either **pull `deployment-config.json` from a central Git repository** (GitHub, GitLab, or Bitbucket) or **auto-generate `deployment-config.json`** by inspecting the services enabled in your Google Cloud project.

---

### Set Up `deployment-config.json`

Choose one of the following methods to configure `deployment-config.json` in your local development environment:

#### Option A: Pull `deployment-config.json` from a Central Git Repository (Recommended for Teams)

Platform administrators can maintain a single `deployment-config.json` in a shared Git repository on **GitHub**, **GitLab**, **Bitbucket**, or any Git server.

1. In your agent (**Antigravity**, **Claude Code CLI**, or **Codex CLI**), prompt the agent with your configuration repository URL:
   ```text
   Deploy my application to the dev environment using the deployment configuration in https://github.com/YOUR_ORG/YOUR_CONFIG_REPO
   ```
2. The agent automatically:
   * Fetches `deployment-config.json` using Git sparse-checkout (`git clone --depth 1 --filter=blob:none --sparse`).
   * If the configuration repository is private and local Git credentials are not configured, retrieves a short-lived read token via **Google Cloud Developer Connect** (`gcloud developer-connect connections git-repository-links fetch-read-token`) to authenticate across GitHub, GitLab, or Bitbucket.
   * Caches the file at `.gcp-deploy/deployment-config.json`, records the source URL in `.gcp-deploy/config-state.json`, and adds `.gcp-deploy/` to `.gitignore` and `.dockerignore`.

#### Option B: Auto-Generate `deployment-config.json` from Your Google Cloud Project

If your organization does not maintain a central configuration repository, your agent can generate a compliant `deployment-config.json` file by inspecting the APIs and resources enabled in your Google Cloud project:

1. Ensure your default project is set in the `gcloud` CLI:
   ```bash
   gcloud config set project YOUR_PROJECT_ID
   ```
2. Prompt your agent:
   ```text
   Generate a deployment configuration file based on the services enabled in my GCP environment.
   ```
   *(Or specify a subset of services, for example: `"Generate a deployment configuration file that utilizes Cloud Run, Artifact Registry, Developer Connect, and Cloud Build."`)*
3. The agent inspects your enabled APIs (`gcloud services list --enabled`), existing Artifact Registry repositories, Developer Connect connections, Cloud Run services, and GKE clusters, and writes the resulting configuration to `./deployment-config.json` and `.gcp-deploy/deployment-config.json`.

---

### `deployment-config.json` Schema and Example

The `deployment-config.json` file is organized into four top-level sections:

1. **Runtime Selection & Common Settings** (`active_runtime`, `default_environment`, `fail_on_push_error`, `common_gcp_settings`)
2. **Cloud Run Environment Settings** (`cloud_run.dev`, `cloud_run.prod`)
3. **Google Kubernetes Engine (GKE) Environment Settings** (`gke.dev`, `gke.prod`)
4. **Developer Connect & Cloud Build Settings** (`developer_connect_and_cloud_build`)

```json
{
  "active_runtime": "Cloud Run",
  "default_environment": "dev",
  "fail_on_push_error": true,
  "common_gcp_settings": {
    "project_id": "YOUR_PROJECT_ID",
    "region": "us-central1"
  },
  "cloud_run": {
    "dev": {
      "project_id": "YOUR_PROJECT_ID",
      "region": "us-central1",
      "artifact_registry": "us-central1-docker.pkg.dev/YOUR_PROJECT_ID/app-images-dev",
      "service_name": "<app-name>-dev",
      "public_access": true,
      "container_port": 8080
    },
    "prod": {
      "project_id": "YOUR_PROJECT_ID",
      "region": "us-central1",
      "artifact_registry": "us-central1-docker.pkg.dev/YOUR_PROJECT_ID/app-images-prod",
      "service_name": "<app-name>-prod",
      "public_access": false,
      "container_port": 8080,
      "require_confirmation": true,
      "binary_authorization": "default",
      "binary_authorization_policy": "prod-policy"
    }
  },
  "gke": {
    "dev": {
      "project_id": "YOUR_PROJECT_ID",
      "cluster_location": "us-central1",
      "cluster_name": "gke-cluster-dev",
      "namespace": "dev",
      "artifact_registry": "us-central1-docker.pkg.dev/YOUR_PROJECT_ID/app-images-dev",
      "manifest_path": "./kubernetes-manifests/"
    },
    "prod": {
      "project_id": "YOUR_PROJECT_ID",
      "cluster_location": "us-central1",
      "cluster_name": "gke-cluster-prod",
      "namespace": "prod",
      "artifact_registry": "us-central1-docker.pkg.dev/YOUR_PROJECT_ID/app-images-prod",
      "manifest_path": "./release/kubernetes-manifests.yaml",
      "require_confirmation": true
    }
  },
  "developer_connect_and_cloud_build": {
    "build_mode": "Developer Connect + Cloud Build",
    "developer_connect": {
      "location": "us-central1",
      "connection_id": "YOUR_DEVCONNECT_CONNECTION_ID"
    },
    "cloud_build_trigger": {
      "project_id": "YOUR_PROJECT_ID",
      "region": "us-central1",
      "service_account": "projects/YOUR_PROJECT_ID/serviceAccounts/cloudbuild-runner@YOUR_PROJECT_ID.iam.gserviceaccount.com",
      "default_branch": "^main$",
      "auto_run_trigger": true
    }
  }
}
```

---

### Configuration Field Reference

#### 1. Top-Level & Common Settings

| Field | Type | Required | Description |
| :--- | :--- | :--- | :--- |
| `active_runtime` | `string` | Yes | Default target runtime when not specified in the user prompt. Allowed values: `"Cloud Run"`, `"GKE"`, or `"prompt"` (asks the developer to choose). |
| `default_environment` | `string` | Yes | Default target environment when not specified in the user prompt (`"dev"` or `"prod"`). |
| `fail_on_push_error` | `boolean` | Yes | When `true` (recommended), the agent immediately aborts the deployment if pushing the container image to Artifact Registry fails, preventing fallback to external or public registries. |
| `common_gcp_settings.project_id` | `string` | Yes | Default Google Cloud project ID. |
| `common_gcp_settings.region` | `string` | Yes | Default Google Cloud region (for example, `"us-central1"`). |

#### 2. Cloud Run Settings (`cloud_run.dev` and `cloud_run.prod`)

| Field | Type | Required | Description |
| :--- | :--- | :--- | :--- |
| `project_id` | `string` | Yes | Target Google Cloud project ID for the Cloud Run service. |
| `region` | `string` | Yes | Cloud Run deployment region. |
| `artifact_registry` | `string` | Yes | Full Artifact Registry Docker repository URI (`<REGION>-docker.pkg.dev/<PROJECT_ID>/<REPO_NAME>`). |
| `service_name` | `string` | Yes | Naming template for the Cloud Run service. Supports `<app-name>` substitution derived from the Git repository or directory name (for example, `"<app-name>-dev"`). |
| `public_access` | `boolean` | Yes | When `true`, passes `--allow-unauthenticated`; when `false`, enforces IAM authentication (`--no-allow-unauthenticated`). |
| `container_port` | `integer` | Yes | Port on which the container listens (default: `8080`). |
| `require_confirmation` | `boolean` | Optional | When `true` (enforced on `prod`), requires explicit user confirmation before executing the deployment. |
| `binary_authorization` | `string` | Optional | Binary Authorization policy name to enforce on the Cloud Run service (for example, `"default"` on `prod` passes `--binary-authorization=default`). |
| `binary_authorization_policy` | `string` | Optional | Identifier for the organization or project Binary Authorization policy used to verify image attestations prior to `prod` deployment. |

#### 3. Google Kubernetes Engine Settings (`gke.dev` and `gke.prod`)

| Field | Type | Required | Description |
| :--- | :--- | :--- | :--- |
| `project_id` | `string` | Yes | Google Cloud project ID hosting the GKE cluster. |
| `cluster_location` | `string` | Yes | Region or zone of the GKE cluster (for example, `"us-central1"`). |
| `cluster_name` | `string` | Yes | Name of the target GKE cluster. |
| `namespace` | `string` | Yes | Target Kubernetes namespace (`"dev"`, `"prod"`, or `"default"`). Created automatically if it does not exist. |
| `artifact_registry` | `string` | Yes | Artifact Registry Docker repository URI used for container images deployed to the cluster. |
| `manifest_path` | `string` | Yes | Local path to the Kubernetes manifest directory or file (for example, `"./kubernetes-manifests/"`). |
| `require_confirmation` | `boolean` | Optional | When `true` (enforced on `prod`), requires explicit user confirmation before applying manifests. |

#### 4. Developer Connect & Cloud Build Settings (`developer_connect_and_cloud_build`)

| Field | Type | Required | Description |
| :--- | :--- | :--- | :--- |
| `build_mode` | `string` | Yes | Set to `"Developer Connect + Cloud Build"` to enforce remote builds via Cloud Build triggers linked to your Git provider (GitHub, GitLab, or Bitbucket) instead of local Docker builds. |
| `developer_connect.location` | `string` | Yes | Region of the Developer Connect connection. |
| `developer_connect.connection_id` | `string` | Yes | ID of the pre-configured Developer Connect connection for GitHub, GitLab, or Bitbucket. |
| `cloud_build_trigger.project_id` | `string` | Yes | Google Cloud project ID where the Cloud Build trigger runs. |
| `cloud_build_trigger.region` | `string` | Yes | Region for the Cloud Build trigger. |
| `cloud_build_trigger.service_account` | `string` | Yes | Full resource name of the dedicated, user-managed Cloud Build service account (`projects/<PROJECT_ID>/serviceAccounts/<SA_EMAIL>`). Must **not** be the default Compute Engine service account. |
| `cloud_build_trigger.default_branch` | `string` | Yes | Branch regex pattern for the Cloud Build trigger (for example, `"^main$"`). When running the trigger manually, the agent resolves the remote repository's default branch and strips `^` and `$`. |
| `cloud_build_trigger.auto_run_trigger` | `boolean` | Optional | When `true`, automatically executes `gcloud builds triggers run` after creating or updating the trigger. |

---

### Required Google Cloud APIs and IAM Permissions

To use `deployment-config.json` across Cloud Run, GKE, Developer Connect, Cloud Build, Binary Authorization, and Agent Registry, ensure the following APIs and IAM roles are configured in your project:

#### 1. Enable Required APIs

```bash
gcloud services enable \
  run.googleapis.com \
  container.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  developerconnect.googleapis.com \
  binaryauthorization.googleapis.com \
  containeranalysis.googleapis.com \
  agentregistry.googleapis.com \
  secretmanager.googleapis.com \
  --project=YOUR_PROJECT_ID
```

#### 2. Required IAM Roles

| Principal | Required IAM Roles | Purpose |
| :--- | :--- | :--- |
| **Developer Identity** (local `gcloud` ADC user) | `roles/artifactregistry.admin`<br>`roles/cloudbuild.builds.editor`<br>`roles/developerconnect.admin`<br>`roles/run.admin`<br>`roles/container.developer`<br>`roles/iam.serviceAccountUser` (on the Cloud Build & runtime SAs)<br>`roles/binaryauthorization.attestorsVerifier`<br>`roles/agentregistry.viewer` | Allows the agent to inspect enabled services, link repositories in Developer Connect, create/run Cloud Build triggers, export SPDX SBOMs, verify Binary Authorization attestations, and deploy to Cloud Run or GKE. |
| **Dedicated Cloud Build Service Account** (`cloudbuild-runner@...`) | `roles/logging.logWriter`<br>`roles/artifactregistry.writer`<br>`roles/developerconnect.tokenAccessor`<br>`roles/run.developer`<br>`roles/container.developer`<br>`roles/storage.admin`<br>`roles/serviceusage.serviceUsageConsumer` | Executes remote container builds with `logging: CLOUD_LOGGING_ONLY`, pushes images to Artifact Registry, and deploys build artifacts. |
| **Cloud Build Service Agent** (`service-PROJECT_NUMBER@gcp-sa-cloudbuild.iam.gserviceaccount.com`) | `roles/cloudbuild.serviceAgent`<br>`roles/developerconnect.tokenAccessor`<br>`roles/iam.serviceAccountUser` (on `cloudbuild-runner@...`) | Allows Cloud Build to access Developer Connect repository links across GitHub, GitLab, and Bitbucket and impersonate the dedicated build service account. |

---

### Built-In Security & Operational Guardrails

When `deployment-config.json` is active, the Google Cloud CI/CD skills automatically enforce the following enterprise guardrails across **Antigravity**, **Claude Code CLI**, and **Codex CLI**:

* **Remote CI/CD Execution (`Developer Connect + Cloud Build`)**: Links your GitHub, GitLab, or Bitbucket repository to Developer Connect and builds on Cloud Build using your dedicated service account with `options: { logging: CLOUD_LOGGING_ONLY }`. If `Dockerfile` or `cloudbuild.yaml` is not yet committed to your remote default branch, the agent automatically synthesizes an `--inline-config` payload so the remote build succeeds without requiring a force-push.
* **Pre-Build Secret Interception**: Scans your workspace for `.env` files, private keys (`*.pem`, `*.key`), service account JSON keys, and hardcoded secrets in `Dockerfile` `ENV`/`ARG` instructions before building. Excludes sensitive files via `.dockerignore` and `.gcloudignore` and recommends **Google Cloud Secret Manager** (`--set-secrets`).
* **SPDX SBOM Generation & Binary Authorization (`prod`)**: Exports an SPDX Software Bill of Materials (`gcloud artifacts sbom export`) for built images and enforces Binary Authorization (`--binary-authorization=default`) on `prod` Cloud Run deployments—verifying cryptographic attestations prior to rollout and diagnosing `IMAGE_UNTRUSTED` policy violations with exact remediation commands.
* **Automatic Agent Registry Registration**: Detects AI Agents (`google-adk`, `langchain`, `langgraph`, `crewai`, `autogen`) and MCP Servers (`mcp`, `fastmcp`, `@modelcontextprotocol/sdk`) and automatically applies Google Cloud Agent Registry discovery labels (`functional-type=agent` or `functional-type=mcp-server`, `agent-registry-auto-register=true` on Cloud Run; `registry.gke.io/functional-type` and SPIFFE `agent-identity` annotations on GKE).
