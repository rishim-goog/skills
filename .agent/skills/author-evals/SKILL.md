---
name: author-evals
description: >
  Use this skill to author and debug evaluations for skillgrade across Gemini, Anthropic Claude, and OpenAI (Codex) models, including eval.yaml, deterministic and error-handling grader scripts, environment variables, and test project setup.
  **Why**: Ensures evaluations are reliable, isolated, multi-model compatible, and accurately measure agent capabilities (including both positive workflows and negative/error-handling cases) without implementation bias.
  **When**:
  - When creating new evaluation tasks or graders.
  - When ensuring evaluations work across Gemini (`gemini`), Anthropic Claude (`claude`), and OpenAI (`codex`) models.
  - When debugging failed evaluations (use along with `improve-skills` to determine if the fix belongs in the eval or the skill).
  - When refining instructions or workspace isolation in `eval.yaml` or `eval.criteria.yaml`.
---

# Authoring Evals for SkillGrade

This skill provides guidelines and best practices for authoring evaluations using the `skillgrade` tool across **Gemini (`gemini`)**, **Anthropic Claude (`claude`)**, and **OpenAI (`codex`)** models. Evaluations are defined in `eval.yaml` and `eval.criteria.yaml`.

## Identifying Target Skills

When authoring an evaluation, first identify which skill (or skills) should be evaluated.
The skills are located in the `./skills` directory for the project.
This information is crucial for determining what evaluation cases (both positive workflows and negative/authentication error scenarios) would be useful.

## Generating Eval Cases

Aim for comprehensive evaluation coverage across both happy-path and error-handling scenarios:
- **Positive Workflow Tasks**: Test core capabilities, configuration discovery/generation, multi-provider Git integrations (GitHub, GitLab, Bitbucket), runtime targets (Cloud Run, GKE), workload types (Web apps, AI Agents, MCP Servers), and supply-chain security (SPDX SBOMs, Binary Authorization, secret leak interception).
- **Authentication, Permission & Security Error Tasks**: Test how the agent behaves when credentials expire (`401`), IAM roles are missing (`403 PERMISSION_DENIED`), private Git repositories lack tokens, Cloud Build custom service accounts are misconfigured, Binary Authorization blocks an unattested image (`IMAGE_UNTRUSTED`), or GKE RBAC denies access. Verify the agent diagnoses the exact root cause, provides actionable remediation, and **never bypasses security controls** or fabricates deployment URLs.

## Multi-Model Compatibility (`gemini`, `claude`, `codex`)

All evaluations in this repository must work seamlessly across **Google Gemini (`gemini`)**, **Anthropic Claude (`claude`)**, and **OpenAI (`codex`)**:

1. **Mirror Workspace Context Files**:
   Different agent CLIs read project context from different filenames:
   - Gemini CLI reads `/root/.gemini/GEMINI.md` and `./GEMINI.md`
   - Claude Code CLI reads `./CLAUDE.md`
   - OpenAI Codex CLI reads `./AGENTS.md`
   Always populate all four files with identical project context (`PROJECT_ID`, `REGION`, `DEVCONNECT_CONNECTION_ID`) in every task's `workspace:` section (or via YAML anchors like `*multi_model_context`).
2. **Pass Multi-Model API Keys in `defaults.env`**:
   Include `GEMINI_API_KEY`, `OPENAI_API_KEY`, and `ANTHROPIC_API_KEY` in `defaults.env` and `Dockerfile.eval`.
3. **Model-Agnostic Graders**:
   Deterministic graders (`scripts/validate-*.py`, `scripts/validate-*.sh`) must inspect **GCP state, workspace files, and `deployment-error-diagnosis.md`** rather than parsing model-specific CLI session log formats.

## Eval Configuration (`eval.yaml` / `eval.criteria.yaml`)

The `eval.yaml` and `eval.criteria.yaml` files define the tasks, environment, and graders for evaluation.

### Key Sections

