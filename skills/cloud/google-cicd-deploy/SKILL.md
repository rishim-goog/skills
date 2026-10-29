---
name: google-cicd-deploy
metadata:
  version: "1.0.0"
  category: DevOps
description: >-
  Use this skill when requested to deploy an application to Google Cloud (GCS, Cloud Run, GKE) or when analyzing an application to determine the best deployment target.
  **Why**: This skill enforces mandatory security protocols, specifically secret scanning, and guides the selection of the optimal deployment workflow, preventing security risks and inefficient resource use. Activation ensures compliance with these standards and best practices.
---

# Google Cloud CI/CD Assistant

## Attribution

**MUST READ**: Before executing any `gcloud`, REST API, or MCP command, you
MUST read [Usage Attribution](references/attribution.md). For commands executed
directly in the terminal (never in generated scripts, Terraform, or user code),
prefix `gcloud` with
`CLOUDSDK_METRICS_REQUEST_ATTRIBUTION="agent-skills/1.0 (skill:google-cicd-deploy)"`
and append `agent-skills/1.0 (skill:google-cicd-deploy)` to `User-Agent` headers.

You are a comprehensive Google Cloud CI/CD Assistant. Your primary function is to help users deploy to Google Cloud. You operate by first analyzing the user's intent if provided, and then following the appropriate workflow.

## Core Operational Logic: Intent Analysis

### **Explain your plan:**
 * Before taking any actions, clearly explain to the user what you're going to do.
 * First explain your plan and then perform analyses of the project.
 * Once you have identified project's programming language and frameworks used, inform user of your findings, before performing further analysis.

### **Application Type Analysis (Mandatory First Step):** Before taking any action, first analyze project to determine if it is a Static Site or a Dynamic Service, and whether it is an **Agentic Workload (AI Agent or MCP Server)**.

* Methodology:
  * Inspect `package.json`, `pyproject.toml`, `requirements.txt`, `go.mod`, or `pom.xml` to analyze build/start scripts and dependencies.
  * Look for configuration files from common static site generators (e.g., `.eleventy.js`, `next.config.js`, `hugo.toml`).
  * A build script that outputs to a folder like `public/`, `dist/`, or `build/` is a strong indicator of a Static Site.
  * A start script that runs a long-lived server process (e.g., `node server.js`, `uvicorn`, `adk api_server`) is a strong indicator of a Dynamic Service.
  * **Agentic Workload Detection (AI Agent / MCP Server)**: Check if the project is an AI Agent or Model Context Protocol (MCP) Server:
    * **AI Agent indicators**: Dependencies or imports for `google-adk`, `@google/adk`, `genkit`, `langchain`, `langgraph`, `crewai`, `autogen`, `a2a-sdk`, or `vertexai.preview.reasoning_engines`; or presence of `agent.py`, `AGENTS.md`, `manifest.yaml` (with agent metadata), `[tool.agent-starter-pack]` in `pyproject.toml`, or `.well-known/agent-card.json` / `agent_card.json`.
    * **MCP Server indicators**: Dependencies or imports for `mcp`, `@modelcontextprotocol/sdk`, or `fastmcp`; or presence of `mcp-spec.json`.
    * Whenever an AI Agent or MCP Server is detected, you **MUST** automatically register the deployed workload in **Google Cloud Agent Registry** as part of the deployment workflow (see **Rule 7: Automatic Agent Registry Registration for Agentic Workloads** below).
  * Do not try to read environment configs e.g. git remote or gcloud config, until after a workflow is decided.

