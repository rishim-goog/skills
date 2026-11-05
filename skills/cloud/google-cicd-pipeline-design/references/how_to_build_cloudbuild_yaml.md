# How to Create a `cloudbuild.yaml` File

This document outlines the standard procedure for automatically generating a `cloudbuild.yaml` configuration file. The primary goal is to create a best-practice, archetype-specific CI/CD pipeline when one does not already exist in the user's repository.

---

## When to Generate a `cloudbuild.yaml`

The core principle is to be non-destructive and idempotent. The generation process should only be triggered under one specific condition:

* **A `cloudbuild.yaml` file does not exist at the root of the source repository (or on the remote default branch when creating a Cloud Build trigger).**

If a `cloudbuild.yaml` file is already present, it should be treated as the source of truth and used as-is without modification, unless the user explicitly requests a change (or if `logging: CLOUD_LOGGING_ONLY` must be added for custom service account compatibility).

---

## Step 1: Discovering the Application Archetype

Before a `cloudbuild.yaml` can be generated, the application's archetype must be identified. This is done by inspecting the local filesystem for common project files. This discovery step is crucial for tailoring the build steps (e.g., linting, testing, Agent Registry registration) to the specific language or framework.

The following mapping should be used:

* `pom.xml` → **Java (Maven)**
* `build.gradle` → **Java (Gradle)**
* `package.json` → **Node.js** (check for `@modelcontextprotocol/sdk` for MCP Servers)
* `requirements.txt` or `pyproject.toml` → **Python** (check for `google-adk`, `langchain`, `langgraph`, `crewai`, `autogen` for AI Agents, or `mcp`, `fastmcp` for MCP Servers)
* `go.mod` → **Go**

---

## Step 2: Generating the Default CI Pipeline

If no `cloudbuild.yaml` exists, a new one should be generated with a standard, four-step CI sequence (plus optional SPDX SBOM export and deployment steps when requested). These steps must be tailored to the discovered application archetype.

1.  **Lint**: Run a static code analysis tool to check for stylistic or programmatic errors. The specific linter should match the application archetype (e.g., `pylint` or `ruff` for Python, `eslint` for Node.js).
2.  **Test**: Execute the project's unit tests. The test runner should match the archetype (e.g., `pytest` for Python, `go test` for Go, `mvn test` for Maven).
3.  **Build Container**: Use the native `gcr.io/cloud-builders/docker` builder to build the container image from the `Dockerfile` in the repository.
4.  **Push Container & Export SBOM**: Push the newly built container image to the verified Artifact Registry repository and optionally export an SPDX Software Bill of Materials (`gcloud artifacts sbom export`).

---

## Key Best Practices and Configuration

When generating the `cloudbuild.yaml`, several best practices must be included to ensure security, compatibility with custom service accounts, and supply-chain verification:

* **Image Tagging**: The container image must be tagged with the `$SHORT_SHA` substitution variable (or `:latest` when triggered ad-hoc). This ensures a unique, traceable image for every commit.
* **Use the `images` Attribute**: The final image URI should be explicitly listed under the top-level `images` attribute in the `cloudbuild.yaml`. This allows Cloud Build to push the image and record build provenance automatically.
* **Mandatory `logging: CLOUD_LOGGING_ONLY` for Custom Service Accounts**: Whenever a Cloud Build trigger or build uses a user-managed `--service-account` (as required in `deployment-config.json`), Cloud Build requires `logging: CLOUD_LOGGING_ONLY` inside the `options:` block. Omitting `CLOUD_LOGGING_ONLY` causes builds with custom service accounts to fail with `INVALID_ARGUMENT`.
* **Enable Provenance**: To enhance supply chain security and support Binary Authorization policies on `prod`, build provenance should always be enabled by setting `requestedVerifyOption: VERIFIED` under `options:`.

---

## Example: Python Application

Here is a complete, best-practice `cloudbuild.yaml` generated for a Python application that uses `pytest` for testing, exports an SPDX SBOM, and configures both `CLOUD_LOGGING_ONLY` and SLSA provenance verification.

```yaml
# Auto-generated cloudbuild.yaml for a Python application

steps:
  # Step 1: Install dependencies
  - name: 'python:3.12-slim'
    entrypoint: 'pip'
    args: ['install', '-r', 'requirements.txt', '--user']

  # Step 2: Run unit tests with pytest
  - name: 'python:3.12-slim'
    entrypoint: 'python'
    args: ['-m', 'pytest']

  # Step 3: Build the container image
  # The image is tagged with the short commit SHA for traceability.
  - name: 'gcr.io/cloud-builders/docker'
    args:
      - 'build'
      - '-t'
      - '${_LOCATION}-docker.pkg.dev/${PROJECT_ID}/${_REPO_NAME}/${_IMAGE_NAME}:$SHORT_SHA'
      - '.'

  # Step 4: Push the container image to Artifact Registry
  - name: 'gcr.io/cloud-builders/docker'
    args:
      - 'push'
      - '${_LOCATION}-docker.pkg.dev/${PROJECT_ID}/${_REPO_NAME}/${_IMAGE_NAME}:$SHORT_SHA'

  # Step 5 (Optional): Export SPDX SBOM for supply-chain verification
  - name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        DIGEST=$(gcloud artifacts docker images describe "${_LOCATION}-docker.pkg.dev/${PROJECT_ID}/${_REPO_NAME}/${_IMAGE_NAME}:$SHORT_SHA" --format="value(image_summary.digest)")
        gcloud artifacts sbom export --uri="${_LOCATION}-docker.pkg.dev/${PROJECT_ID}/${_REPO_NAME}/${_IMAGE_NAME}@${DIGEST}" --project="${PROJECT_ID}" || true

# Explicitly list the final image to be pushed and verified.
images:
  - '${_LOCATION}-docker.pkg.dev/${PROJECT_ID}/${_REPO_NAME}/${_IMAGE_NAME}:$SHORT_SHA'

# Enable CLOUD_LOGGING_ONLY (mandatory for custom service accounts) and SLSA provenance.
options:
  logging: CLOUD_LOGGING_ONLY
  requestedVerifyOption: VERIFIED
```
