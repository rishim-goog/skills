# Loading Organization Deployment Configuration (`deployment-config.json`) from Source Control

This guide defines the standard procedure for retrieving, caching, and applying organization-wide deployment defaults (`deployment-config.json`) from a central Git configuration repository hosted on **any source control provider** (including **GitHub**, **GitLab**, **Bitbucket**, self-managed Git servers, or other Git hosts), aligned directly with the Administrator Runtime Configuration schema.

---

## 1. Onboarding & Persistence Lifecycle

Before asking the developer for Google Cloud parameters (`project_id`, `region`, runtime target, Artifact Registry repository, GKE cluster, or Developer Connect / Cloud Build settings), always resolve configuration in the following order:

1.  **Check Persisted Workspace Configuration First**:
    *   Inspect the workspace for an existing `.gcp-deploy/deployment-config.json` (and optional `.gcp-deploy/config-state.json` or local `gcp-deploy.json`).
    *   **Existing Project**: If `.gcp-deploy/deployment-config.json` is already present in the workspace, **read and use it immediately without asking the developer to re-configure it and without running `git pull`** (avoiding unnecessary network or credential prompt delays).
2.  **Explicit Prompt / Workspace Context Parameters**:
    *   If `.gcp-deploy/deployment-config.json` does not exist locally, but the required deployment parameters (`project_id`, `region`, and target resource name) are already explicitly provided in the user prompt or workspace context (`GEMINI.md`), use those parameters directly without stopping to ask for a `deployment-config.json` Git repository URL.
3.  **New Project Onboarding**:
    *   Otherwise, if no configuration state exists in the workspace, ask the developer **once**:
        > *"Please provide the Git repository URL (GitHub, GitLab, Bitbucket, or your source control provider) containing your organization's `deployment-config.json` (or let me know if you want to configure parameters manually)."*
    *   Once fetched, save the file to `.gcp-deploy/deployment-config.json`, record the repository URL in `.gcp-deploy/config-state.json`, and ensure `.gcp-deploy/` is ignored in `.gitignore` and `.dockerignore` so future prompts in the project automatically reuse it.

---

## 2. Pulling `deployment-config.json` Across Source Control Providers

Detect the Git provider from the repository URL (HTTPS or SSH) and retrieve `deployment-config.json` using the methods below.

### Method A: Universal Git Sparse Checkout (Works Across All Source Control Providers — GitHub, GitLab, Bitbucket, and Any Git Host)

This universal method works with **any Git source control provider** (public or private). Always pass `GIT_TERMINAL_PROMPT=0` so `git` never blocks on an interactive prompt if local credentials are not configured:

```bash
mkdir -p .gcp-deploy
rm -rf .gcp-deploy/config-repo
GIT_TERMINAL_PROMPT=0 git clone --depth 1 --filter=blob:none --sparse "<GIT_REPO_URL>" .gcp-deploy/config-repo
git -C .gcp-deploy/config-repo sparse-checkout set deployment-config.json
cp .gcp-deploy/config-repo/deployment-config.json .gcp-deploy/deployment-config.json
```

*(If a specific branch or tag `<REF>` is specified, pass `--branch <REF>` to `git clone`.)*

### Method B: Private Repo Retrieval via Google Cloud Developer Connect Token (GitHub, GitLab, Bitbucket)

If the configuration repository is private and local Git credentials are not configured in the terminal (`GIT_TERMINAL_PROMPT=0 git clone` fails with an authentication error), fetch a short-lived read token from Google Cloud Developer Connect (creating the repository link first if needed) and clone with `sparse-checkout`:

```bash
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
REGION=${REGION:-us-central1}
# Find existing connection and repo link (or create the repo link if missing)
CONNECTION_ID=$(gcloud developer-connect connections list --location="$REGION" --project="$PROJECT_ID" --format="value(name.basename())" --limit=1 --quiet)
REPO_LINK_ID=$(gcloud developer-connect connections git-repository-links list --connection="$CONNECTION_ID" --location="$REGION" --project="$PROJECT_ID" --filter="cloneUri:<GIT_REPO_URL>" --format="value(name.basename())" --limit=1 --quiet)
TOKEN=$(gcloud developer-connect connections git-repository-links fetch-read-token "$REPO_LINK_ID" --connection="$CONNECTION_ID" --location="$REGION" --project="$PROJECT_ID" --format="value(token)" --quiet)

# Inject token into HTTPS URL (x-access-token for GitHub, oauth2 for GitLab, x-token-auth for Bitbucket)
AUTH_URL=$(echo "<GIT_REPO_URL>" | sed "s|https://|https://x-access-token:${TOKEN}@|")
rm -rf .gcp-deploy/config-repo
GIT_TERMINAL_PROMPT=0 git clone --depth 1 --filter=blob:none --sparse "$AUTH_URL" .gcp-deploy/config-repo
git -C .gcp-deploy/config-repo sparse-checkout set deployment-config.json
cp .gcp-deploy/config-repo/deployment-config.json .gcp-deploy/deployment-config.json
```

### Method C: Provider-Specific CLI & Raw HTTP Fallbacks

If direct single-file retrieval is preferred over `git clone`:

#### 1. GitHub (`github.com` or GitHub Enterprise)
*   **Via GitHub CLI (`gh`)** *(handles private repos automatically)*:
    ```bash
    gh api "repos/<OWNER>/<REPO>/contents/deployment-config.json?ref=<BRANCH>" \
      -H "Accept: application/vnd.github.raw" > .gcp-deploy/deployment-config.json
    ```
*   **Via Raw HTTPS**:
    ```bash
    curl -sSfL ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
      "https://raw.githubusercontent.com/<OWNER>/<REPO>/<BRANCH>/deployment-config.json" \
      -o .gcp-deploy/deployment-config.json
    ```

#### 2. GitLab (`gitlab.com` or Self-Managed GitLab)
*   **Via GitLab CLI (`glab`)** *(handles private repos automatically; replace `/` in `<GROUP>/<PROJECT>` with `%2F`)*:
    ```bash
    glab api "projects/<URL_ENCODED_PROJECT_PATH>/repository/files/deployment-config.json/raw?ref=<BRANCH>" \
      > .gcp-deploy/deployment-config.json
    ```
*   **Via GitLab REST API / Raw HTTPS**:
    ```bash
    curl -sSfL ${GITLAB_TOKEN:+-H "PRIVATE-TOKEN: $GITLAB_TOKEN"} \
      "https://<GITLAB_HOST>/<GROUP>/<PROJECT>/-/raw/<BRANCH>/deployment-config.json" \
      -o .gcp-deploy/deployment-config.json
    ```

#### 3. Bitbucket (`bitbucket.org` or Bitbucket Data Center)
*   **Via Bitbucket Cloud API / Raw HTTPS**:
    ```bash
    curl -sSfL ${BITBUCKET_TOKEN:+-H "Authorization: Bearer $BITBUCKET_TOKEN"} \
      "https://api.bitbucket.org/2.0/repositories/<WORKSPACE>/<REPO_SLUG>/src/<BRANCH>/deployment-config.json" \
      -o .gcp-deploy/deployment-config.json
    ```
    *(Or with Bitbucket App Password: `curl -sSfL -u "$BITBUCKET_USERNAME:$BITBUCKET_APP_PASSWORD" "https://bitbucket.org/<WORKSPACE>/<REPO_SLUG>/raw/<BRANCH>/deployment-config.json" -o .gcp-deploy/deployment-config.json`)*

---

## 3. `deployment-config.json` Schema (Aligned with Local Skill Config Prototype)

The `deployment-config.json` file maps 1-to-1 to the 4 configuration sections in the CI/CD integration prototype:

1.  **Runtime Selection & Common Settings** (`active_runtime`, `default_environment`, `fail_on_push_error`, `common_gcp_settings`)
2.  **Runtime: Google Cloud Run Configuration** (`cloud_run.dev`, `cloud_run.prod`)
3.  **Runtime: Google Kubernetes Engine (GKE) Configuration** (`gke.dev`, `gke.prod`)
4.  **Developer Connect & Cloud Build Configuration** (`build_mode`, `developer_connect`, `cloud_build_trigger`)

```json
{
  "active_runtime": "Cloud Run",
  "default_environment": "dev",
  "fail_on_push_error": true,
  "common_gcp_settings": {
    "project_id": "my-gcp-project",
    "region": "us-central1"
  },
  "cloud_run": {
    "dev": {
      "project_id": "my-gcp-project",
      "region": "us-central1",
      "artifact_registry": "us-central1-docker.pkg.dev/my-gcp-project/my-app-images-dev",
      "service_name": "<app-name>-dev",
      "public_access": true,
      "container_port": 8080
    },
    "prod": {
      "project_id": "my-gcp-project",
      "region": "us-central1",
      "artifact_registry": "us-central1-docker.pkg.dev/my-gcp-project/my-app-images-prod",
      "service_name": "<app-name>-prod",
      "public_access": false,
      "container_port": 8080,
      "require_confirmation": true
    }
  },
  "gke": {
    "dev": {
      "project_id": "my-gcp-project",
      "cluster_location": "us-central1",
      "cluster_name": "my-gke-cluster-dev",
      "namespace": "dev",
      "artifact_registry": "us-central1-docker.pkg.dev/my-gcp-project/my-app-images-dev",
      "manifest_path": "./kubernetes-manifests/"
    },
    "prod": {
      "project_id": "my-gcp-project",
      "cluster_location": "us-central1",
      "cluster_name": "my-gke-cluster-prod",
      "namespace": "prod",
      "artifact_registry": "us-central1-docker.pkg.dev/my-gcp-project/my-app-images-prod",
      "manifest_path": "./release/kubernetes-manifests.yaml",
      "require_confirmation": true
    }
  },
  "developer_connect_and_cloud_build": {
    "build_mode": "Developer Connect + Cloud Build",
    "developer_connect": {
      "location": "us-central1",
      "connection_id": "my-devconnect-connection"
    },
    "cloud_build_trigger": {
      "project_id": "my-gcp-project",
      "region": "us-central1",
      "service_account": "projects/my-gcp-project/serviceAccounts/cloudbuild-runner@my-gcp-project.iam.gserviceaccount.com",
      "default_branch": "^main$",
      "auto_run_trigger": true
    }
  }
}
```