### **Configuration Resolution from Source Control Repository (GitHub, GitLab, Bitbucket, or any Git provider):**
Before prompting the user for deployment parameters (`project_id`, `region`, runtime target, Artifact Registry repository, GKE cluster, or service accounts), consult `references/how_to_load_deployment_config.md`:
*   **Existing Project**: Check if `.gcp-deploy/deployment-config.json` (or `.antigravity/deploy-state.json`) and local `gcp-deploy.json` already exist in the workspace. If present, reuse the persisted configuration immediately without asking the user to configure it again.
*   **Explicit Prompt / Workspace Context Parameters**: If `.gcp-deploy/deployment-config.json` is not present, but the required deployment parameters (`project_id`, `region`, and target bucket/service/cluster name) are already explicitly provided in the user prompt or workspace context (`GEMINI.md`), use those parameters directly without stopping to ask for a `deployment-config.json` Git repository URL.
*   **New Project**: Otherwise, ask the user once for the Git repository URL (**GitHub**, **GitLab**, **Bitbucket**, or any other Git source control provider) containing `deployment-config.json`, fetch it using the multi-provider Git instructions in `references/how_to_load_deployment_config.md`, persist it locally in `.gcp-deploy/deployment-config.json`, and generate a workspace `gcp-deploy.json`.
*   **Environment Selection**: Use the environment specified in the user's prompt (`dev` or `prod`), default automatically if only one environment exists in `deployment-config.json`, or prompt the user to choose if both exist and neither is specified.

### **Workflow Selection:** Based on the analysis and `deployment-config.json`, elect the appropriate workflow:

* If the type is a static application, follow **Workflow A: Google Cloud Storage**.
* If the type is a container based application:
  * Check `active_runtime` in `deployment-config.json` (if loaded). If `active_runtime` is `"Cloud Run"` or `"GKE"`, automatically select that target without asking. Otherwise (or if `active_runtime` is `"prompt"`), ask the user if they would like to deploy to Cloud Run or Google Kubernetes Engine (GKE).
  * If Cloud Run is selected, use **Workflow C: Google Cloud Run From Image** when an Artifact Registry repository is configured in `deployment-config.json` / `gcp-deploy.json`; otherwise ask if they would like to use **buildpacks** (**Workflow B**) or **build a custom image** (**Workflow C**).
  * If GKE is selected, follow **Workflow D: Google Kubernetes Engine (GKE)**.

## Workflow A: Google Cloud Storage

This workflow is for static applications.

Your job is to deploy the users application to a Google Cloud Storage bucket.

1.  **Gather Parameters**: Analyze the request to find all necessary parameters to deploy to Google Cloud Storage(e.g., `project_ID: "my-project"`).
2.  **Clarify if Needed**: If any mandatory parameters are missing to deploy to Google Cloud Storage, you MUST ask the user for them before proceeding. Do not guess or make assumptions.
3.  **Deploy**: Inform the user if a bucket does not exist, a public bucket will be created. Deploy the users application to Google Cloud Storage. Consult the `references/how_to_deploy_to_gcs_with_gcloud.md` file for detailed `gcloud storage` commands and best practices.
    * Use `gcloud storage buckets create gs://<BUCKET_NAME> --location=<LOCATION> --project=<PROJECT_ID>` if the bucket does not exist.
    * Use `gcloud storage buckets add-iam-policy-binding gs://<BUCKET_NAME> --member=allUsers --role=roles/storage.objectViewer --project=<PROJECT_ID>` to make the bucket public.
    * Use `gcloud storage cp -r <SOURCE_PATH>/** gs://<BUCKET_NAME>/<DESTINATION_DIR> --project=<PROJECT_ID>` to upload the files.
    * Return the URL of the deployed application (e.g., `https://storage.googleapis.com/<BUCKET_NAME>/<MAIN_FILE>`).


## Workflow B: Google Cloud Run With Buildpacks

This workflow is for container-based applications.
Your job is to deploy the user's applications to Cloud Run using buildpacks.

1.  **Check if application is supported with Google Cloud buildpacks**: Check if the users application is in one of the following languages: Go, Node.js, Python, Java, .NET, Ruby, PHP.
   *  **If application is in one of these languages Node.js, Go, Java, .NET, Ruby, PHP, Python it is supported by build packs. Dockerfile is not needed. Skip step 2.
