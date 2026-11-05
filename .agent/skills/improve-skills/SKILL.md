---
name: improve-skills
description: >
  Use this skill to analyze evaluation results across Gemini, Claude, and OpenAI (Codex) models to identify gaps and improve skills with general-purpose updates. Avoids biasing updates solely for evaluation success.
  **Why**: Encodes best practices for skill improvement that prevent overfitting to specific evaluations or single-model quirks, ensuring skills remain robust, portable, and broadly applicable. It helps differentiate between skill gaps and environment issues.
  **When**:
  - After completing an evaluation run to analyze failures (use along with `author-evals` to determine if the fix belongs in the skill or the eval).
  - When identifying a need to generalize a solution beyond a specific test case or across multiple LLM families (`gemini`, `claude`, `codex`).
  - When updating skills and their `references/` deep docs to improve clarity and coverage of edge cases and error handling.
---

# Skill Improvement from Evaluation Analysis

This skill outlines the process for analyzing evaluation results to improve the core skills (`SKILL.md` and `references/` deep docs) used by the agent. It emphasizes making robust, general improvements rather than "hacking" the skills to pass specific evaluation checks.

## Workflow

### Step 1: Gather Evaluation Results

1.  Locate the evaluation results. These may be in a local directory (`eval-results/<timestamp>/<model>/`) or a Google Cloud Storage bucket.
2.  If the results are in GCS, use `gsutil` or `gcloud storage` to list and copy the files locally for analysis.
3.  Read the result JSON files across all evaluated models (`gemini`, `claude`, `codex`) to understand the tasks run, pass rates, and specific failure details in `grader_results`.
4.  **Debugging with Workspaces**: For detailed debugging of failures, including inspecting generated files and running validation scripts, refer to the `author-evals` skill.

### Step 2: Analyze Against Configuration (`eval.yaml` / `eval.criteria.yaml`)

1.  Read `eval.yaml` and `eval.criteria.yaml` in the repository root to understand the specific requirements and expected behaviors for each task.
2.  Pay attention to the `graders` section, including deterministic scripts (`scripts/validate-*.py`, `scripts/validate-*.sh`) and `llm_rubric` assertions.
3.  Compare the actual outputs in the result logs with the expectations in the eval config.
4.  **Identify Eval Flaws**: Check if the eval config contains cases that are overly constrained or that should be changed to better test the skill.

### Step 3: Identify Skill & Reference Doc Gaps

1.  Locate the current skills in the `./skills` directory at the workspace root (not in `.agent/skills`).
2.  Analyze both the top-level `SKILL.md` and all deep reference files in `./skills/cloud/<skill>/references/` to see if they cover the failed scenario or if `references/` has drifted out of sync with `SKILL.md`.
3.  Identify gaps where `SKILL.md` or `references/` lacks clarity on mandatory steps, multi-provider support (GitHub, GitLab, Bitbucket), supply-chain security (SBOMs, Binary Authorization, secret leak prevention), or authentication/permission error handling.
4.  **Differentiate Environment Issues**: Check if the failure was caused by the test environment (e.g., missing IAM permissions, disabled APIs, missing tools). If so, call this out to the user as an environment failure, write a local file (e.g., `ENV_ISSUES.md`) to the workspace root detailing the issue and required action, and do not update the skill to fix it.

### Step 4: Formulate General, Cross-Model Improvements

1.  **Rule of No Eval Bias**: When updating a skill, do NOT reference "evaluation scores", "evals", or specific evaluation tasks. Never update a skill to simply check for a specific file named in an eval or to use a specific tool just because the eval requires it, unless that tool is a best practice for the workflow.
2.  **Keep `SKILL.md` and `references/` Synchronized**: Whenever a workflow rule, JSON schema field (such as `sample-deployment-config.json`), or CLI flag requirement is updated in `SKILL.md`, immediately update the corresponding deep documentation under `references/` so agents reading progressive disclosure docs receive consistent instructions.
3.  **Cross-Model Portability (`Gemini`, `Claude`, `OpenAI Codex`)**:
    - Write clear, deterministic shell snippets and structured checklists that work equally well across Gemini, Claude, and OpenAI models.
    - Reference workspace context files portably (`GEMINI.md`, `CLAUDE.md`, or `AGENTS.md`).
4.  Focus on **Scope and Applicability**: Update descriptions to follow a consistent pattern in the YAML front matter:
    - High-level description.
    - Why it's important to activate (encoding best practices that tools alone cannot achieve).
    - When to activate (triggers).
    - Respect the hard limit of 1024 characters for descriptions.
5.  **Move Triggers to Description**: Include skill activation triggers within the description field of the YAML front matter to make them immediately visible to the model and encourage activation.
6.  Focus on **Best Practices & Error Handling**: Add instructions that ensure correct, secure operation (e.g., pre-build secret scanning, SPDX SBOM export, Binary Authorization verification, and fail-closed diagnosis on `401`/`403` authentication or permission errors without bypassing security controls).
7.  **Incremental Focus**: Prioritize targeted, well-structured updates over broad rewrites.

## External References

For more best practices on skill creation and optimization, refer to the official documentation:
- [Skill Creation Guide](https://agentskills.io/skill-creation)
- [Best Practices](https://agentskills.io/skill-creation/best-practices)
- [Optimizing Descriptions](https://agentskills.io/skill-creation/optimizing-descriptions)
