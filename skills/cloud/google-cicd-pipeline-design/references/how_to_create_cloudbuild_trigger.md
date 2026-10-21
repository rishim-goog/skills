# End-to-End Guide: Creating a Cloud Build Trigger

This document outlines the standard, idempotent procedure for creating a Google Cloud Build trigger. Creating the trigger is the **final** action in a sequence of prerequisite checks and resource provisioning steps. The agent must ensure all dependencies are met before attempting to create the trigger itself.

---

## Core Principle: Idempotency

Every step in this process must be **idempotent**. This means the agent must **always check if a resource already exists** before attempting to create it. This prevents errors and ensures the process can be run multiple times safely.

---

## Prerequisite Checklist

The following dependencies must be satisfied in order before creating the trigger.

### 1. Ensure `cloudbuild.yaml` Exists

The trigger needs a build configuration file to execute.

* **Action**: Check for a `cloudbuild.yaml` file at the root of the source repository.
* **If it does not exist**: Generate one by translating the user-approved plan. The steps in the generated YAML must be a direct translation of the components defined in the plan's `stages` object. The specifics of the steps (e.g., using `pytest` vs. `mvn test`) should be informed by discovering the application archetype (e.g., by finding a `pyproject.toml` or `pom.xml`).

### 2. Ensure Artifact Registry Repository Exists

The `cloudbuild.yaml` file will reference an Artifact Registry repository to push container images. This repository must exist before a build can succeed.

* **Action**: Parse the `cloudbuild.yaml` file to identify the Artifact Registry image path (e.g., `us-central1-docker.pkg.dev/my-project/my-app-repo/my-image`).
* **Extract** the repository portion (`us-central1-docker.pkg.dev/my-project/my-app-repo`).
* **Check** if this repository already exists in the target GCP project using `gcloud`:
  ```bash
  gcloud artifacts repositories describe <REPO_NAME> --location=<REGION> --project=<PROJECT_ID>
  ```
* **If it does not exist**: Create it using `gcloud`:
  ```bash
  gcloud artifacts repositories create <REPO_NAME> \
    --repository-format=docker \
    --location=<REGION> \
    --project=<PROJECT_ID>
  ```

### 3. Ensure Developer Connect and Repository Link Exist

Cloud Build triggers connect to source code via Developer Connect. The entire connection and repository link must be in place.

1.  **Check for Connection**: First, check if a Developer Connect connection already exists for the relevant Git provider (e.g., GitHub) in the target project and region:
    ```bash
    gcloud developer-connect connections list --location=<REGION> --project=<PROJECT_ID>
    ```
2.  **Create Connection (if needed)**: If no suitable connection exists, create one using `gcloud developer-connect connections create` (and prompt the user to complete the GitHub authorization flow via the `installationState.actionUri` in the GCP Console if `STAGE != COMPLETE`):
    ```bash
    gcloud developer-connect connections create <CONNECTION_ID> \
      --location=<REGION> \
      --project=<PROJECT_ID> \
      --github-config-app=developer-connect
    ```
3.  **Obtain Source URI**: The agent must know the exact URI of the source code repository (e.g., `https://github.com/my-org/my-app.git`). This should be obtained from the user-approved plan, `git remote get-url origin`, or by asking the user directly.
4.  **Check for Repository Link**: Check if a repository link for that specific URI already exists within the Developer Connect connection:
    ```bash
    gcloud developer-connect connections git-repository-links list \
      --connection=<CONNECTION_ID> \
      --location=<REGION> \
      --project=<PROJECT_ID>
    ```
5.  **Create Repository Link (if needed)**: If the link does not exist, create it using `gcloud`:
    ```bash
    gcloud developer-connect connections git-repository-links create <REPO_LINK_ID> \
      --connection=<CONNECTION_ID> \
      --clone-uri=<GIT_REPO_URI> \
      --location=<REGION> \
      --project=<PROJECT_ID>
    ```
    This link (`projects/<PROJECT_ID>/locations/<REGION>/connections/<CONNECTION_ID>/gitRepositoryLinks/<REPO_LINK_ID>`) is the resource that the Cloud Build trigger will formally point to.

### 4. Ensure Dedicated Service Account and Required IAM Roles Exist