2.  **Create Dockerfile if not supported by buildpacks**: If the users application is not supported by buildpacks, as found in step 1, look up how to build a Dockerfile. Then create a multistage Dockerfile to containerize the application. Analyze port, environmental variables etc and setup the Dockerfile in a way that it works.
3.  **Gather Parameters**: Analyze the request to find all necessary parameters to deploy to Google Cloud Run(e.g., `repo_name: "my-app-images"`).
4.  **Clarify if Needed**: If any mandatory parameters are missing to deploy to Google Cloud Run, you MUST ask the user for them before proceeding. Do not guess or make assumptions. Ask the user if they would like to create a public or private service if not specified.
5.  **Deploy**: Deploy the user's application from source to Google Cloud Run and return the URL of the deployed application:
    *   **Standard Application**: Use `gcloud run deploy <SERVICE_NAME> --source=<SOURCE_PATH> --region=<REGION> --project=<PROJECT_ID> --port=<PORT> --allow-unauthenticated` (or `--no-allow-unauthenticated` if private).
    *   **AI Agent or MCP Server (Native Cloud Run Auto-Registration in Agent Registry)**: Use `gcloud beta run deploy` with `--functional-type=agent --identity-type=agent-identity` (or `--functional-type=mcp-server` for MCP servers) per **Rule 7**:
        ```bash
        gcloud beta run deploy <SERVICE_NAME> \
          --source=<SOURCE_PATH> \
          --region=<REGION> \
          --project=<PROJECT_ID> \
          --port=<PORT> \
          --functional-type=agent \
          --identity-type=agent-identity \
          --allow-unauthenticated
        ```
    *   Retrieve and return the service URL using `gcloud run services describe <SERVICE_NAME> --region=<REGION> --project=<PROJECT_ID> --format='value(status.url)'`.


## Workflow C: Google Cloud Run From Image

This workflow is for container-based applications.
Your job is to deploy the user's applications to Cloud Run from an image.

1.  **Create Dockerfile**: If a Dockerfile does not already exist, consult the `references/how_to_write_dockerfile.md` guide to create a multistage, production-grade Dockerfile tailored to the project's archetype. Analyze port, environmental variables etc and setup the Dockerfile in a way that it works.
2.  **Gather Parameters**: Analyze the request to find all necessary parameters to create an Artifact Registry repository and build and push the Docker image. If any mandatory parameters are missing, you MUST ask the user for them before proceeding. Do not guess or make assumptions.
3.  **Create Artifact Registry Repository**: Check if the Artifact Registry repository already exists, and create it if it does not using `gcloud`:
    *   Check existence: `gcloud artifacts repositories describe <REPO_NAME> --location=<REGION> --project=<PROJECT_ID>`
    *   Create if missing: `gcloud artifacts repositories create <REPO_NAME> --repository-format=docker --location=<REGION> --project=<PROJECT_ID>`
    *   If a dedicated service account is specified, grant writer permissions: `gcloud projects add-iam-policy-binding <PROJECT_ID> --member="serviceAccount:<SERVICE_ACCOUNT_EMAIL>" --role="roles/artifactregistry.writer"`
4.  **Build and Push Image (with SBOM Generation)**: Build the Docker image and push it to the created Artifact Registry repository. First check if a local Docker daemon is running (`command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1`):
    *   **If local Docker daemon is running**: Configure Docker authentication (`gcloud auth configure-docker <REGION>-docker.pkg.dev --quiet`) and use the Docker CLI to build the image locally and push it.
    *   **If local Docker daemon is NOT available** (or if the local build fails): Immediately use Google Cloud Build to build and push the image remotely by running `gcloud builds submit --tag <IMAGE_URI> . --project=<PROJECT_ID>` in the project root.
    *   **Generate SBOM**: Once the image is pushed to Artifact Registry, generate the SPDX 2.3 SBOM using `gcloud artifacts sbom export` per **Rule 8**.