- **`defaults`**: Set base configuration for all tasks.
    - `agent`: Default model to use (`gemini`; overridden at runtime via `--agent=claude` or `--agent=codex`).
    - `provider`: Execution environment (`docker` or `local`).
    - `docker`: Base image and setup commands (`Dockerfile.eval` pre-installs `@google/gemini-cli`, `@anthropic-ai/claude-code`, `@openai/codex`, `gcloud`, `kubectl`, `terraform`, `gh`, `glab`).
    - `env`: Base environment variables (`PROJECT_ID`, `REGION`, `GEMINI_API_KEY`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`).
    - `environment.mounts`: Bind mounts for Docker (`~/.config/gcloud`).
- **`tasks`**: List of evaluation tasks.
    - `name`: Unique task name.
    - `instruction`: Clear instructions for the agent, including expected output file names (e.g., `deployment-config.json`, `deployment-error-diagnosis.md`).
    - `workspace`: Files to include in the container. Use isolation; do not assume files are present.
    - `trialConfig`: Setup and cleanup hooks for each trial.
    - `graders`: Graders used to evaluate performance.

### Workspace Isolation

By default, **no files are auto-included** in the execution environment. You must explicitly specify all files and directories needed for the task in the `workspace` section:

```yaml
workspace:
  - src: fixtures/broken-app.js
    dest: app.js
  - content: &context_doc |
      # Project Context
      PROJECT_ID=${PROJECT_ID}
      REGION=${REGION}
    dest: /root/.gemini/GEMINI.md
  - content: *context_doc
    dest: GEMINI.md
  - content: *context_doc
    dest: CLAUDE.md
  - content: *context_doc
    dest: AGENTS.md
```

## Graders

Authoring effective graders is key to reliable evaluations.

### 1. Deterministic Graders (Recommended)

Deterministic graders run a script or command and evaluate the outcome objectively. They are more reliable and faster than LLM graders.

- **Output Format**: The grader script MUST output a JSON object to `stdout` with at least `score` (0.0 to 1.0) and `details` (string).
- **Bash Example**:
    ```bash
    #!/bin/bash
    # Grade outcome, not steps!
    if test -f output.txt; then
      echo '{"score": 1.0, "details": "Output file exists"}'
    else
      echo '{"score": 0.0, "details": "Output file missing"}'
    fi
    ```
- **Rule**: Use `awk` or `python3` for arithmetic instead of `bc`, as `bc` is not available in standard `node:20-slim` images.

### 2. LLM Rubric Graders

LLM rubric graders are used for qualitative criteria.

- **Format**: Outcome assertions are recommended for binary checks. Free-text rubrics are also supported.
- **Outcome Assertions Example**:
    ```yaml
    - type: llm_rubric
      outcome_assertions:
        - Did the agent follow the mandatory 3-step workflow?
        - Did it complete in <=5 commands?
      weight: 0.3
    ```

### 3. Tool Usage Graders

Verifies that the agent called specific tools during the trial.

Example:
```yaml
- type: tool_usage
  expectedTools:
    - name: read_file
    - name: write_to_file
      args:
        path: test.txt
```

Final reward is a weighted sum of all grader scores.

## Environment Variables

Proper environment variable configuration ensures trials are isolated and reproducible.

### Dynamic Variables

Use the `{{trial}}` placeholder in environment variables to create unique values per trial (e.g., ports, resource names). SkillGrade also auto-injects:
- `_EVAL_TRIAL`: Current trial ID.
- `_EVAL_UUID`: Unique run identifier.

Example usage in instructions or scripts:
- `PROJECT_ID`: Project to target.
- `REGION`: Deployment region.
- `gs://${_EVAL_UUID}-${_EVAL_TRIAL}`: Unique bucket name.

## IAM Permissions and Test Project Setup

When evaluations interact with cloud resources (like Google Cloud in this project), suggest required permissions and setup.

### IAM Permissions

Suggest minimal permissions required for the test:
- **Storage Admin** for GCS bucket operations.
- **Cloud Run Admin** for service deployments.
- **Artifact Registry Admin** for image uploads and SBOM exports.
- **Cloud Build Editor** & **Developer Connect Admin** for CI/CD trigger evaluations.
- **Kubernetes Engine Developer** for GKE evaluations.

Advise the user to use limited service accounts rather than Owner roles.

### Setup and Cleanup Scripts

- **Setup scripts**: Clone necessary repositories, install dependencies, or provision base resources (`scripts/setup-eval-env.sh`).
- **Cleanup scripts**: Crucial for deleting resources created during the evaluation (e.g., GCS buckets, Cloud Run services, GKE deployments, Cloud Build triggers) to avoid leaks and costs.

## Running Evaluations (Single-Model & Multi-Model)

1.  **Export API Keys**: Export `GEMINI_API_KEY`, `ANTHROPIC_API_KEY`, and/or `OPENAI_API_KEY`.
2.  **Run Multi-Model Runner (Recommended)**:
    ```bash
    ./scripts/run-multi-model-evals.sh --config eval.criteria.yaml --models gemini,claude,codex
    ```
    *(On a Google Cloudtop without Docker daemon, pass `--provider local`.)*
3.  **Run Single-Model `skillgrade` Command**:
    ```bash
    npx skillgrade --config eval.criteria.yaml --agent gemini --no-redact --save-trial-workspace
    ```

### Debugging Running Evaluations

While an evaluation is running in Docker, you can use standard Docker commands to inspect the environment and agent behavior:

1.  **Find Container ID**: Use `docker ps` to find the container ID of the running trial.
2.  **Interactive Shell**: Get an interactive shell in the container:
    ```bash
    docker exec -it <container_id> sh
    ```
3.  **Inspect Processes**: Inside the container, run `ps -ax` to see the agent CLI invocation (`gemini`, `claude`, or `codex`) and running tools/MCP servers.

### Debugging Failed Evaluations with Saved Workspaces

1.  **Enable Saved Workspaces**: Use the `--save-trial-workspace` flag when running `skillgrade` to persist the trial workspace.
2.  **Locate Workspace**: The persisted workspaces will be available under the `workspaces/` directory in your output directory.
3.  **Inspect and Validate**:
    -   Look at files generated or modified by the agent/skill.
    -   Run validation scripts manually against the saved workspace to understand why they failed.

## Best Practices

- **Grade outcomes, not steps.** Check that the file or cloud resource was created/diagnosed accurately, not that the agent ran a specific internal tool.
- **Instructions must name output files.** The grader must know what to check (e.g., `deployment-config.json`, `deployment-error-diagnosis.md`).
- **Maintain cross-model parity.** Never rely on features exclusive to one agent CLI when authoring tasks or graders.

## Improving Evals based on Results

1.  **Gather Results**: Locate the evaluation results (local or GCS).
2.  **Analyze Logs**: Look at the agent execution logs across `gemini`, `claude`, and `codex`.
3.  **Identify Inefficiencies**:
    - Is the agent looping?
    - Are the instructions ambiguous?
    - **Handle Environment Issues**: If the failure was caused by the test environment (e.g., missing IAM permissions, disabled APIs, expired ADC), write `ENV_ISSUES.md` to the workspace root detailing the issue and required action, and do not update the eval to fix it unless the eval setup itself is flawed.
4.  **Rule of No Tool Bias & No Implementation Bias**: Eval instructions must test the outcome, not force specific internal tool names or rigid implementation details that lead to overfitting.