Cloud Build triggers should **always** use a dedicated, user-managed service account instead of the default Compute Engine service account to follow the principle of least privilege. **CRITICAL: NEVER use the default Compute Engine service account (typically formatted as `[PROJECT_NUMBER]-compute@developer.gserviceaccount.com`), even if you observe existing triggers in the project using it.**

1.  **Check or Create Service Account**:
    ```bash
    gcloud iam service-accounts describe <SA_NAME>@<PROJECT_ID>.iam.gserviceaccount.com --project=<PROJECT_ID> || \
    gcloud iam service-accounts create <SA_NAME> \
      --display-name="Cloud Build Trigger Service Account" \
      --project=<PROJECT_ID>
    ```
2.  **Grant Required Project-Level Roles to the Dedicated Service Account**:
    Grant the necessary roles (`roles/artifactregistry.writer`, `roles/cloudbuild.builds.editor`, `roles/developerconnect.tokenAccessor`, `roles/logging.logWriter`, `roles/run.developer`, `roles/serviceusage.serviceUsageConsumer`, `roles/storage.admin`) to `serviceAccount:<SA_NAME>@<PROJECT_ID>.iam.gserviceaccount.com`:
    ```bash
    for ROLE in \
      roles/artifactregistry.writer \
      roles/cloudbuild.builds.editor \
      roles/developerconnect.tokenAccessor \
      roles/logging.logWriter \
      roles/run.developer \
      roles/serviceusage.serviceUsageConsumer \
      roles/storage.admin; do
      gcloud projects add-iam-policy-binding <PROJECT_ID> \
        --member="serviceAccount:<SA_NAME>@<PROJECT_ID>.iam.gserviceaccount.com" \
        --role="$ROLE" \
        --condition=None
    done
    ```
3.  **Grant Service Agent Roles (Developer Connect & Cloud Build P4SAs)**:
    Retrieve the project number (`PROJECT_NUMBER=$(gcloud projects describe <PROJECT_ID> --format='value(projectNumber)')`) and ensure the Developer Connect and Cloud Build service agents have required permissions:
    ```bash
    PROJECT_NUMBER=$(gcloud projects describe <PROJECT_ID> --format='value(projectNumber)')

    # Developer Connect Service Agent
    gcloud projects add-iam-policy-binding <PROJECT_ID> \
      --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-devconnect.iam.gserviceaccount.com" \
      --role="roles/secretmanager.admin" \
      --condition=None

    # Cloud Build Service Agent
    for ROLE in roles/cloudbuild.serviceAgent roles/developerconnect.tokenAccessor; do
      gcloud projects add-iam-policy-binding <PROJECT_ID> \
        --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-cloudbuild.iam.gserviceaccount.com" \
        --role="$ROLE" \
        --condition=None
    done

    # Allow Cloud Build Service Agent to act as the dedicated build SA and Cloud Run runtime SA
    gcloud iam service-accounts add-iam-policy-binding <SA_NAME>@<PROJECT_ID>.iam.gserviceaccount.com \
      --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-cloudbuild.iam.gserviceaccount.com" \
      --role="roles/iam.serviceAccountUser" \
      --project=<PROJECT_ID>
    ```
---

## Final Step: Creating the Trigger via `gcloud`

Once all prerequisites are met, check if the trigger already exists and create it using `gcloud builds triggers create developer-connect`. **You MUST provide the full resource name of the dedicated service account created in Step 4 to the `--service-account` flag.**

```bash
gcloud builds triggers describe <TRIGGER_ID> --region=<REGION> --project=<PROJECT_ID> || \
gcloud builds triggers create developer-connect \
  --name=<TRIGGER_ID> \
  --region=<REGION> \
  --project=<PROJECT_ID> \
  --repository="projects/<PROJECT_ID>/locations/<REGION>/connections/<CONNECTION_ID>/gitRepositoryLinks/<REPO_LINK_ID>" \
  --branch-pattern="<BRANCH_REGEX>" \
  --build-config="cloudbuild.yaml" \
  --service-account="projects/<PROJECT_ID>/serviceAccounts/<SA_NAME>@<PROJECT_ID>.iam.gserviceaccount.com"
```
*(Note: If the trigger should run on tags instead of branches, replace `--branch-pattern="<BRANCH_REGEX>"` with `--tag-pattern="<TAG_REGEX>"`.)*