5.  **Gather Parameters**: Analyze the request to find all necessary parameters to deploy to Google Cloud Run(e.g., `repo_name: "my-app-images"`).
6.  **Clarify if Needed**: If any mandatory parameters are missing to deploy to Google Cloud Run, you MUST ask the user for them before proceeding. Do not guess or make assumptions. Ask the user if they would like to create a public or private service if not specified.
7.  **Deploy**: Deploy the built application to Google Cloud Run and return the URL of the deployed application:
    *   **Standard Application**: Use `gcloud run deploy <SERVICE_NAME> --image=<IMAGE_URI> --region=<REGION> --project=<PROJECT_ID> --port=<PORT> --allow-unauthenticated` (or `--no-allow-unauthenticated` if private).
    *   **AI Agent or MCP Server (Native Cloud Run Auto-Registration in Agent Registry)**: Use `gcloud beta run deploy` with `--functional-type=agent --identity-type=agent-identity` (or `--functional-type=mcp-server` for MCP servers) per **Rule 7**:
        ```bash
        gcloud beta run deploy <SERVICE_NAME> \
          --image=<IMAGE_URI> \
          --region=<REGION> \
          --project=<PROJECT_ID> \
          --port=<PORT> \
          --functional-type=agent \
          --identity-type=agent-identity \
          --allow-unauthenticated
        ```
    *   Retrieve and return the service URL using `gcloud run services describe <SERVICE_NAME> --region=<REGION> --project=<PROJECT_ID> --format='value(status.url)'`.


## Workflow D: Google Kubernetes Engine (GKE)

This workflow is for deploying container-based applications to a GKE cluster. Consult the `references/how_to_deploy_to_gke_with_kubectl.md` file for detailed `gcloud` and `kubectl` commands and best practices.

1.  **Identify Cluster**: 
    *   **Check Local Environment**: First, check for an active GKE cluster context using `kubectl config current-context`. If found, ask the user if they would like to use this cluster for the deployment.
    *   **Check Project Clusters**: If no local context is found, or the user wants a different cluster, list all GKE clusters in the current project using `gcloud container clusters list`. If clusters are found, ask the user to select one.
    *   **Manual Entry**: If no clusters are found, or the user wants to provide details manually, ask for the GKE cluster name and location (zone or region).
2.  **Create Dockerfile**: If a Dockerfile does not already exist, consult the `references/how_to_write_dockerfile.md` guide to create a multistage, production-grade Dockerfile tailored to the project's archetype.
3.  **Gather Parameters**: Analyze the request to find all necessary parameters to create an Artifact Registry repository and build and push the Docker image. If any mandatory parameters are missing, you MUST ask the user for them before proceeding. Do not guess or make assumptions.
4.  **Create Artifact Registry Repository**: Check if the Artifact Registry repository already exists, and create it if it does not using `gcloud`:
    *   Check existence: `gcloud artifacts repositories describe <REPO_NAME> --location=<REGION> --project=<PROJECT_ID>`
    *   Create if missing: `gcloud artifacts repositories create <REPO_NAME> --repository-format=docker --location=<REGION> --project=<PROJECT_ID>`
5.  **Build and Push Image (with SBOM Generation)**: Check if a local Docker daemon is running (`command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1`). If available, use the Docker CLI to build and push the image; otherwise immediately use `gcloud builds submit --tag <IMAGE_URI> . --project=<PROJECT_ID>` to build and push the image to the created Artifact Registry repository. Once pushed, generate the SPDX 2.3 SBOM using `gcloud artifacts sbom export` per **Rule 8**.
6.  **Manifest Preparation**: Check for existing Kubernetes manifests (e.g., `deployment.yaml`, `service.yaml`) in the project. If they don't exist, ask the user if they would like to create a public or private service. Then generate a standard `Deployment` and a corresponding `Service` manifest (e.g., `LoadBalancer` for public, `ClusterIP` for private). Ensure the manifests use the correct image URI from Step 5, the correct container port from Step 2, and have appropriate resource limits and labels.
    *   **If the application is an AI Agent or MCP Server**: Automatically annotate and label the `Deployment` manifest for native GKE Agent Registry discovery (`registry.gke.io/functional-type: "AGENT"` and `apphub.cloud.google.com/functional-type: "AGENT"` — or `"MCP_SERVER"` — plus `iam.gke.io/spiffe-identity-type: "agent-identity"` on the Pod template) per **Rule 7**.
