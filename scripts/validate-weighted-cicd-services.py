#!/usr/bin/env python3
"""Deterministic grader for Prompt #1 (Scenarios #1 and #2): Weighted CI/CD service usage.

Criteria from evaluation spec:
- AGY Agent should use Cloud Build, DevConnect and Artifact Registry.
- If only a portion of the services are used, partial score should be deducted.
- Not using Artifact Registry MUST be weighted as a higher deduction than not using
  Cloud Build or DevConnect.

Weights:
- Artifact Registry used (image pushed to configured Artifact Registry): 0.50
- Cloud Build used (build submitted / trigger created & run):            0.25
- Developer Connect used (git-repository-link created/used):             0.25
"""

import argparse
import json
import os
import subprocess


def run_cmd(cmd):
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        return res.returncode == 0, res.stdout.strip(), res.stderr.strip()
    except Exception as exc:
        return False, "", str(exc)


def check_artifact_registry(project_id, region, repo_or_uri, workspace_dir):
    """Checks if an image was pushed to Artifact Registry or configured in build output."""
    if repo_or_uri:
        # Normalize URI (e.g. us-central1-docker.pkg.dev/project/repo)
        uri = repo_or_uri
        if "/" not in uri and project_id and region:
            uri = f"{region}-docker.pkg.dev/{project_id}/{repo_or_uri}"
        ok, out, _ = run_cmd(
            [
                "gcloud",
                "artifacts",
                "docker",
                "images",
                "list",
                uri,
                f"--project={project_id}",
                "--limit=5",
                "--format=json",
                "--quiet",
            ]
        )
        if ok and out and out != "[]":
            return True, f"Verified container image(s) in Artifact Registry ({uri})"

    # Fallback check in workspace manifests / cloudbuild.yaml / gcp-deploy.json
    for root, dirs, files in os.walk(workspace_dir):
        dirs[:] = [d for d in dirs if d not in [".git", "node_modules", ".venv"]]
        for fname in files:
            if fname.endswith((".yaml", ".yml", ".json", ".sh")):
                fpath = os.path.join(root, fname)
                try:
                    with open(fpath, "r", encoding="utf-8", errors="ignore") as f:
                        content = f.read()
                    if "-docker.pkg.dev/" in content:
                        return True, f"Found Artifact Registry image reference in {fname}"
                except Exception:
                    pass

    return False, "Artifact Registry was NOT used (high deduction applied: -0.50)"


def check_cloud_build(project_id, region, workspace_dir):
    """Checks if Cloud Build trigger or build was executed in the project."""
    if project_id:
        for cmd in (
            [
                "gcloud",
                "builds",
                "triggers",
                "list",
                f"--project={project_id}",
                f"--region={region}",
                "--limit=5",
                "--format=json",
                "--quiet",
            ],
            [
                "gcloud",
                "builds",
                "list",
                f"--project={project_id}",
                "--limit=5",
                "--format=json",
                "--quiet",
            ],
        ):
            ok, out, _ = run_cmd(cmd)
            if ok and out and out != "[]":
                return True, "Verified Cloud Build trigger/build activity in GCP project"

    for root, dirs, files in os.walk(workspace_dir):
        dirs[:] = [d for d in dirs if d not in [".git", "node_modules", ".venv"]]
        if "cloudbuild.yaml" in files:
            return True, "Found cloudbuild.yaml in workspace"

    return False, "Cloud Build was NOT used (deduction applied: -0.25)"


def check_developer_connect(project_id, region, connection_id, workspace_dir):
    """Checks if Developer Connect connection / git-repository-link was used."""
    if project_id and region and connection_id:
        ok, out, _ = run_cmd(
            [
                "gcloud",
                "developer-connect",
                "connections",
                "git-repository-links",
                "list",
                f"--connection={connection_id}",
                f"--location={region}",
                f"--project={project_id}",
                "--limit=5",
                "--format=json",
                "--quiet",
            ]
        )
        if ok and out and out != "[]":
            return True, f"Verified Developer Connect repository link under connection '{connection_id}'"

    # Check if deployment-config.json or terraform / scripts reference developer-connect
    config_path = os.path.join(workspace_dir, ".gcp-deploy", "deployment-config.json")
    if os.path.exists(config_path):
        try:
            with open(config_path, "r", encoding="utf-8") as f:
                cfg = json.load(f)
            dc_cfg = cfg.get("developer_connect_and_cloud_build", {})
            if dc_cfg.get("developer_connect", {}).get("connection_id"):
                return True, "Verified Developer Connect configuration loaded in .gcp-deploy/deployment-config.json"
        except Exception:
            pass

    return False, "Developer Connect was NOT used (deduction applied: -0.25)"


def main():
    parser = argparse.ArgumentParser(
        description="Weighted grader for Artifact Registry (0.50), Cloud Build (0.25), and Developer Connect (0.25)."
    )
    parser.add_argument("--workspace", default=".", help="Workspace directory")
    parser.add_argument(
        "--project-id", default=os.environ.get("PROJECT_ID", ""), help="GCP Project ID"
    )
    parser.add_argument(
        "--region", default=os.environ.get("REGION", "us-central1"), help="GCP Region"
    )
    parser.add_argument(
        "--artifact-registry",
        default=os.environ.get("ARTIFACT_REGISTRY", ""),
        help="Artifact Registry repo name or URI",
    )
    parser.add_argument(
        "--connection-id",
        default=os.environ.get("DEVCONNECT_CONNECTION_ID", ""),
        help="Developer Connect connection ID",
    )
    args = parser.parse_args()

    ar_passed, ar_msg = check_artifact_registry(
        args.project_id, args.region, args.artifact_registry, args.workspace
    )
    cb_passed, cb_msg = check_cloud_build(
        args.project_id, args.region, args.workspace
    )
    dc_passed, dc_msg = check_developer_connect(
        args.project_id, args.region, args.connection_id, args.workspace
    )

    # Weighted calculation: Artifact Registry = 0.50, Cloud Build = 0.25, DevConnect = 0.25
    score = 0.0
    if ar_passed:
        score += 0.50
    if cb_passed:
        score += 0.25
    if dc_passed:
        score += 0.25

    score = round(score, 2)
    checks = [
        {
            "name": "artifact-registry-used",
            "weight": 0.50,
            "passed": ar_passed,
            "message": ar_msg,
        },
        {
            "name": "cloud-build-used",
            "weight": 0.25,
            "passed": cb_passed,
            "message": cb_msg,
        },
        {
            "name": "developer-connect-used",
            "weight": 0.25,
            "passed": dc_passed,
            "message": dc_msg,
        },
    ]

    print(
        json.dumps(
            {
                "score": score,
                "details": (
                    f"Weighted CI/CD service score: {score:.2f} "
                    f"(AR={ar_passed} [0.50], CB={cb_passed} [0.25], DevConnect={dc_passed} [0.25])"
                ),
                "checks": checks,
            }
        )
    )


if __name__ == "__main__":
    main()