---

## 4. Agent Execution Rules

When `deployment-config.json` is loaded from the Git repository, enforce the following 5 execution rules:

1.  **Runtime Determination**:
    *   If `active_runtime` is set to `"Cloud Run"` or `"GKE"`, use that target directly without asking.
    *   If set to `"prompt"`, ask the user: *"Would you like to deploy to Cloud Run or GKE?"*
2.  **Environment Determination & Auto-Population**:
    *   Use the environment specified in the user's prompt (`dev` or `prod`). If unspecified, use `default_environment` (or if only one environment exists in `deployment-config.json`, default to that environment; otherwise prompt the user).
    *   Once the runtime (`cloud_run` or `gke`) and environment (`dev` or `prod`) are determined, **automatically populate all parameters from that section without asking the user** for project ID, region, Artifact Registry URI, service/cluster name, namespace, manifest path, or container port.
    *   When `require_confirmation` is `true` (always enforced for `prod`), always require explicit user confirmation before deploying to `prod`.
3.  **Deployment Target Naming**:
    *   Derive `<app-name>` from the Git repository name (`git remote get-url origin`) or current directory name, and apply the configured environment pattern (e.g., `<app-name>-dev` or `<app-name>-prod`).
4.  **Artifact Registry Push Enforcement**:
    *   When `fail_on_push_error` is `true` (default), pushing the image to the configured `artifact_registry` URI is mandatory. If the push fails for any reason (authentication, permissions, network, or Cloud Build errors), **immediately fail the deployment and report the error to the user**. Never bypass Artifact Registry by falling back to external or public registries (such as Docker Hub).
5.  **Developer Connect & Cloud Build Enforcement**:
    *   Whenever `build_mode` is `"Developer Connect + Cloud Build"` (or `"developer-connect"`) and deploying from the user's own source control repository (**GitHub**, **GitLab**, **Bitbucket**, or any supported Git provider), **do NOT build locally using Docker CLI** and **do NOT check or worry about unpublished local branches**—always use the **default branch in the remote source control repository**.
    *   Determine the remote repository's default branch universally across any Git provider (even for private repos with no local clone) via Developer Connect's read token + `git ls-remote --symref`:
        ```bash
        TOKEN=$(gcloud developer-connect connections git-repository-links fetch-read-token <REPO_LINK_ID> \
          --connection=<CONNECTION_ID> --location=<REGION> --project=<PROJECT_ID> --format="value(token)" --quiet 2>/dev/null || true)
        AUTH_URI=$(echo "<GIT_REPO_URI>" | sed "s|https://|https://x-access-token:${TOKEN}@|")
        DEFAULT_BRANCH=$(GIT_TERMINAL_PROMPT=0 git ls-remote --symref "${TOKEN:+$AUTH_URI}${TOKEN:-<GIT_REPO_URI>}" HEAD 2>/dev/null | awk '/^ref:/ {sub("refs/heads/", "", $2); print $2}')
        ```
        *(Only fall back to `default_branch` in `deployment-config.json` with `^` and `$` stripped if the remote `HEAD` ref cannot be resolved.)*
    *   Automatically link the repository to Developer Connect using `gcloud developer-connect connections git-repository-links create` under the configured `developer_connect.connection_id`.
    *   Create or run the Cloud Build trigger using `gcloud builds triggers create developer-connect` (or `gcloud beta builds triggers create developer-connect`) and `gcloud builds triggers run` with the pre-configured dedicated `cloud_build_trigger.service_account`:
        *   **Mandatory `CLOUD_LOGGING_ONLY`**: Always include `options: { logging: CLOUD_LOGGING_ONLY }` in the Cloud Build configuration when using a dedicated `--service-account`.
        *   **Check Remote Branch for `cloudbuild.yaml` & `Dockerfile`**: Inspect `git ls-tree "origin/${DEFAULT_BRANCH}" cloudbuild.yaml Dockerfile`. If `cloudbuild.yaml` or `Dockerfile` is not committed on `origin/${DEFAULT_BRANCH}`, use `--inline-config=<INLINE_CLOUDBUILD_YAML>` (with `options: { logging: CLOUD_LOGGING_ONLY }` and inline `Dockerfile` creation if needed) so the trigger succeeds on the first run.
        *   **Use Remote Default Branch & Strip Regex Anchors for `triggers run`**: When creating a trigger, pass `--branch-pattern="^${DEFAULT_BRANCH}$"`. When calling `gcloud builds triggers run <TRIGGER_ID> --branch="${DEFAULT_BRANCH}"`, always pass the literal default branch name without `^` or `$` regex anchors.
        *   **Batch CLI Execution**: Combine Artifact Registry check/create, Developer Connect repo link check/create, and Cloud Build trigger check/create/run into a single shell script without calling `gcloud help` first.
    *   Use the resulting Artifact Registry image for subsequent Cloud Run or GKE deployments.
    *   For 3rd-party public sample repositories (which are outside the user's Developer Connect permissions), clone and build directly.