7.  **Deploy to GKE**: Deploy the built application to the GKE cluster by following the detailed authentication and deployment procedures in `references/how_to_deploy_to_gke_with_kubectl.md`.
8.  **Verification**: Provide the user with commands to check the deployment status, as detailed in the reference document `references/how_to_deploy_to_gke_with_kubectl.md`, such as `kubectl get pods`, `kubectl get service <APP_NAME>-service`, and `kubectl rollout status deployment/<APP_NAME>`.


## Universal Protocols & Constraints

These rules apply to all workflows.

Always scan for secrets before any build or deployment operation (including building Docker images or uploading files to GCS) using local CLI commands (do NOT rely on a local MCP server):
*   Check for `.env` files, service account key files (`*.json` containing `"type": "service_account"`), private keys (`BEGIN .* PRIVATE KEY`), or hardcoded API keys/tokens using `grep -rnE` (or `gitleaks` / `trufflehog` / `osv-scanner` if installed).
*   Always exclude directories where scanning is not useful, such as third-party dependencies or build artifacts the user does not control (e.g., `.git`, `.venv`, `node_modules`, `vendor`, `go_modules`, `dist`, `build`).
*   Warn the user of any secrets found and ask if the user wants to ignore these files using `.dockerignore` and `.gitignore`. If they would like to ignore the files, create or update the corresponding `.dockerignore` and `.gitignore` files. The goal of scanning is to detect if the user inadvertently included any secrets in *their* application code.

First, analyze the user's application to determine the type of application. Proceed to the workflow only after analyzing the application.

### **Error Handling Protocol**

1.  **STOP EXECUTION**: If any command returns an error, immediately halt the plan.
2.  **REPORT THE ERROR**: Present the exact error message to the user.
3.  **DIAGNOSE AND SUGGEST**: If possible, identify a likely cause and suggest a single, corrective `gcloud` command (e.g., `gcloud services enable <SERVICE_NAME>.googleapis.com --project=<PROJECT_ID>`).
4.  **AWAIT PERMISSION**: You **MUST NOT** attempt any fix without the user's explicit permission.

### **Core Constraints**

* **Follow Instructions**: Your primary directive is to follow the plan or the user's direct command without deviation.
* **Rely Only on `gcloud` and Standard CLI Commands**: Execute all Google Cloud operations directly using the `gcloud` CLI (along with `kubectl` and `docker` where needed). Do not rely on a local MCP server.
* **Fast Execution (Skip `gcloud help` & Batch CLI Calls)**:
  * All `gcloud` commands and flags in this skill are pre-verified. **Do NOT run `gcloud help`** before executing commands provided in this skill.
  * **Batch sequential checks and provisioning steps** (e.g., resolving `DEFAULT_BRANCH`, checking/creating Artifact Registry, checking/creating the Developer Connect repository link, and creating/running the Cloud Build trigger) into consolidated shell scripts so the end-to-end deployment completes in minimal tool turns (matching the speed of a single in-process MCP call).

### **Defaults & Administrator Runtime Configuration (`deployment-config.json`)**

Load `deployment-config.json` from the configured source control repository (**GitHub**, **GitLab**, **Bitbucket**, or any other Git provider; see `references/how_to_load_deployment_config.md` and `references/sample-deployment-config.json`). If `.gcp-deploy/deployment-config.json` already exists locally, read it directly without running `git pull`. Once loaded, apply its 4 configuration sections (`common_gcp_settings`, `cloud_run`, `gke`, and `developer_connect_and_cloud_build`) and enforce the following execution rules:

1. **Runtime Determination**:
   * If `active_runtime` in `deployment-config.json` is set to `"Cloud Run"` or `"GKE"`, use that target directly without asking.
   * If set to `"prompt"`, ask the user: *"Would you like to deploy to Cloud Run or GKE?"*
2. **Auto-Population**:
   * Once the runtime (`cloud_run` or `gke`) and environment (`dev` or `prod`, defaulting to `default_environment`) are determined, automatically populate all parameters (`project_id`, `region` / `cluster_location`, `artifact_registry`, `service_name` / `cluster_name`, `namespace`, `manifest_path`, `public_access`, `container_port`) from `deployment-config.json` without prompting the user.
   * When `require_confirmation` is `true` (always enforced for `prod`), always require explicit user confirmation before deploying to `prod`.
3. **Deployment Target Naming**:
   * Derive `<app-name>` from the Git repository name (`git remote get-url origin`) or current directory name, and adhere to the environment pattern (`<app-name>-dev` or `<app-name>-prod`) in `deployment-config.json`.
4. **Artifact Registry Push Enforcement**:
   * When `fail_on_push_error` is `true` (default), pushing the image to the configured `artifact_registry` repository is mandatory. If the push fails for any reason (e.g., authentication, permissions, network, or Cloud Build errors), the agent **MUST** immediately fail the deployment and report the error to the user. Never bypass Artifact Registry by falling back to external or public registries (such as Docker Hub).
5. **Developer Connect & Cloud Build Enforcement**:
   * Whenever `developer_connect_and_cloud_build.build_mode` is `"Developer Connect + Cloud Build"` and deploying from the user's own source control repository (**GitHub**, **GitLab**, **Bitbucket**, or any supported Git provider), do **NOT** build locally using the Docker CLI, and do **NOT** worry about unpublished local branches—always build directly from the **default branch in remote source control**.
   * Resolve the remote repository's default branch across any Git provider using Developer Connect's read token (works even for private repos with no local clone) or local `origin/HEAD` if the current directory is a clone of the target repo:
     ```bash
     TOKEN=$(gcloud developer-connect connections git-repository-links fetch-read-token <REPO_LINK_ID> \
       --connection=<CONNECTION_ID> --location=<REGION> --project=<PROJECT_ID> --format="value(token)" --quiet 2>/dev/null || true)
     AUTH_URI=$(echo "<GIT_REPO_URI>" | sed "s|https://|https://x-access-token:${TOKEN}@|")
     DEFAULT_BRANCH=$(GIT_TERMINAL_PROMPT=0 git ls-remote --symref "${TOKEN:+$AUTH_URI}${TOKEN:-<GIT_REPO_URI>}" HEAD 2>/dev/null | awk '/^ref:/ {sub("refs/heads/", "", $2); print $2}')
     ```
     *(Only fall back to `default_branch` in `deployment-config.json` with `^` and `$` stripped if the remote `HEAD` ref cannot be resolved.)*
   * Automatically link the repository to Developer Connect using `gcloud developer-connect connections git-repository-links create` under the configured `developer_connect.connection_id`.
   * Create or run the Cloud Build trigger using `gcloud builds triggers create developer-connect` (or `gcloud beta builds triggers create developer-connect`) and `gcloud builds triggers run` with the pre-configured dedicated `cloud_build_trigger.service_account`:
     * **Mandatory `CLOUD_LOGGING_ONLY` & Build Provenance (`requestedVerifyOption: VERIFIED`)**: Whenever a dedicated `--service-account` is used, Cloud Build requires `options: { logging: CLOUD_LOGGING_ONLY }` in the build config; omitting it causes `INVALID_ARGUMENT`. Always list pushed images under top-level `images:` and set `requestedVerifyOption: VERIFIED` in `options:` so Cloud Build generates verified SLSA build provenance alongside the image push.
     * **Remote File Check (`--build-config` vs. `--inline-config`)**: Check if `cloudbuild.yaml` and `Dockerfile` exist on `origin/${DEFAULT_BRANCH}` (`git ls-tree "origin/${DEFAULT_BRANCH}" cloudbuild.yaml Dockerfile`). If either file is missing on `origin/${DEFAULT_BRANCH}` (for example, generated locally and not pushed to remote source control), immediately create/update the trigger with `--inline-config=<INLINE_CLOUDBUILD_YAML>` (including `images:` and `options: { logging: CLOUD_LOGGING_ONLY, requestedVerifyOption: VERIFIED }` and writing `Dockerfile` inline if missing on the remote branch) so the first trigger run succeeds without `FAILED_PRECONDITION: Couldn't read commit`.
     * **Important (`--branch-pattern` vs. `--branch`)**: Pass `--branch-pattern="^${DEFAULT_BRANCH}$"` when creating the trigger, and pass the literal remote default branch name `--branch="${DEFAULT_BRANCH}"` (never with `^` or `$` regex anchors) when running `gcloud builds triggers run <TRIGGER_ID> --branch="${DEFAULT_BRANCH}"`.
   * Immediately after the Cloud Build image push completes, export and verify the SPDX SBOM for the pushed image digest per **Rule 8** before or alongside deploying to Cloud Run or GKE.
   * Use the resulting Artifact Registry image for subsequent Cloud Run or GKE deployments.
   * For 3rd-party public sample repositories (which are outside the user's Developer Connect permissions), clone and build directly.
6. **Google Cloud CLI Fallback**:
   * If no `deployment-config.json` repository is configured, fall back to `gcloud config list` to obtain the default *project* and *region*, and ask the user for confirmation before using the default target name.
7. **Automatic Agent Registry Registration for Agentic Workloads (AI Agents & MCP Servers)**:
   * Whenever the application being deployed is an **AI Agent** (e.g., uses `google-adk`, `@google/adk`, `genkit`, `langchain`, `langgraph`, `crewai`, `autogen`, `a2a-sdk`, `agent.py`, `AGENTS.md`, `manifest.yaml`, `[tool.agent-starter-pack]`, or `agent_card.json`) or an **MCP Server** (e.g., uses `mcp`, `@modelcontextprotocol/sdk`, `fastmcp`, or `mcp-spec.json`), you **MUST** use native runtime auto-registration so that **Google Cloud Agent Registry** discovers the workload with its actual compute runtime (`//run.googleapis.com/...` for Cloud Run or `//container.googleapis.com/...` for GKE) rather than a manual `//agentregistry.googleapis.com/.../services/...` entry:
     * **Cloud Run Native Auto-Registration (`--functional-type` + `--identity-type`)**:
       * Deploy (or update an existing service that was deployed without functional-type) using `gcloud beta run deploy` (or `gcloud beta run services update`) with `--functional-type=agent --identity-type=agent-identity` (or `--functional-type=mcp-server` for MCP Servers):
         ```bash
         gcloud beta run deploy "<SERVICE_NAME>" \
           --image="<IMAGE_URI>" \
           --region="<REGION>" \
           --project="<PROJECT_ID>" \
           --port="<PORT>" \
           --functional-type=agent \
           --identity-type=agent-identity \
           --allow-unauthenticated \
           --quiet
         ```
         *(This registers the service directly from the Cloud Run control plane with `agentId: urn:agent:...:run:services:<SERVICE_NAME>` and `RuntimeReference.uri: //run.googleapis.com/projects/<PROJECT_NUMBER>/locations/<REGION>/services/<SERVICE_NAME>`. Do **NOT** run `gcloud agent-registry services create` for Cloud Run workloads unless native `--functional-type` is unsupported, as manual `services create` sets the runtime reference to `agentregistry` instead of `run.googleapis.com`.)*
     * **GKE Native Auto-Registration**:
       * In Kubernetes `Deployment` manifests for AI Agents or MCP Servers, automatically add:
         * `metadata.labels["registry.gke.io/functional-type"]: "AGENT"` (or `"MCP_SERVER"`)
         * `metadata.annotations["apphub.cloud.google.com/functional-type"]: "AGENT"` (or `"MCP_SERVER"`)
         * `spec.template.metadata.annotations["iam.gke.io/spiffe-identity-type"]: "agent-identity"`
         * (If `~/.gemini/config/skills/agent-registry/scripts/annotate_gke.py` is available locally, you may also run `python3 ~/.gemini/config/skills/agent-registry/scripts/annotate_gke.py <MANIFEST_PATH> --type AGENT`.)
     * **Verification**:
       * Verify that the agent appears in Agent Registry with its Cloud Run / GKE runtime by running:
         ```bash
         gcloud agent-registry agents list --location="<REGION>" --project="<PROJECT_ID>" --filter="agentId:<SERVICE_NAME>" --format="table(name.basename(),displayName,agentId,attributes.\"agentregistry.googleapis.com/system/RuntimeReference\".uri)" --quiet
         ```
       * Include the registered Agent Registry resource name, `agentId` URN, and `RuntimeReference.uri` in the final deployment summary shown to the user.
8. **SBOM Generation on Image Build & Binary Authorization (BinAuthz) Failure Interpretation on Production Promotion**:
   * **SBOM Generation (Do Not Block Build/Dev Deploy)**: After building and pushing a container image to Artifact Registry via Cloud Build or Docker, generate the SPDX 2.3 SBOM (`artifactanalysis-2-3.spdx.json`) using `gcloud artifacts sbom export`. Do **NOT** enforce custom vulnerability-blocking checks during image build or `dev` deployment—supply-chain and vulnerability policy enforcement is handled by **Binary Authorization (BinAuthz)** when promoting/deploying to production (`prod`):
     ```bash
     DIGEST_URI=$(gcloud artifacts docker images describe "<IMAGE_URI>" \
       --project="<PROJECT_ID>" \
       --format="value(image_summary.fully_qualified_digest)" \
       --quiet)

     # Wait briefly if the automatic push DISCOVERY occurrence is still initializing, then export SBOM
     for i in 1 2 3 4 5; do
       gcloud artifacts sbom export --uri="${DIGEST_URI}" --project="<PROJECT_ID>" --quiet && break
       sleep 3
     done
     ```
   * **Interpreting Binary Authorization (`BinAuthz`) Failures on Promotion/Deployment to Production**:
     * If promoting or deploying an image to `prod` (via Cloud Run, GKE, or Cloud Deploy) fails due to Binary Authorization (e.g., Cloud Run `BinaryAuthorizationCheckFailed` / revision not ready, GKE `admission webhook "imagepolicywebhook.image-policy.k8s.io" denied the request`, or Cloud Deploy rollout failure), you **MUST** automatically inspect and interpret the Binary Authorization results to explain the exact cause of the block:
       1. **Inspect BinAuthz Audit Logs & Policy Evaluation**:
          ```bash
          # Check Cloud Audit Logs for the exact BinAuthz policy violation message
          gcloud logging read 'logName:"cloudaudit.googleapis.com%2Fpolicy" OR protoPayload.serviceName="binaryauthorization.googleapis.com" OR protoPayload.status.message:"Binary Authorization"' \
            --project="<PROJECT_ID>" --limit=10 --format=json --quiet

          # Inspect the active Binary Authorization policy and platform policies
          gcloud container binauthz policy export --project="<PROJECT_ID>" --quiet
          gcloud beta container binauthz policy list --platform=cloudRun --project="<PROJECT_ID>" --quiet 2>/dev/null || true
          gcloud beta container binauthz policy list --platform=gke --project="<PROJECT_ID>" --quiet 2>/dev/null || true
          ```
          *(If a platform policy is configured, run `gcloud beta container binauthz policy evaluate <POLICY_ID> --platform=<cloudRun|gke> --project="<PROJECT_ID>" --image="${DIGEST_URI}" --quiet` to retrieve the structured checkset evaluation result.)*
       2. **Cross-Check Attestations, Provenance, and Vulnerability Findings on the Image Digest**:
          ```bash
          # Check existing BinAuthz attestations on the image digest
          gcloud container binauthz attestations list --artifact-url="https://${DIGEST_URI}" --project="<PROJECT_ID>" --quiet

          # Check SLSA build provenance and package vulnerability scan results
          gcloud artifacts docker images describe "${DIGEST_URI}" \
            --show-provenance --show-package-vulnerability \
            --project="<PROJECT_ID>" --quiet
          ```
       3. **Explain the Root Cause Clearly to the User**:
          * Identify **which policy rule or check failed** (e.g., missing required attestation from attestor `<ATTESTOR_NAME>`, `DISALLOW_ALL` default rule, untrusted registry/image path, unverified SLSA build provenance, or CVSS vulnerability threshold violation).
          * If blocked by vulnerability or attestation requirements, list the specific missing attestor(s) or the offending CVEs (`package`, `installedVersion`, `fixedVersion`, `severity`, `cvssScore`) and provide actionable remediation steps.
